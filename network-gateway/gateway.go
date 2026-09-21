package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

var uuidPattern = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

type connectionConfig struct {
	OrganizationID string `json:"organization_id"`
	ID             string `json:"id"`
	Generation     int64  `json:"generation"`
	Hostname       string `json:"hostname"`
	Enabled        bool   `json:"enabled"`
}

func (c connectionConfig) identity() string { return c.OrganizationID + "/" + c.ID }

type routeConfig struct {
	OrganizationID string `json:"organization_id"`
	ConnectionID   string `json:"connection_id"`
	Generation     int64  `json:"generation"`
	ResourceID     string `json:"resource_id"`
	Version        int64  `json:"version"`
	Kind           string `json:"kind"`
	Host           string `json:"host"`
	Port           int    `json:"port"`
}

func (r routeConfig) identity() string   { return r.OrganizationID + "/" + r.ResourceID + "/" + r.Kind }
func (r routeConfig) connection() string { return r.OrganizationID + "/" + r.ConnectionID }

type stream struct {
	route  routeConfig
	cancel context.CancelFunc
}
type gateway struct {
	mu      sync.Mutex
	dir     string
	key     []byte
	store   *sealedStore
	configs map[string]connectionConfig
	nodes   map[string]networkNode
	routes  map[string]routeConfig
	streams map[*stream]struct{}
	factory func(string, []byte, connectionConfig, string) (networkNode, error)
}

func newGateway(dir string, key []byte) (*gateway, error) {
	store, err := newSealedStore(filepath.Join(dir, "catalog.state"), "trifle-network-gateway/catalog/v1", key)
	if err != nil {
		return nil, err
	}
	g := &gateway{dir: dir, key: key, store: store, configs: map[string]connectionConfig{}, nodes: map[string]networkNode{}, routes: map[string]routeConfig{}, streams: map[*stream]struct{}{}, factory: newTailscaleNode}
	b, err := store.ReadState("connections")
	if err == nil {
		if err := json.Unmarshal(b, &g.configs); err != nil {
			return nil, err
		}
	}
	return g, nil
}

func (g *gateway) startNodes() error {
	for id, c := range g.configs {
		if !c.Enabled {
			continue
		}
		n, err := g.factory(filepath.Join(g.dir, id), g.key, c, "")
		if err != nil {
			g.Close()
			return fmt.Errorf("restore connection %s: %w", c.ID, err)
		}
		g.nodes[id] = n
	}
	return nil
}

func (g *gateway) persist() error {
	b, err := json.Marshal(g.configs)
	if err != nil {
		return err
	}
	return g.store.WriteState("connections", b)
}

func (g *gateway) Close() {
	g.mu.Lock()
	defer g.mu.Unlock()
	for s := range g.streams {
		s.cancel()
	}
	for _, n := range g.nodes {
		_ = n.Close()
	}
}

func (g *gateway) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/healthz" {
		respond(w, 200, map[string]string{"status": "ok"})
		return
	}
	// Defense in depth: TLS listener already requires a client certificate.
	if r.TLS == nil || len(r.TLS.VerifiedChains) == 0 {
		http.Error(w, "client certificate required", 401)
		return
	}
	switch {
	case r.Method == "PUT" && r.URL.Path == "/v1/connections":
		g.configure(w, r)
	case r.Method == "POST" && r.URL.Path == "/v1/status":
		g.status(w, r)
	case r.Method == "PUT" && r.URL.Path == "/v1/routes":
		g.route(w, r)
	case r.Method == "POST" && r.URL.Path == "/v1/streams":
		g.openStream(w, r)
	default:
		http.NotFound(w, r)
	}
}

func decode(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 16*1024)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(target); err != nil {
		http.Error(w, "invalid request", 400)
		return false
	}
	if err := d.Decode(&struct{}{}); err != io.EOF {
		http.Error(w, "invalid request", 400)
		return false
	}
	return true
}
func respond(w http.ResponseWriter, code int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(value)
}

