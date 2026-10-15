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

// UnitPack is a pay-as-you-go top-up of Reborn AI units. Mobile product ids
// are consumable in-app products, the same on both stores.
type UnitPack struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Units       int    `json:"units"`
	AmountCents int    `json:"amount_cents"`
	Currency    string `json:"currency"`
	ProductID   string `json:"product_id"`
}

// UnitPacks are the top-up packs, smallest first.
var UnitPacks = []UnitPack{
	{ID: "units_250", Name: "250 AI units", Units: 250, AmountCents: 299, Currency: "usd", ProductID: "reborn.ai.units250"},
	{ID: "units_600", Name: "600 AI units", Units: 600, AmountCents: 599, Currency: "usd", ProductID: "reborn.ai.units600"},
	{ID: "units_1300", Name: "1,300 AI units", Units: 1300, AmountCents: 1199, Currency: "usd", ProductID: "reborn.ai.units1300"},
}

// PackByID finds a top-up pack by id.
func PackByID(id string) (UnitPack, bool) {
	for _, p := range UnitPacks {
		if p.ID == id {
			return p, true
		}
	}
	return UnitPack{}, false
}

// PackByProduct finds a top-up pack by store product id.
func PackByProduct(id string) (UnitPack, bool) {
	for _, p := range UnitPacks {
		if p.ProductID == id {
			return p, true
		}
	}
	return UnitPack{}, false
}

// Creator gifts: a gift on a card a member wrote is shared with them. The
// payment fee comes off first, then Reborn keeps its commission.

// DefaultCommissionPercent is Reborn's cut of a gift after the payment fee.
const DefaultCommissionPercent = 30

// DefaultStoreFeePercent is what Apple and Google keep from an in-app purchase
// (15% on their small business programmes; 30% otherwise).
const DefaultStoreFeePercent = 15

// Split is how a gift is divided.
type Split struct {
	FeeCents    int `json:"fee_cents"`
	AuthorCents int `json:"author_cents"`
	RebornCents int `json:"reborn_cents"`
}

// SplitGift divides amountCents paid through provider. Stripe charges 2.9% +
// 30c; the app stores keep storeFeePercent. The writer gets the rest less
// commissionPercent, rounded down to the cent.
func SplitGift(amountCents int, provider string, commissionPercent, storeFeePercent int) Split {
	var fee int
	if provider == "stripe" {
		fee = (amountCents*29+999)/1000 + 30
	} else {
		fee = (amountCents*storeFeePercent + 99) / 100
	}
	fee = min(fee, amountCents)
	net := amountCents - fee
	author := net * (100 - commissionPercent) / 100
	return Split{FeeCents: fee, AuthorCents: author, RebornCents: net - author}
}

// WriterTier is a monthly price a writer can charge for their subscribers-only
// cards. On the web it is a Stripe subscription; in the apps it is a 30-day
// pass (an Apple non-renewing subscription, a Google Play one-time product),
// so one member can subscribe to many writers at the same price.
type WriterTier struct {
	ID          string `json:"id"`
	AmountCents int    `json:"amount_cents"`
	Currency    string `json:"currency"`
	ProductID   string `json:"product_id"`
}

// WriterPassDays is how long an in-app subscription pass lasts.
const WriterPassDays = 30

// WriterTiers are the monthly prices writers choose from.
var WriterTiers = []WriterTier{
	{ID: "month_199", AmountCents: 199, Currency: "usd", ProductID: "reborn.writer.month199"},
	{ID: "month_499", AmountCents: 499, Currency: "usd", ProductID: "reborn.writer.month499"},
	{ID: "month_999", AmountCents: 999, Currency: "usd", ProductID: "reborn.writer.month999"},
}

// WriterTierByID finds a writer tier by id.
func WriterTierByID(id string) (WriterTier, bool) {
	for _, t := range WriterTiers {
		if t.ID == id {
			return t, true
		}
	}
	return WriterTier{}, false
}

// WriterTierByProduct finds a writer tier by store product id.
func WriterTierByProduct(id string) (WriterTier, bool) {
	for _, t := range WriterTiers {
		if t.ProductID == id {
			return t, true
		}
	}
	return WriterTier{}, false
}
