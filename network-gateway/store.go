package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"

	"tailscale.com/ipn"
)

// sealedStore persists node keys without ever writing plaintext state to disk.
// The connection identity is authenticated as additional data, so files cannot
// be transplanted between tenants. Atomic replacement is fsynced before return.
type sealedStore struct {
	mu     sync.Mutex
	path   string
	aad    []byte
	aead   cipher.AEAD
	values map[ipn.StateKey][]byte
}

func newSealedStore(path, identity string, key []byte) (*sealedStore, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	s := &sealedStore{path: path, aad: []byte(identity), aead: aead, values: map[ipn.StateKey][]byte{}}
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return nil, err
	}
	if len(b) < aead.NonceSize() {
		return nil, errors.New("invalid encrypted state")
	}
	plain, err := aead.Open(nil, b[:aead.NonceSize()], b[aead.NonceSize():], s.aad)
	if err != nil {
		return nil, errors.New("cannot decrypt gateway state")
	}
	if err := json.Unmarshal(plain, &s.values); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *sealedStore) ReadState(k ipn.StateKey) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	b, ok := s.values[k]
	if !ok {
		return nil, ipn.ErrStateNotExist
	}
	return append([]byte(nil), b...), nil
}

func (s *sealedStore) WriteState(k ipn.StateKey, value []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	next := make(map[ipn.StateKey][]byte, len(s.values)+1)
	for key, val := range s.values {
		next[key] = val
	}
	if value == nil {
		delete(next, k)
	} else {
		next[k] = append([]byte(nil), value...)
	}
	plain, err := json.Marshal(next)
	if err != nil {
		return err
	}
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return err
	}
	sealed := s.aead.Seal(nonce, nonce, plain, s.aad)
	if err := atomicWrite(s.path, sealed); err != nil {
		return err
	}
	s.values = next
	return nil
}

func atomicWrite(path string, contents []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".state-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	defer f.Close()
	if err := f.Chmod(0600); err != nil {
		return err
	}
	if _, err := f.Write(contents); err != nil {
		return err
	}
	if err := f.Sync(); err != nil {
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	if err := os.Rename(f.Name(), path); err != nil {
		return err
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}
