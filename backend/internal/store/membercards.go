package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"regexp"
	"strings"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/cardaudio"
	"github.com/appsotechltd/reborn/backend/internal/cardimages"
	"github.com/jackc/pgx/v5"
)

// MembersSource is the shared source every member card belongs to.
const MembersSource = "reborn-members"

// everyoneOnly is a SQL condition true for cards anyone may see.
const everyoneOnly = `c.audience = 'everyone'`

// visibleTo is a SQL condition true when the viewer (a uuid parameter, which
// may be NULL) may see the published card: it is for everyone, the viewer
// wrote it, it is for followers and the viewer follows its writer, or the
// viewer has a live subscription to its writer (which also opens followers-only cards).
func visibleTo(viewerParam string) string {
	v := viewerParam + `::uuid`
	return `(c.audience = 'everyone' OR c.author_id = ` + v + `
		OR (c.audience = 'followers' AND EXISTS (SELECT 1 FROM follows fl
			WHERE fl.follower_id = ` + v + ` AND fl.kind = 'user' AND fl.target = c.author_id::text))
		OR EXISTS (SELECT 1 FROM writer_subscriptions wsv
			WHERE wsv.subscriber_id = ` + v + ` AND wsv.writer_id = c.author_id AND wsv.expires_at > now()))`
}

// Audiences are who a member's card can be shown to.
var Audiences = []string{"everyone", "followers", "subscribers", "private"}

// ErrLimit means a member reached the most they can keep.
var ErrLimit = errors.New("limit reached")

// Limits on what one member can keep.
const (
	MaxMemberCards      = 2000
	MaxMemberCategories = 50
)

// MemberCategory is one of a member's own categories for their cards.
type MemberCategory struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	CardCount *int   `json:"card_count,omitempty"`
}

// MemberImage is an AI-made picture on a member card.
type MemberImage struct {
	URL    string `json:"url"`
	Style  string `json:"style"` // sketch, illustration or picture
	Width  int    `json:"width"`
	Height int    `json:"height"`
	Prompt string `json:"prompt,omitempty"`
}

// MemberAudio is a member card read aloud.
type MemberAudio struct {
	URL       string  `json:"url"`
	Voice     string  `json:"voice"`
	DurationS float64 `json:"duration_s"`
	TextHash  string  `json:"text_hash"`
}

