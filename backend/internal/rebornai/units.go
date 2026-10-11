// Package rebornai is Reborn AI, the premium chat assistant. It talks and
// listens, searches the card library, draws charts and makes pictures, using
// OpenAI's API. Every action costs AI units at its own rate.
//
// One unit covers about $0.005 of OpenAI cost. The rates and the reasoning
// behind them are in docs/AI_UNITS.md.
package rebornai

import (
	"regexp"
	"strings"
)

// Kinds of charge. They match the ai_usage.kind column.
const (
	KindText         = "text"
	KindChart        = "chart"
	KindVoice        = "voice"
	KindSketch       = "sketch"
	KindIllustration = "illustration"
	KindPicture      = "picture"
)

// Rate is what one action costs.
type Rate struct {
	Kind  string `json:"kind"`
	Units int    `json:"units"`
	Per   string `json:"per"` // what one charge covers, for display
}

// Rates are the unit prices, in display order.
var Rates = []Rate{
	{KindText, 1, "reply"},
	{KindChart, 1, "chart or graph"},
	{KindVoice, 1, "30 spoken words (about 12 seconds)"},
	{KindSketch, 2, "sketch"},
	{KindIllustration, 4, "illustration"},
	{KindPicture, 12, "picture"},
}

// UnitsFor returns the rate for a kind.
func UnitsFor(kind string) int {
	for _, r := range Rates {
		if r.Kind == kind {
			return r.Units
		}
	}
	return 0
}

// wordsPerVoiceUnit is how many spoken words one voice unit covers. People
// speak about 150 words a minute, so a minute of speech is 5 units.
const wordsPerVoiceUnit = 30

// VoiceUnits is what speaking or hearing text costs: one unit per started 30 words.
func VoiceUnits(text string) int {
	n := len(strings.Fields(text))
	if n == 0 {
		return 0
	}
	return (n + wordsPerVoiceUnit - 1) / wordsPerVoiceUnit
}

var (
	citationRe = regexp.MustCompile(`\s*\[[a-z0-9]+(?:-[a-z0-9]+)*--[0-9]{2,3}\]`)
	markdownRe = regexp.MustCompile("[*_#`>]+")
)

// Spoken turns a reply into text fit to read aloud: no card ids or markdown.
func Spoken(text string) string {
	text = citationRe.ReplaceAllString(text, "")
	text = markdownRe.ReplaceAllString(text, "")
	return strings.Join(strings.Fields(text), " ")
}
