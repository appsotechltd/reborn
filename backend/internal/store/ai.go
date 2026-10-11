package store

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5"
)

// AIWallet is a member's Reborn AI units: the monthly allowance that comes
// with premium, and top-up units that never expire. Allowance is spent first.
type AIWallet struct {
	MonthlyUnits  int       `json:"monthly_units"`
	AllowanceUsed int       `json:"allowance_used"`
	AllowanceLeft int       `json:"allowance_left"`
	TopUpUnits    int       `json:"topup_units"`
	Remaining     int       `json:"remaining"`
	ResetsAt      time.Time `json:"resets_at"`
}

// monthStart is the first instant (UTC) of the month holding t.
func monthStart(t time.Time) time.Time {
	t = t.UTC()
	return time.Date(t.Year(), t.Month(), 1, 0, 0, 0, 0, time.UTC)
}

func makeWallet(monthly, used, topup int, period time.Time) AIWallet {
	left := max(monthly-used, 0)
	return AIWallet{MonthlyUnits: monthly, AllowanceUsed: used, AllowanceLeft: left, TopUpUnits: topup,
		Remaining: left + topup, ResetsAt: period.AddDate(0, 1, 0)}
}

// lockWallet makes sure the user has a wallet for this month and locks it for the transaction.
func lockWallet(ctx context.Context, tx pgx.Tx, userID string, now time.Time) (used, topup int, period time.Time, err error) {
	start := monthStart(now)
	if _, err = tx.Exec(ctx, `INSERT INTO ai_wallets (user_id, period_start) VALUES ($1, $2) ON CONFLICT (user_id) DO NOTHING`, userID, start); err != nil {
		return
	}
	if err = tx.QueryRow(ctx, `SELECT allowance_used, topup_units, period_start FROM ai_wallets WHERE user_id = $1 FOR UPDATE`, userID).
		Scan(&used, &topup, &period); err != nil {
		return
	}
	if period.Before(start) {
		used, period = 0, start
		_, err = tx.Exec(ctx, `UPDATE ai_wallets SET allowance_used = 0, period_start = $2, updated_at = now() WHERE user_id = $1`, userID, start)
	}
	return
}

// AIWalletOf returns the user's wallet. monthly is the allowance they get this month.
func (s *Store) AIWalletOf(ctx context.Context, userID string, monthly int, now time.Time) (AIWallet, error) {
	var w AIWallet
	err := pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		used, topup, period, err := lockWallet(ctx, tx, userID, now)
		w = makeWallet(monthly, used, topup, period)
		return err
	})
	return w, err
}

// AISpend is how one charge was paid for.
type AISpend struct {
	Units         int `json:"units"`
	FromAllowance int `json:"from_allowance"`
	FromTopUp     int `json:"from_topup"`
}

// SpendAIUnits charges up to units for one action, allowance first, and logs
// it. It never takes more than the wallet holds, so callers check the balance
// before doing paid work; a race between two requests can only undercharge.
func (s *Store) SpendAIUnits(ctx context.Context, userID, kind string, units int, messageID *string, monthly int, now time.Time) (AISpend, AIWallet, error) {
	var sp AISpend
	var w AIWallet
	err := pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		used, topup, period, err := lockWallet(ctx, tx, userID, now)
		if err != nil {
			return err
		}
		sp.FromAllowance = min(max(monthly-used, 0), units)
		sp.FromTopUp = min(topup, units-sp.FromAllowance)
		sp.Units = sp.FromAllowance + sp.FromTopUp
		used, topup = used+sp.FromAllowance, topup-sp.FromTopUp
		w = makeWallet(monthly, used, topup, period)
		if sp.Units == 0 {
			return nil
		}
		if _, err := tx.Exec(ctx, `UPDATE ai_wallets SET allowance_used = $2, topup_units = $3, updated_at = now() WHERE user_id = $1`,
			userID, used, topup); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `INSERT INTO ai_usage (user_id, kind, units, from_allowance, from_topup, message_id, created_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7)`, userID, kind, sp.Units, sp.FromAllowance, sp.FromTopUp, messageID, now)
		return err
	})
	return sp, w, err
}