// VideoScene is one illustration in an illustrated video.
type VideoScene struct {
	URL    string `json:"url"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
}

// MemberVideo is an illustrated video: illustrations that drift and fade in
// turn, each shown for an equal share of the narration. The apps play it.
type MemberVideo struct {
	Kind      string       `json:"kind"` // "illustrated"
	Scenes    []VideoScene `json:"scenes"`
	AudioURL  string       `json:"audio_url"`
	Voice     string       `json:"voice"`
	DurationS float64      `json:"duration_s"`
	TextHash  string       `json:"text_hash"`
}

// MemberMedia is what is stored in cards.media.
type MemberMedia struct {
	Image *MemberImage `json:"image,omitempty"`
	Audio *MemberAudio `json:"audio,omitempty"`
	Video *MemberVideo `json:"video,omitempty"`
}

type memberScan struct {
	authorID, handle, name   *string
	categoryID, categoryName *string
	media                    []byte
	status, audience         string
	createdAt                time.Time
}

// SpokenSeconds estimates how long text takes to read aloud (about 150 words a minute).
func SpokenSeconds(text string) float64 {
	return float64(len(strings.Fields(text))) / 2.5
}

func finishMemberCard(c *Card) {
	m := c.member
	c.member = nil
	c.Author = &Profile{ID: *m.authorID}
	if m.handle != nil {
		c.Author.Handle = *m.handle
	}
	if m.name != nil {
		c.Author.DisplayName = *m.name
	}
	if m.categoryID != nil && m.categoryName != nil {
		c.Category = &MemberCategory{ID: *m.categoryID, Name: *m.categoryName}
	}
	c.Visibility = m.status // private, hidden or deleted
	if m.status == "published" {
		c.Visibility = m.audience // everyone or followers
	}
	created := m.createdAt
	c.CreatedAt = &created
	c.Credit = "Written by " + c.Author.DisplayName + " on Reborn"
	c.Source.Authors = []string{c.Author.DisplayName}
	c.Explainer, c.Audio, c.Image = nil, nil, nil
	var media MemberMedia
	if len(m.media) > 0 && json.Unmarshal(m.media, &media) == nil {
		if media.Image != nil {
			c.Image = &cardimages.Image{URL: media.Image.URL, Type: "illustration", Caption: "Made with Reborn AI"}
		}
		if media.Audio != nil {
			c.Audio = &cardaudio.Audio{URL: media.Audio.URL, DurationS: media.Audio.DurationS, Voice: media.Audio.Voice,
				VoiceName: VoiceName(media.Audio.Voice)}
		}
		c.Video = media.Video
	}
}

// Voices are the approved voices members can pick for their cards.
var Voices = []struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}{
	{"af_heart", "Heart"}, {"af_bella", "Bella"}, {"bf_emma", "Emma"}, {"am_michael", "Michael"},
	{"bm_george", "George"}, {"af_sarah", "Sarah"}, {"af_alloy", "Alloy"}, {"af_nova", "Nova"},
	{"am_adam", "Adam"}, {"am_echo", "Echo"}, {"am_eric", "Eric"}, {"am_liam", "Liam"},
}

// VoiceName is a voice's display name, or "" when it isn't an approved voice.
func VoiceName(id string) string {
	for _, v := range Voices {
		if v.ID == id {
			return v.Name
		}
	}
	return ""
}

// --- categories ---

// MemberCategories lists a member's categories with how many cards each holds.
// Only public cards are counted unless all is set.
func (s *Store) MemberCategories(ctx context.Context, userID string, all bool) ([]MemberCategory, error) {
	rows, err := s.DB.Query(ctx, `SELECT mc.id::text, mc.name,
			(SELECT count(*) FROM cards c WHERE c.category_id = mc.id AND (c.status = 'published' OR ($2 AND c.status = 'private')))::int
		FROM member_categories mc WHERE mc.user_id::text = $1 ORDER BY lower(mc.name)`, userID, all)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (MemberCategory, error) {
		var c MemberCategory
		var n int
		err := r.Scan(&c.ID, &c.Name, &n)
		c.CardCount = &n
		return c, err
	})
}

// CreateMemberCategory adds a category; ErrConflict means the name is taken.
func (s *Store) CreateMemberCategory(ctx context.Context, userID, name string) (MemberCategory, error) {
	var c MemberCategory
	var n int
	if err := s.DB.QueryRow(ctx, `SELECT count(*) FROM member_categories WHERE user_id = $1`, userID).Scan(&n); err != nil {
		return c, err
	}
	if n >= MaxMemberCategories {
		return c, ErrLimit
	}
	err := s.DB.QueryRow(ctx, `INSERT INTO member_categories (user_id, name) VALUES ($1, $2) RETURNING id::text, name`,
		userID, name).Scan(&c.ID, &c.Name)
	zero := 0
	c.CardCount = &zero
	return c, conflictOr(err)
}

// RenameMemberCategory renames one of the member's categories.
func (s *Store) RenameMemberCategory(ctx context.Context, userID, id, name string) (MemberCategory, error) {
	var c MemberCategory
	err := s.DB.QueryRow(ctx, `UPDATE member_categories SET name = $3 WHERE id::text = $1 AND user_id = $2 RETURNING id::text, name`,
		id, userID, name).Scan(&c.ID, &c.Name)
	return c, conflictOr(err)
}

// DeleteMemberCategory removes a category; its cards stay, uncategorised.
func (s *Store) DeleteMemberCategory(ctx context.Context, userID, id string) error {
	tag, err := s.DB.Exec(ctx, `DELETE FROM member_categories WHERE id::text = $1 AND user_id = $2`, id, userID)
	if err == nil && tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return err
}

func (s *Store) ownsCategory(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, userID string, id *string) error {
	if id == nil || *id == "" {
		return nil
	}
	var ok bool
	if err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM member_categories WHERE id::text = $1 AND user_id = $2)`, *id, userID).Scan(&ok); err != nil {
		return err
	}
	if !ok {
		return ErrNotFound
	}
	return nil
}

// --- cards ---