func (g *gateway) configure(w http.ResponseWriter, r *http.Request) {
	var request struct {
		connectionConfig
		AuthKey string `json:"auth_key"`
	}
	if !decode(w, r, &request) {
		return
	}
	c := request.connectionConfig
	if !uuidPattern.MatchString(c.ID) || !uuidPattern.MatchString(c.OrganizationID) || c.Generation < 1 || (c.Enabled && !strings.HasPrefix(c.Hostname, "trifle-")) {
		http.Error(w, "invalid connection", 400)
		return
	}
	if request.AuthKey != "" && !strings.HasPrefix(request.AuthKey, "tskey-auth-") {
		http.Error(w, "a Tailscale auth key is required", 400)
		return
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	id := c.identity()
	old, exists := g.configs[id]
	if exists && (c.Generation < old.Generation || (c.Generation == old.Generation && c != old)) {
		http.Error(w, "stale connection configuration", 409)
		return
	}
	if exists && c == old && g.nodes[id] != nil {
		respond(w, 200, map[string]bool{"accepted": true})
		return
	}
	if c.Enabled && (!exists || !old.Enabled || request.AuthKey != "") && request.AuthKey == "" {
		http.Error(w, "fresh enrollment key required", 422)
		return
	}
	if exists && c.Generation > old.Generation {
		for s := range g.streams {
			if s.route.connection() == id {
				s.cancel()
			}
		}
		if node := g.nodes[id]; node != nil {
			_ = node.Close()
			delete(g.nodes, id)
		}
		// Persist disabled first: a crash must not resurrect an old identity.
		tombstone := c
		tombstone.Enabled = false
		g.configs[id] = tombstone
		if err := g.persist(); err != nil {
			http.Error(w, "state persistence failed", 500)
			return
		}
		if err := os.RemoveAll(filepath.Join(g.dir, id)); err != nil {
			http.Error(w, "state cleanup failed", 500)
			return
		}
	}
	if c.Enabled {
		n, err := g.factory(filepath.Join(g.dir, id), g.key, c, request.AuthKey)
		if err != nil {
			http.Error(w, "node enrollment failed", 502)
			return
		}
		g.nodes[id] = n
	}
	g.configs[id] = c
	if err := g.persist(); err != nil {
		if n := g.nodes[id]; n != nil {
			_ = n.Close()
			delete(g.nodes, id)
		}
		http.Error(w, "state persistence failed", 500)
		return
	}
	respond(w, 200, map[string]bool{"accepted": true})
}

func (g *gateway) status(w http.ResponseWriter, r *http.Request) {
	var c connectionConfig
	if !decode(w, r, &c) {
		return
	}
	g.mu.Lock()
	n := g.nodes[c.identity()]
	current, ok := g.configs[c.identity()]
	count := 0
	for s := range g.streams {
		if s.route.connection() == c.identity() {
			count++
		}
	}
	g.mu.Unlock()
	if !ok || current.Generation != c.Generation {
		http.Error(w, "connection not found", 404)
		return
	}
	if n == nil {
		respond(w, 200, nodeStatus{State: "Stopped", IPs: []string{}})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	s, err := n.Status(ctx)
	if err != nil {
		http.Error(w, "node status unavailable", 502)
		return
	}
	s.ActiveStreams = count
	respond(w, 200, s)
}

func validRoute(v routeConfig) bool {
	return uuidPattern.MatchString(v.OrganizationID) && uuidPattern.MatchString(v.ConnectionID) && uuidPattern.MatchString(v.ResourceID) && v.Generation > 0 && v.Version > 0 && (v.Kind == "database" || v.Kind == "s3") && v.Port > 0 && v.Port <= 65535 && len(v.Host) > 0 && len(v.Host) < 254 && !strings.ContainsAny(v.Host, " /\\\r\n\t@?#")
}

func (g *gateway) route(w http.ResponseWriter, r *http.Request) {
	var v routeConfig
	if !decode(w, r, &v) {
		return
	}
	if !validRoute(v) {
		http.Error(w, "invalid route", 400)
		return
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	c, ok := g.configs[v.connection()]
	if !ok || !c.Enabled || c.Generation != v.Generation {
		http.Error(w, "connection unavailable", 409)
		return
	}
	old, exists := g.routes[v.identity()]
	newIdentity := old.ConnectionID == v.ConnectionID && old.Generation < v.Generation
	if exists && (old.Version > v.Version || (old.Version == v.Version && old != v && !newIdentity)) {
		http.Error(w, "stale resource configuration", 409)
		return
	}
	if exists && old != v {
		for s := range g.streams {
			if s.route.identity() == v.identity() {
				s.cancel()
			}
		}
	}
	g.routes[v.identity()] = v
	respond(w, 200, map[string]bool{"accepted": true})
}

func (g *gateway) openStream(w http.ResponseWriter, r *http.Request) {
	var v routeConfig
	if !decode(w, r, &v) {
		return
	}
	if !validRoute(v) {
		http.Error(w, "invalid route", 400)
		return
	}
	g.mu.Lock()
	c, ok := g.configs[v.connection()]
	n := g.nodes[v.connection()]
	if !ok || !c.Enabled || c.Generation != v.Generation || n == nil || g.routes[v.identity()] != v {
		g.mu.Unlock()
		http.Error(w, "route unavailable", 409)
		return
	}
	if len(g.streams) >= 4096 {
		g.mu.Unlock()
		http.Error(w, "gateway stream limit reached", 503)
		return
	}
	ctx, cancel := context.WithCancel(r.Context())
	s := &stream{v, cancel}
	g.streams[s] = struct{}{}
	g.mu.Unlock()
	defer func() { cancel(); g.mu.Lock(); delete(g.streams, s); g.mu.Unlock() }()
	started := time.Now()
	dialCtx, dialCancel := context.WithTimeout(ctx, 10*time.Second)
	remote, err := n.Dial(dialCtx, v.Host, v.Port)
	dialCancel()
	if err != nil {
		log.Printf("event=dial_failed connection=%s resource=%s elapsed_ms=%d", v.ConnectionID, v.ResourceID, time.Since(started).Milliseconds())
		http.Error(w, "tailnet destination unavailable; check node, route and grants", 502)
		return
	}
	defer remote.Close()
	hijacker, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "streaming unsupported", 500)
		return
	}
	client, buffer, err := hijacker.Hijack()
	if err != nil {
		return
	}
	defer client.Close()
	_ = client.SetDeadline(time.Time{})
	if _, err := buffer.WriteString("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: trifle-stream\r\n\r\n"); err != nil {
		return
	}
	if err := buffer.Flush(); err != nil {
		return
	}
	log.Printf("event=stream_open connection=%s resource=%s elapsed_ms=%d", v.ConnectionID, v.ResourceID, time.Since(started).Milliseconds())
	done := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			client.Close()
			remote.Close()
		case <-done:
		}
	}()
	defer close(done)
	copyDone := make(chan error, 2)
	go func() { _, e := io.Copy(remote, buffer); closeWrite(remote); copyDone <- e }()
	go func() { _, e := io.Copy(client, remote); closeWrite(client); copyDone <- e }()
	if err := <-copyDone; err != nil && !errors.Is(err, net.ErrClosed) {
		cancel()
	}
	// Allow a peer to finish sending after the other direction reaches EOF.
	select {
	case <-copyDone:
	case <-ctx.Done():
	case <-time.After(30 * time.Second):
	}
}

func closeWrite(c net.Conn) {
	if half, ok := c.(interface{ CloseWrite() error }); ok {
		_ = half.CloseWrite()
	}
}
