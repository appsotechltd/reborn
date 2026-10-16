package cardimages

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/appsotechltd/reborn/backend/internal/objstore"
)

// Post is a card's image post: one designed 4:5 picture carrying the card's title over
// a painted scene, shown in the feed in place of the text preview.
//
// content/images/posts.json lists, per card id, the picture's path in the media store
// (images/posts/v1/<card-id>.jpg) and its size. The API adds a "post_image" object to
// every card that has one.
type Post struct {
	URL    string `json:"url"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
	Alt    string `json:"alt"`
}

// Posts maps card ids to their image post.
type Posts map[string]Post

type postManifest struct {
	Version int `json:"version"`
	Cards   map[string]struct {
		File   string `json:"file"`
		Width  int    `json:"width"`
		Height int    `json:"height"`
		Alt    string `json:"alt"`
	} `json:"cards"`
}

// LoadPosts reads dir/posts.json, like Load: a missing manifest gives no posts, and on
// local disk a post whose file was never copied into MEDIA_DIR is left out.
func LoadPosts(ctx context.Context, dir string, media objstore.Store) (Posts, error) {
	set := Posts{}
	if dir == "" || media == nil {
		return set, nil
	}
	raw, err := os.ReadFile(filepath.Join(dir, "posts.json"))
	if errors.Is(err, fs.ErrNotExist) {
		return set, nil
	}
	if err != nil {
		return nil, err
	}
	var m postManifest
	if err := json.Unmarshal(raw, &m); err != nil {
		return nil, fmt.Errorf("image post manifest: %w", err)
	}
	_, local := media.(*objstore.Local)
	for id, e := range m.Cards {
		if e.File == "" {
			continue
		}
		if local {
			if ok, _, err := media.Stat(ctx, e.File); err != nil || !ok {
				continue
			}
		}
		set[id] = Post{URL: media.URL(e.File), Width: e.Width, Height: e.Height, Alt: e.Alt}
	}
	return set, nil
}
