package objstore

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"strings"
)

// UploadResult counts what UploadDir did.
type UploadResult struct {
	Uploaded, Unchanged, Skipped int
}

// UploadDir copies every media file under dir to the store at prefix/<relative path>.
// Files whose ETag already matches their MD5 are left alone; files of other
// types and hidden files are skipped.
func UploadDir(ctx context.Context, st Store, dir, prefix string, log func(string)) (UploadResult, error) {
	var res UploadResult
	prefix = strings.Trim(prefix, "/")
	err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if strings.HasPrefix(d.Name(), ".") && p != dir {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if d.IsDir() {
			return nil
		}
		ct := TypeOf(d.Name())
		if ct == "" {
			res.Skipped++
			return nil
		}
		rel, err := filepath.Rel(dir, p)
		if err != nil {
			return err
		}
		key := path.Join(prefix, filepath.ToSlash(rel))
		uploaded, err := uploadFile(ctx, st, p, key, ct)
		if err != nil {
			return fmt.Errorf("%s: %w", key, err)
		}
		if uploaded {
			res.Uploaded++
			if log != nil {
				log(key)
			}
		} else {
			res.Unchanged++
		}
		return nil
	})
	return res, err
}

func uploadFile(ctx context.Context, st Store, file, key, contentType string) (bool, error) {
	f, err := os.Open(file)
	if err != nil {
		return false, err
	}
	defer f.Close()
	h := md5.New()
	size, err := io.Copy(h, f)
	if err != nil {
		return false, err
	}
	exists, etag, err := st.Stat(ctx, key)
	if err != nil {
		return false, err
	}
	if exists && etag != "" && etag == hex.EncodeToString(h.Sum(nil)) {
		return false, nil
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return false, err
	}
	return true, st.Put(ctx, key, contentType, f, size)
}