// MemberCardInput is what a member writes. Nil fields are left as they are on update.
type MemberCardInput struct {
	Title      *string
	Body       *string
	ApplyIt    *string
	Topic      *string
	CategoryID *string // "" clears it
	Audience   *string // everyone, followers, subscribers or private
}

// statusAudience maps an audience to the card's status and audience columns.
func statusAudience(a string) (status, audience string) {
	switch a {
	case "private":
		return "private", "everyone"
	case "followers", "subscribers":
		return "published", a
	}
	return "published", "everyone"
}

var slugRe = regexp.MustCompile(`[^a-z0-9]+`)

// memberCardID makes a readable, unique card id like "my-morning-walk-k3x9p--01".
func memberCardID(title string) string {
	slug := strings.Trim(slugRe.ReplaceAllString(strings.ToLower(title), "-"), "-")
	if len(slug) > 40 {
		slug = strings.Trim(slug[:40], "-")
	}
	if slug == "" {
		slug = "idea"
	}
	b := make([]byte, 5)
	_, _ = rand.Read(b)
	const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
	for i := range b {
		b[i] = alphabet[int(b[i])%len(alphabet)]
	}
	return slug + "-" + string(b) + "--01"
}

func memberHash(title, body, applyIt string) string {
	sum := sha256.Sum256([]byte(title + "\n" + body + "\n" + applyIt))
	return hex.EncodeToString(sum[:])
}

// CreateMemberCard saves a card a member wrote.
func (s *Store) CreateMemberCard(ctx context.Context, userID string, in MemberCardInput) (Card, error) {
	var id string
	err := withTx(ctx, s.DB, func(tx pgx.Tx) error {
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM cards WHERE author_id = $1 AND status <> 'deleted'`, userID).Scan(&n); err != nil {
			return err
		}
		if n >= MaxMemberCards {
			return ErrLimit
		}
		if err := s.ownsCategory(ctx, tx, userID, in.CategoryID); err != nil {
			return err
		}
		status, audience := statusAudience("everyone")
		if in.Audience != nil {
			status, audience = statusAudience(*in.Audience)
		}
		var cat any
		if in.CategoryID != nil && *in.CategoryID != "" {
			cat = *in.CategoryID
		}
		id = memberCardID(*in.Title)
		_, err := tx.Exec(ctx, `INSERT INTO cards (id, source_id, topic, title, body, apply_it, health, content_hash, author_id, category_id, status, audience)
			VALUES ($1, $2, $3, $4, $5, $6, $3 = 'health', $7, $8, $9::uuid, $10, $11)`,
			id, MembersSource, *in.Topic, *in.Title, *in.Body, *in.ApplyIt, memberHash(*in.Title, *in.Body, *in.ApplyIt), userID, cat, status, audience)
		return err
	})
	if err != nil {
		return Card{}, err
	}
	return s.MemberCard(ctx, userID, id)
}

// MemberCard returns one of the member's own cards, whatever its visibility.
func (s *Store) MemberCard(ctx context.Context, userID, id string) (Card, error) {
	c, err := scanCard(s.DB.QueryRow(ctx, `SELECT `+cardCols+cardFrom+`WHERE c.id = $1 AND c.author_id = $2 AND c.status <> 'deleted'`, id, userID))
	return c, notFound(err)
}

// UpdateMemberCard edits one of the member's cards. A card a moderator took
// down stays hidden.
func (s *Store) UpdateMemberCard(ctx context.Context, userID, id string, in MemberCardInput) (Card, error) {
	err := withTx(ctx, s.DB, func(tx pgx.Tx) error {
		if err := s.ownsCategory(ctx, tx, userID, in.CategoryID); err != nil {
			return err
		}
		var title, body, applyIt, topic, status, audience string
		err := tx.QueryRow(ctx, `SELECT title, body, apply_it, topic, status, audience FROM cards
			WHERE id = $1 AND author_id = $2 AND status <> 'deleted' FOR UPDATE`, id, userID).Scan(&title, &body, &applyIt, &topic, &status, &audience)
		if err != nil {
			return notFound(err)
		}
		set := func(dst *string, v *string) {
			if v != nil {
				*dst = *v
			}
		}
		set(&title, in.Title)
		set(&body, in.Body)
		set(&applyIt, in.ApplyIt)
		set(&topic, in.Topic)
		if in.Audience != nil {
			st, au := statusAudience(*in.Audience)
			audience = au
			if status != "hidden" { // a card taken down stays down
				status = st
			}
		}
		if _, err := tx.Exec(ctx, `UPDATE cards SET title = $3, body = $4, apply_it = $5, topic = $6, health = $6 = 'health', status = $7,
			audience = $9, content_hash = $8, updated_at = CASE WHEN content_hash = $8 THEN updated_at ELSE now() END
			WHERE id = $1 AND author_id = $2`, id, userID, title, body, applyIt, topic, status, memberHash(title, body, applyIt), audience); err != nil {
			return err
		}
		if in.CategoryID != nil {
			var cat any
			if *in.CategoryID != "" {
				cat = *in.CategoryID
			}
			_, err = tx.Exec(ctx, `UPDATE cards SET category_id = $3::uuid WHERE id = $1 AND author_id = $2`, id, userID, cat)
		}
		return err
	})
	if err != nil {
		return Card{}, err
	}
	return s.MemberCard(ctx, userID, id)
}

// DeleteMemberCard deletes one of the member's cards for good, with its
// reactions, comments and favourites. Gifts already paid keep their record.
func (s *Store) DeleteMemberCard(ctx context.Context, userID, id string) error {
	return withTx(ctx, s.DB, func(tx pgx.Tx) error {
		var paid bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM gifts WHERE card_id = $1 AND status = 'paid')`, id).Scan(&paid); err != nil {
			return err
		}
		if paid {
			// Gifts reference the card, so a gifted card is emptied and hidden instead.
			tag, err := tx.Exec(ctx, `UPDATE cards SET status = 'deleted', body = '', apply_it = '', media = '{}',
				category_id = NULL WHERE id = $1 AND author_id = $2`, id, userID)
			if err == nil && tag.RowsAffected() == 0 {
				return ErrNotFound
			}
			return err
		}
		tag, err := tx.Exec(ctx, `DELETE FROM cards WHERE id = $1 AND author_id = $2`, id, userID)
		if err == nil && tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return err
	})
}

