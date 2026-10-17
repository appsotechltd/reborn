package store

import (
	"context"
	"fmt"

	"github.com/appsotechltd/reborn/backend/internal/cardimages"
	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/jackc/pgx/v5"
)

// Subject is a short course: guides followed one after the other. Each guide
// is read through its summary, so progress comes from summary progress.
type Subject struct {
	ID          string   `json:"id"`
	Title       string   `json:"title"`
	Description string   `json:"description"`
	Topics      []string `json:"topics"`
	GuideCount  int      `json:"guide_count"`
	PartCount   int      `json:"part_count"`
	Minutes     int      `json:"minutes"`
	// Cover is the first guide's cover picture, when it has one.
	Cover  *cardimages.Image `json:"cover,omitempty"`
	Viewer *SubjectProgress  `json:"viewer,omitempty"`
}

// SubjectProgress is how far the signed-in reader is through a subject.
type SubjectProgress struct {
	Started  bool `json:"started"`
	Finished int  `json:"finished"` // guides finished
	Done     bool `json:"done"`     // every guide finished
	// Next is the guide to continue with: the first one not finished yet.
	Next string `json:"next_summary_id,omitempty"`
}

// SubjectDetail is a subject with its guides in order.
type SubjectDetail struct {
	Subject
	Guides []Summary `json:"guides"`
}

// SubjectStep places a summary in its subject, for "Next guide" at the end.
type SubjectStep struct {
	ID    string      `json:"id"`
	Title string      `json:"title"`
	Step  int         `json:"step"` // 1-based
	Count int         `json:"count"`
	Next  *SubjectRef `json:"next,omitempty"`
}

// SubjectRef names a summary briefly.
type SubjectRef struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type subjectRow struct {
	id, title, description string
	topics, summaryIDs     []string
}

// guides returns a subject's published summaries in reading order.
func (s *Store) subjectGuides(ctx context.Context, ids []string, userID string) ([]Summary, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+summaryCols+summaryFrom+`
		WHERE sm.id = ANY($2) AND sm.status = 'published'`, nullableUser(userID), ids)
	if err != nil {
		return nil, err
	}
	got, err := collectSummaries(rows, userID != "")
	if err != nil {
		return nil, err
	}
	byID := map[string]Summary{}
	for _, sm := range got {
		byID[sm.ID] = sm
	}
	out := make([]Summary, 0, len(ids))
	for _, id := range ids {
		if sm, ok := byID[id]; ok {
			out = append(out, sm)
		}
	}
	return out, nil
}

func buildSubject(r subjectRow, guides []Summary, viewer bool) Subject {
	sj := Subject{ID: r.id, Title: r.title, Description: r.description, Topics: r.topics, GuideCount: len(guides)}
	for _, g := range guides {
		sj.PartCount += g.PartCount
		sj.Minutes += g.Minutes
		if sj.Cover == nil {
			sj.Cover = g.Cover
		}
	}
	if viewer {
		p := &SubjectProgress{}
		for _, g := range guides {
			if g.Viewer == nil {
				continue
			}
			if g.Viewer.Started {
				p.Started = true
			}
			if g.Viewer.Finished {
				p.Finished++
			} else if p.Next == "" {
				p.Next = g.ID
			}
		}
		p.Done = len(guides) > 0 && p.Finished == len(guides)
		sj.Viewer = p
	}
	return sj
}

func scanSubjectRows(rows pgx.Rows) ([]subjectRow, error) {
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (subjectRow, error) {
		var sr subjectRow
		err := r.Scan(&sr.id, &sr.title, &sr.description, &sr.topics, &sr.summaryIDs)
		return sr, err
	})
}

// Subjects lists published subjects, those in topic when it is set: subjects
// whose main topic it is come first, then by title.
func (s *Store) Subjects(ctx context.Context, userID, topic string) ([]Subject, error) {
	rows, err := s.DB.Query(ctx, `SELECT id, title, description, topics, summary_ids FROM subjects
		WHERE status = 'published' AND ($1 = '' OR $1 = ANY(topics))
		ORDER BY coalesce(array_position(topics, $1), 1), lower(title), id`, topic)
	if err != nil {
		return nil, err
	}
	srs, err := scanSubjectRows(rows)
	if err != nil {
		return nil, err
	}
	out := make([]Subject, 0, len(srs))
	for _, r := range srs {
		guides, err := s.subjectGuides(ctx, r.summaryIDs, userID)
		if err != nil {
			return nil, err
		}
		out = append(out, buildSubject(r, guides, userID != ""))
	}
	return out, nil
}

// GetSubject returns a published subject with its guides in order.
func (s *Store) GetSubject(ctx context.Context, id, userID string) (SubjectDetail, error) {
	rows, err := s.DB.Query(ctx, `SELECT id, title, description, topics, summary_ids FROM subjects
		WHERE id = $1 AND status = 'published'`, id)
	if err != nil {
		return SubjectDetail{}, err
	}
	srs, err := scanSubjectRows(rows)
	if err != nil {
		return SubjectDetail{}, err
	}
	if len(srs) == 0 {
		return SubjectDetail{}, ErrNotFound
	}
	guides, err := s.subjectGuides(ctx, srs[0].summaryIDs, userID)
	if err != nil {
		return SubjectDetail{}, err
	}
	return SubjectDetail{Subject: buildSubject(srs[0], guides, userID != ""), Guides: guides}, nil
}

// SubjectStepOf returns where a summary sits in its subject, or nil when it
// belongs to none.
func (s *Store) SubjectStepOf(ctx context.Context, summaryID string) (*SubjectStep, error) {
	rows, err := s.DB.Query(ctx, `SELECT id, title, description, topics, summary_ids FROM subjects
		WHERE status = 'published' AND $1 = ANY(summary_ids) ORDER BY id LIMIT 1`, summaryID)
	if err != nil {
		return nil, err
	}
	srs, err := scanSubjectRows(rows)
	if err != nil || len(srs) == 0 {
		return nil, err
	}
	guides, err := s.subjectGuides(ctx, srs[0].summaryIDs, "")
	if err != nil {
		return nil, err
	}
	st := &SubjectStep{ID: srs[0].id, Title: srs[0].title, Count: len(guides)}
	for i, g := range guides {
		if g.ID == summaryID {
			st.Step = i + 1
			if i+1 < len(guides) {
				st.Next = &SubjectRef{ID: guides[i+1].ID, Title: guides[i+1].Title}
			}
		}
	}
	if st.Step == 0 {
		return nil, nil
	}
	return st, nil
}

// seedSubjects upserts the library's subjects and hides ones no longer in it.
// A guide's summary id is its source id.
func seedSubjects(ctx context.Context, tx pgx.Tx, lib content.Library) (int, error) {
	ids := make([]string, 0, len(lib.Subjects))
	for _, sj := range lib.Subjects {
		if _, err := tx.Exec(ctx, `INSERT INTO subjects (id, title, description, topics, summary_ids)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title, description = EXCLUDED.description,
				topics = EXCLUDED.topics, summary_ids = EXCLUDED.summary_ids, status = 'published', updated_at = now()`,
			sj.ID, sj.Title, sj.Description, sj.Topics, sj.Guides); err != nil {
			return 0, fmt.Errorf("subject %s: %w", sj.ID, err)
		}
		ids = append(ids, sj.ID)
	}
	_, err := tx.Exec(ctx, `UPDATE subjects SET status = 'hidden' WHERE NOT (id = ANY($1))`, ids)
	return len(ids), err
}
