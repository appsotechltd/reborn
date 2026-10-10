// Package payments confirms gift payments with Stripe (web) and with the
// Apple App Store and Google Play (mobile in-app purchases).
package payments

import "errors"

// Tier is a gift size. Mobile product ids are the same on both stores.
type Tier struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	AmountCents int    `json:"amount_cents"`
	Currency    string `json:"currency"`
	ProductID   string `json:"product_id"`
}

// Tiers is the gift catalogue.
var Tiers = []Tier{
	{ID: "spark", Name: "Spark", AmountCents: 199, Currency: "usd", ProductID: "reborn.gift.spark"},
	{ID: "lamp", Name: "Lamp", AmountCents: 499, Currency: "usd", ProductID: "reborn.gift.lamp"},
	{ID: "sun", Name: "Sun", AmountCents: 999, Currency: "usd", ProductID: "reborn.gift.sun"},
}

// TierByID finds a tier by id.
func TierByID(id string) (Tier, bool) {
	for _, t := range Tiers {
		if t.ID == id {
			return t, true
		}
	}
	return Tier{}, false
}

// TierByProduct finds a tier by store product id.
func TierByProduct(id string) (Tier, bool) {
	for _, t := range Tiers {
		if t.ProductID == id {
			return t, true
		}
	}
	return Tier{}, false
}

// ErrInvalid means a payment proof failed verification.
var ErrInvalid = errors.New("payment could not be verified")

// Plan is a premium subscription plan.
type Plan struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	AmountCents int    `json:"amount_cents"`
	Currency    string `json:"currency"`
	Interval    string `json:"interval"`
	ProductID   string `json:"product_id"` // App Store and Play subscription product id
}

// Plans are the premium plans.
var Plans = []Plan{
	{ID: "monthly", Name: "Premium monthly", AmountCents: 499, Currency: "usd", Interval: "month", ProductID: "reborn.premium.monthly"},
	{ID: "yearly", Name: "Premium yearly", AmountCents: 3999, Currency: "usd", Interval: "year", ProductID: "reborn.premium.yearly"},
}

// PlanByID finds a plan by id.
func PlanByID(id string) (Plan, bool) {
	for _, p := range Plans {
		if p.ID == id {
			return p, true
		}
	}
	return Plan{}, false
}

// PlanByProduct finds a plan by store product id.
func PlanByProduct(id string) (Plan, bool) {
	for _, p := range Plans {
		if p.ProductID == id {
			return p, true
		}
	}
	return Plan{}, false
}