// MemberCardsParams selects a member's cards.
type MemberCardsParams struct {
	AuthorID   string
	CategoryID string // "none" for uncategorised cards
	All        bool   // include private and hidden cards (the writer's own view)
	Offset     int
	Limit      int
}

// MemberCards lists a member's cards, newest first.
func (s *Store) MemberCards(ctx context.Context, p MemberCardsParams) ([]Card, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+cardCols+cardFrom+`
		WHERE c.author_id::text = $1 AND (c.status = 'published' OR ($2 AND c.status <> 'deleted'))
		AND ($3 = '' OR ($3 = 'none' AND c.category_id IS NULL) OR c.category_id::text = $3)
		ORDER BY c.created_at DESC, c.id OFFSET $4 LIMIT $5`, p.AuthorID, p.All, p.CategoryID, p.Offset, p.Limit)
	if err != nil {
		return nil, err
	}
	return collectCards(rows)
}

// MemberPosts lists a member's public cards as posts, newest first.
func (s *Store) MemberPosts(ctx context.Context, authorID, categoryID, viewerID string, offset, limit int) ([]Post, error) {
	posts, err := s.queryPosts(ctx, viewerID, `SELECT `+postCols+postFrom+`
		WHERE c.author_id::text = $1 AND c.status = 'published' AND `+visibleTo("$5")+` AND ($2 = '' OR c.category_id::text = $2)
		ORDER BY c.published_at DESC, c.id OFFSET $3 LIMIT $4`, authorID, categoryID, offset, limit, nullableUser(viewerID))
	return posts, err
}

