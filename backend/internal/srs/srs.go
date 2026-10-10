// Package srs schedules card reviews with a simplified SM-2 algorithm.
package srs

import (
	"math"
	"time"
)

// Grade is how well the user remembered a card.
type Grade string

// Grades, from forgot to effortless.
const (
	Again Grade = "again"
	Hard  Grade = "hard"
	Good  Grade = "good"
	Easy  Grade = "easy"
)

// Valid reports whether g is a known grade.
func (g Grade) Valid() bool { return g == Again || g == Hard || g == Good || g == Easy }

// State is a card's review schedule for one user.
type State struct {
	Ease         float64
	IntervalDays int
	Reps         int
	Lapses       int
	DueAt        time.Time
}

// New returns the state of a card that was just added to review: due tomorrow.
func New(now time.Time) State {
	return State{Ease: 2.5, DueAt: now.Add(24 * time.Hour)}
}

// Next returns the state after grading the card at now.
func Next(s State, g Grade, now time.Time) State {
	if s.Ease == 0 {
		s.Ease = 2.5
	}
	switch g {
	case Again:
		s.Lapses++
		s.Reps = 0
		s.IntervalDays = 0
		s.Ease = math.Max(1.3, s.Ease-0.2)
		s.DueAt = now.Add(10 * time.Minute)
		return s
	case Hard:
		s.Ease = math.Max(1.3, s.Ease-0.15)
		s.IntervalDays = max(1, int(math.Round(float64(s.IntervalDays)*1.2)))
	case Good:
		switch s.Reps {
		case 0:
			s.IntervalDays = 1
		case 1:
			s.IntervalDays = 3
		default:
			s.IntervalDays = max(s.IntervalDays+1, int(math.Round(float64(s.IntervalDays)*s.Ease)))
		}
	case Easy:
		s.Ease += 0.15
		switch s.Reps {
		case 0:
			s.IntervalDays = 3
		default:
			s.IntervalDays = max(s.IntervalDays+2, int(math.Round(float64(max(s.IntervalDays, 1))*s.Ease*1.3)))
		}
	}
	s.IntervalDays = min(s.IntervalDays, 365)
	s.Reps++
	s.DueAt = now.Add(time.Duration(s.IntervalDays) * 24 * time.Hour)
	return s
}
