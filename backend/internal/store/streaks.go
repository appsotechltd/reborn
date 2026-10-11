package store

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// Streak is a user's reading streak. A day counts when they read their daily goal.
type Streak struct {
	Current  int        `json:"current"`
	Longest  int        `json:"longest"`
	Goal     int        `json:"goal"`
	Today    int        `json:"today"` // ideas read today
	GoalMet  bool       `json:"goal_met"`
	LastDays []DayCount `json:"last_days"` // the last 7 local days, oldest first
}

// DayCount is the ideas read on one day.
type DayCount struct {
	Day   string `json:"day"`
	Ideas int    `json:"ideas"`
}

// BumpActivity adds n ideas read to the user's local today and returns how
// many days they have been active in total (any idea read).
func (s *Store) BumpActivity(ctx context.Context, userID string, n int, now time.Time) (activeDays int, err error) {
	if n <= 0 {
		return 0, nil
	}
	err = s.DB.QueryRow(ctx, `WITH up AS (
			INSERT INTO activity_days (user_id, day, ideas)
			SELECT id, ($3::timestamptz AT TIME ZONE timezone)::date, $2 FROM users WHERE id = $1
			ON CONFLICT (user_id, day) DO UPDATE SET ideas = activity_days.ideas + EXCLUDED.ideas
			RETURNING (xmax = 0) AS new_day
		)
		SELECT count(*) + coalesce((SELECT CASE WHEN new_day THEN 1 ELSE 0 END FROM up), 0)
		FROM activity_days WHERE user_id = $1`, userID, n, now).Scan(&activeDays)
	return activeDays, err
}

// StreakOf computes a user's streak as of now in their timezone.
func (s *Store) StreakOf(ctx context.Context, userID string, now time.Time) (Streak, error) {
	var st Streak
	var today time.Time
	if err := s.DB.QueryRow(ctx, `SELECT daily_goal, ($2::timestamptz AT TIME ZONE timezone)::date FROM users WHERE id = $1`,
		userID, now).Scan(&st.Goal, &today); err != nil {
		return st, notFound(err)
	}
	rows, err := s.DB.Query(ctx, `SELECT day, ideas FROM activity_days WHERE user_id = $1 AND day <= $2 ORDER BY day DESC LIMIT 400`, userID, today)
	if err != nil {
		return st, err
	}
	type dayIdeas struct {
		Day   time.Time
		Ideas int
	}
	days, err := pgx.CollectRows(rows, pgx.RowToStructByPos[dayIdeas])
	if err != nil {
		return st, err
	}
	byDay := map[string]int{}
	for _, d := range days {
		byDay[d.Day.Format("2006-01-02")] = d.Ideas
	}
	key := func(t time.Time) string { return t.Format("2006-01-02") }
	st.Today = byDay[key(today)]
	st.GoalMet = st.Today >= st.Goal
	for i := 6; i >= 0; i-- {
		d := today.AddDate(0, 0, -i)
		st.LastDays = append(st.LastDays, DayCount{Day: key(d), Ideas: byDay[key(d)]})
	}
	// The current streak may still be alive through yesterday when today isn't done yet.
	start := today
	if !st.GoalMet {
		start = today.AddDate(0, 0, -1)
	}
	for d := start; byDay[key(d)] >= st.Goal; d = d.AddDate(0, 0, -1) {
		st.Current++
	}
	// Longest run among the days we loaded (oldest last).
	run := 0
	var prev time.Time
	for i := len(days) - 1; i >= 0; i-- {
		d := days[i]
		if d.Ideas < st.Goal {
			run = 0
			continue
		}
		if run > 0 && d.Day.Sub(prev) == 24*time.Hour {
			run++
		} else {
			run = 1
		}
		prev = d.Day
		st.Longest = max(st.Longest, run)
	}
	st.Longest = max(st.Longest, st.Current)
	return st, nil
}