// SetMemberMedia stores one kind of media (image, audio or video) on the
// member's card; nil removes it.
func (s *Store) SetMemberMedia(ctx context.Context, userID, id, kind string, v any) (Card, error) {
	var tag interface{ RowsAffected() int64 }
	var err error
	if v == nil {
		tag, err = s.DB.Exec(ctx, `UPDATE cards SET media = media - $3::text, updated_at = now() WHERE id = $1 AND author_id = $2`, id, userID, kind)
	} else {
		raw, merr := json.Marshal(v)
		if merr != nil {
			return Card{}, merr
		}
		tag, err = s.DB.Exec(ctx, `UPDATE cards SET media = jsonb_set(media, ARRAY[$3::text], $4::jsonb), updated_at = now()
			WHERE id = $1 AND author_id = $2`, id, userID, kind, raw)
	}
	if err != nil {
		return Card{}, err
	}
	if tag.RowsAffected() == 0 {
		return Card{}, ErrNotFound
	}
	return s.MemberCard(ctx, userID, id)
}

// MemberMediaOf returns the stored media of the member's card.
func (s *Store) MemberMediaOf(ctx context.Context, userID, id string) (MemberMedia, error) {
	var raw []byte
	var m MemberMedia
	if err := s.DB.QueryRow(ctx, `SELECT media FROM cards WHERE id = $1 AND author_id = $2`, id, userID).Scan(&raw); err != nil {
		return m, notFound(err)
	}
	err := json.Unmarshal(raw, &m)
	return m, err
}

// --- collections ---

// MemberCardCount is how many cards a member has written, public and all.
func (s *Store) MemberCardCount(ctx context.Context, userID string) (public, all int, err error) {
	err = s.DB.QueryRow(ctx, `SELECT count(*) FILTER (WHERE status = 'published'), count(*) FILTER (WHERE status <> 'deleted')
		FROM cards WHERE author_id::text = $1`, userID).Scan(&public, &all)
	return
}

// --- reports ---

// ReportCard records a report on a member's card and takes the card down once
// enough people report it, until a moderator looks.
func (s *Store) ReportCard(ctx context.Context, userID, id, reason string) error {
	return withTx(ctx, s.DB, func(tx pgx.Tx) error {
		var author *string
		if err := tx.QueryRow(ctx, `SELECT author_id::text FROM cards WHERE id = $1 AND status = 'published'`, id).Scan(&author); err != nil {
			return notFound(err)
		}
		if author == nil {
			return ErrNotFound // library cards are checked by the team, not reported
		}
		tag, err := tx.Exec(ctx, `INSERT INTO card_reports (card_id, user_id, reason) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`, id, userID, reason)
		if err != nil || tag.RowsAffected() == 0 {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE cards SET status = 'hidden' WHERE id = $1
			AND (SELECT count(*) FROM card_reports WHERE card_id = $1) >= $2`, id, ReportsToHide)
		return err
	})
}

// ReportedCard is a member card in the moderation queue.
type ReportedCard struct {
	Card    Card     `json:"card"`
	Status  string   `json:"status"`
	Reports int      `json:"reports"`
	Reasons []string `json:"reasons"`
}

// ReportedCards lists member cards with reports a moderator has not cleared, most reported first.
func (s *Store) ReportedCards(ctx context.Context) ([]ReportedCard, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+cardCols+`, x.n, x.reasons`+cardFrom+`
		JOIN (SELECT card_id, count(*)::int AS n, array_remove(array_agg(reason), '') AS reasons FROM card_reports GROUP BY card_id) x
			ON x.card_id = c.id
		ORDER BY x.n DESC, c.created_at LIMIT 200`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ReportedCard{}
	for rows.Next() {
		var rc ReportedCard
		c, err := scanCardWith(rows, &rc.Reports, &rc.Reasons)
		if err != nil {
			return nil, err
		}
		rc.Card, rc.Status = c, c.Visibility
		if rc.Reasons == nil {
			rc.Reasons = []string{}
		}
		out = append(out, rc)
	}
	return out, rows.Err()
}

// ModerateCard takes a member card down or puts it back; either way its reports are cleared.
func (s *Store) ModerateCard(ctx context.Context, id string, hide bool) error {
	return withTx(ctx, s.DB, func(tx pgx.Tx) error {
		status := "published"
		if hide {
			status = "hidden"
		}
		tag, err := tx.Exec(ctx, `UPDATE cards SET status = $2 WHERE id = $1 AND author_id IS NOT NULL`, id, status)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		_, err = tx.Exec(ctx, `DELETE FROM card_reports WHERE card_id = $1`, id)
		return err
	})
}
