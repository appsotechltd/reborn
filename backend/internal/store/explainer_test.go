package store

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/appsotechltd/reborn/backend/internal/explainers"
)

func TestFinishCardAttachesExplainer(t *testing.T) {
	SetExplainers(explainers.Set{"a--01": {Kind: "animated", VideoURL: "/media/explainers/a--01.mp4"}})
	t.Cleanup(func() { SetExplainers(nil) })

	with, err := finishCard(Card{ID: "a--01"}, nil)
	if err != nil || with.Explainer == nil || with.Explainer.VideoURL != "/media/explainers/a--01.mp4" {
		t.Fatalf("explainer not attached: %+v %v", with.Explainer, err)
	}
	without, _ := finishCard(Card{ID: "b--01"}, nil)
	raw, _ := json.Marshal(without)
	if without.Explainer != nil || strings.Contains(string(raw), "explainer") {
		t.Fatalf("card without a video must omit the field: %s", raw)
	}
}