// AIUsageItem is one charge.
type AIUsageItem struct {
	Kind      string    `json:"kind"`
	Units     int       `json:"units"`
	CreatedAt time.Time `json:"created_at"`
}

// AIUsage lists the user's latest charges.
func (s *Store) AIUsage(ctx context.Context, userID string, limit int) ([]AIUsageItem, error) {
	rows, err := s.DB.Query(ctx, `SELECT kind, units, created_at FROM ai_usage WHERE user_id = $1 ORDER BY created_at DESC, id DESC LIMIT $2`, userID, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (AIUsageItem, error) {
		var it AIUsageItem
		return it, r.Scan(&it.Kind, &it.Units, &it.CreatedAt)
	})
}

// --- conversations ---

// AIConversation is one Reborn AI chat.
type AIConversation struct {
	ID        string    `json:"id"`
	Title     string    `json:"title"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// AIMessage is one turn in a chat. Attachments is a JSON array of pictures and charts.
type AIMessage struct {
	ID          string          `json:"id"`
	Role        string          `json:"role"`
	Content     string          `json:"content"`
	Voice       bool            `json:"voice"`
	CitationIDs []string        `json:"-"`
	Citations   []Card          `json:"citations"`
	Attachments json.RawMessage `json:"attachments"`
	Units       int             `json:"units"`
	CreatedAt   time.Time       `json:"created_at"`
}

// CreateAIConversation starts a chat.
func (s *Store) CreateAIConversation(ctx context.Context, userID, title string, now time.Time) (AIConversation, error) {
	var c AIConversation
	err := s.DB.QueryRow(ctx, `INSERT INTO ai_conversations (user_id, title, created_at, updated_at) VALUES ($1, $2, $3, $3)
		RETURNING id::text, title, created_at, updated_at`, userID, title, now).Scan(&c.ID, &c.Title, &c.CreatedAt, &c.UpdatedAt)
	return c, err
}

// AIConversationOf returns one of the user's chats.
func (s *Store) AIConversationOf(ctx context.Context, userID, id string) (AIConversation, error) {
	var c AIConversation
	err := s.DB.QueryRow(ctx, `SELECT id::text, title, created_at, updated_at FROM ai_conversations WHERE id::text = $1 AND user_id = $2`,
		id, userID).Scan(&c.ID, &c.Title, &c.CreatedAt, &c.UpdatedAt)
	return c, notFound(err)
}

// AIConversations lists the user's chats, most recent first.
func (s *Store) AIConversations(ctx context.Context, userID string, limit int) ([]AIConversation, error) {
	rows, err := s.DB.Query(ctx, `SELECT id::text, title, created_at, updated_at FROM ai_conversations
		WHERE user_id = $1 ORDER BY updated_at DESC LIMIT $2`, userID, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (AIConversation, error) {
		var c AIConversation
		return c, r.Scan(&c.ID, &c.Title, &c.CreatedAt, &c.UpdatedAt)
	})
}

// DeleteAIConversation removes a chat and its messages.
func (s *Store) DeleteAIConversation(ctx context.Context, userID, id string) error {
	tag, err := s.DB.Exec(ctx, `DELETE FROM ai_conversations WHERE id::text = $1 AND user_id = $2`, id, userID)
	if err == nil && tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return err
}

const aiMessageCols = `m.id::text, m.role, m.content, m.voice, m.citations, m.attachments, m.units, m.created_at`

func scanAIMessage(r pgx.Row) (AIMessage, error) {
	var m AIMessage
	err := r.Scan(&m.ID, &m.Role, &m.Content, &m.Voice, &m.CitationIDs, &m.Attachments, &m.Units, &m.CreatedAt)
	return m, err
}

// AIMessages returns a chat's last limit messages, oldest first, with cited cards filled in.
func (s *Store) AIMessages(ctx context.Context, conversationID string, limit int) ([]AIMessage, error) {
	rows, err := s.DB.Query(ctx, `SELECT * FROM (SELECT `+aiMessageCols+` FROM ai_messages m
		WHERE m.conversation_id::text = $1 ORDER BY m.created_at DESC LIMIT $2) t ORDER BY created_at`, conversationID, limit)
	if err != nil {
		return nil, err
	}
	msgs, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (AIMessage, error) { return scanAIMessage(r) })
	if err != nil {
		return nil, err
	}
	for i := range msgs {
		if msgs[i].Citations, err = s.fillCitations(ctx, msgs[i].CitationIDs); err != nil {
			return nil, err
		}
	}
	return msgs, nil
}

func (s *Store) fillCitations(ctx context.Context, ids []string) ([]Card, error) {
	if len(ids) == 0 {
		return []Card{}, nil
	}
	cards, err := s.GetCards(ctx, ids)
	if err != nil {
		return nil, err
	}
	byID := map[string]Card{}
	for _, c := range cards {
		byID[c.ID] = c
	}
	out := []Card{}
	for _, id := range ids {
		if c, ok := byID[id]; ok {
			out = append(out, c)
		}
	}
	return out, nil
}

// AIMessageOf returns one message from the user's chats.
func (s *Store) AIMessageOf(ctx context.Context, userID, id string) (AIMessage, error) {
	m, err := scanAIMessage(s.DB.QueryRow(ctx, `SELECT `+aiMessageCols+` FROM ai_messages m
		JOIN ai_conversations c ON c.id = m.conversation_id WHERE m.id::text = $1 AND c.user_id = $2`, id, userID))
	if err != nil {
		return m, notFound(err)
	}
	m.Citations, err = s.fillCitations(ctx, m.CitationIDs)
	return m, err
}

// AddAIMessage appends a message to a chat and marks the chat as updated.
func (s *Store) AddAIMessage(ctx context.Context, conversationID string, m AIMessage, now time.Time) (AIMessage, error) {
	if m.CitationIDs == nil {
		m.CitationIDs = []string{}
	}
	if len(m.Attachments) == 0 {
		m.Attachments = json.RawMessage("[]")
	}
	err := pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `INSERT INTO ai_messages (conversation_id, role, content, voice, citations, attachments, units, created_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id::text, created_at`,
			conversationID, m.Role, m.Content, m.Voice, m.CitationIDs, m.Attachments, m.Units, now).Scan(&m.ID, &m.CreatedAt); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE ai_conversations SET updated_at = $2 WHERE id::text = $1`, conversationID, now)
		return err
	})
	if m.Citations == nil {
		m.Citations = []Card{}
	}
	return m, err
}

