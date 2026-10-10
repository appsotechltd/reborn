package srs

import (
	"testing"
	"time"
)

func TestGoodGrowsInterval(t *testing.T) {
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	s := New(now)
	var got []int
	for i := 0; i < 5; i++ {
		s = Next(s, Good, now)
		got = append(got, s.IntervalDays)
	}
	want := []int{1, 3, 8, 20, 50}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("intervals = %v, want %v", got, want)
		}
	}
	if !s.DueAt.Equal(now.Add(50 * 24 * time.Hour)) {
		t.Fatalf("due = %v", s.DueAt)
	}
}

func TestAgainResets(t *testing.T) {
	now := time.Now()
	s := Next(Next(Next(New(now), Good, now), Good, now), Again, now)
	if s.Reps != 0 || s.IntervalDays != 0 || s.Lapses != 1 {
		t.Fatalf("state after again = %+v", s)
	}
	if s.Ease >= 2.5 || s.Ease < 1.3 {
		t.Fatalf("ease = %v", s.Ease)
	}
	if d := s.DueAt.Sub(now); d != 10*time.Minute {
		t.Fatalf("due in %v", d)
	}
}

func TestEaseFloorAndCap(t *testing.T) {
	now := time.Now()
	s := New(now)
	for i := 0; i < 20; i++ {
		s = Next(s, Again, now)
	}
	if s.Ease != 1.3 {
		t.Fatalf("ease floor = %v", s.Ease)
	}
	for i := 0; i < 30; i++ {
		s = Next(s, Easy, now)
	}
	if s.IntervalDays != 365 {
		t.Fatalf("interval cap = %v", s.IntervalDays)
	}
}

func TestValid(t *testing.T) {
	if Grade("meh").Valid() || !Good.Valid() {
		t.Fatal("Valid is wrong")
	}
}