// AddAIMessageUnits adds units charged after a message was saved (for example, reading it aloud).
func (s *Store) AddAIMessageUnits(ctx context.Context, id string, units int) error {
	_, err := s.DB.Exec(ctx, `UPDATE ai_messages SET units = units + $2 WHERE id::text = $1`, id, units)
	return err
}

// --- top-ups ---

// AITopUp is one purchase of a unit pack.
type AITopUp struct {
	ID          string     `json:"id"`
	Pack        string     `json:"pack"`
	Units       int        `json:"units"`
	AmountCents int        `json:"amount_cents"`
	Currency    string     `json:"currency"`
	Provider    string     `json:"provider"`
	Status      string     `json:"status"`
	CreatedAt   time.Time  `json:"created_at"`
	PaidAt      *time.Time `json:"paid_at"`
}

const topUpCols = `id::text, pack, units, amount_cents, currency, provider, status, created_at, paid_at`

func scanTopUp(r pgx.Row) (AITopUp, error) {
	var t AITopUp
	err := r.Scan(&t.ID, &t.Pack, &t.Units, &t.AmountCents, &t.Currency, &t.Provider, &t.Status, &t.CreatedAt, &t.PaidAt)
	return t, err
}

// NewAITopUp is a top-up to record.
type NewAITopUp struct {
	UserID      string
	Pack        string
	Units       int
	AmountCents int
	Currency    string
	Provider    string
}

// CreatePendingTopUp records a top-up whose payment has started.
func (s *Store) CreatePendingTopUp(ctx context.Context, t NewAITopUp) (AITopUp, error) {
	return scanTopUp(s.DB.QueryRow(ctx, `INSERT INTO ai_topups (user_id, pack, units, amount_cents, currency, provider)
		VALUES ($1, $2, $3, $4, $5, $6) RETURNING `+topUpCols, t.UserID, t.Pack, t.Units, t.AmountCents, t.Currency, t.Provider))
}

// SetTopUpRef stores the payment provider's id for a pending top-up.
func (s *Store) SetTopUpRef(ctx context.Context, id, ref string) error {
	_, err := s.DB.Exec(ctx, `UPDATE ai_topups SET provider_ref = $2 WHERE id::text = $1`, id, ref)
	return err
}

func creditTopUp(ctx context.Context, tx pgx.Tx, userID *string, units int, now time.Time) error {
	if userID == nil {
		return nil // the account was deleted
	}
	_, err := tx.Exec(ctx, `INSERT INTO ai_wallets (user_id, period_start, topup_units) VALUES ($1, $2, $3)
		ON CONFLICT (user_id) DO UPDATE SET topup_units = ai_wallets.topup_units + EXCLUDED.topup_units, updated_at = now()`,
		*userID, monthStart(now), units)
	return err
}

// MarkTopUpPaid marks a pending top-up as paid and credits its units, once.
func (s *Store) MarkTopUpPaid(ctx context.Context, id, provider, ref string, now time.Time) error {
	return pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		var userID *string
		var units int
		err := tx.QueryRow(ctx, `UPDATE ai_topups SET status = 'paid', paid_at = $4, provider_ref = coalesce(provider_ref, $3)
			WHERE id::text = $1 AND provider = $2 AND status = 'pending' RETURNING user_id::text, units`, id, provider, ref, now).Scan(&userID, &units)
		if err == pgx.ErrNoRows {
			return nil // already paid, or not ours
		}
		if err != nil {
			return err
		}
		return creditTopUp(ctx, tx, userID, units, now)
	})
}

// RecordPaidTopUp stores a top-up a store already confirmed and credits it.
// The same store transaction is only ever credited once; a repeat returns the first top-up.
func (s *Store) RecordPaidTopUp(ctx context.Context, t NewAITopUp, ref string, now time.Time) (AITopUp, error) {
	var out AITopUp
	err := pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `INSERT INTO ai_topups (user_id, pack, units, amount_cents, currency, provider, provider_ref, status, paid_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, 'paid', $8) ON CONFLICT (provider, provider_ref) DO NOTHING`,
			t.UserID, t.Pack, t.Units, t.AmountCents, t.Currency, t.Provider, ref, now)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 1 {
			if err := creditTopUp(ctx, tx, &t.UserID, t.Units, now); err != nil {
				return err
			}
		}
		out, err = scanTopUp(tx.QueryRow(ctx, `SELECT `+topUpCols+` FROM ai_topups WHERE provider = $1 AND provider_ref = $2`, t.Provider, ref))
		return err
	})
	return out, err
}

// TopUpOf returns one of the user's top-ups.
func (s *Store) TopUpOf(ctx context.Context, userID, id string) (AITopUp, error) {
	t, err := scanTopUp(s.DB.QueryRow(ctx, `SELECT `+topUpCols+` FROM ai_topups WHERE id::text = $1 AND user_id = $2`, id, userID))
	return t, notFound(err)
}
