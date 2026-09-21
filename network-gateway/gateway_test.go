package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/types/key"
	"tailscale.com/types/views"
)

const orgA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
const orgB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
const connID = "cccccccc-cccc-cccc-cccc-cccccccccccc"
const sourceID = "dddddddd-dddd-dddd-dddd-dddddddddddd"

type fakeNode struct{ identity string }

func (n *fakeNode) Close() error { return nil }
func (n *fakeNode) Status(context.Context) (nodeStatus, error) {
	return nodeStatus{State: "Running", Enrolled: true, IPs: []string{"100.64.0.1"}}, nil
}
func (n *fakeNode) Dial(ctx context.Context, host string, port int) (net.Conn, error) {
	a, b := net.Pipe()
	go func() { defer b.Close(); _, _ = io.WriteString(b, n.identity+"\n"); _, _ = io.Copy(b, b) }()
	return a, nil
}

func testGateway(t *testing.T) (*gateway, *httptest.Server, *tls.Config) {
	t.Helper()
	g, err := newGateway(t.TempDir(), make([]byte, 32))
	if err != nil {
		t.Fatal(err)
	}
	g.factory = func(_ string, _ []byte, c connectionConfig, _ string) (networkNode, error) {
		return &fakeNode{c.identity()}, nil
	}
	cert, roots := testCertificate(t)
	s := httptest.NewUnstartedServer(g)
	s.TLS = &tls.Config{Certificates: []tls.Certificate{cert}, ClientCAs: roots, ClientAuth: tls.RequireAndVerifyClientCert, MinVersion: tls.VersionTLS13}
	s.StartTLS()
	t.Cleanup(func() { g.Close(); s.Close() })
	return g, s, &tls.Config{Certificates: []tls.Certificate{cert}, RootCAs: roots, ServerName: "localhost", MinVersion: tls.VersionTLS13}
}

func testCertificate(t *testing.T) (tls.Certificate, *x509.CertPool) {
	t.Helper()
	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth}}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &priv.PublicKey, priv)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, _ := x509.MarshalECPrivateKey(priv)
	cert, err := tls.X509KeyPair(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}))
	if err != nil {
		t.Fatal(err)
	}
	parsed, _ := x509.ParseCertificate(der)
	roots := x509.NewCertPool()
	roots.AddCert(parsed)
	return cert, roots
}

func request(t *testing.T, s *httptest.Server, config *tls.Config, method, path string, value any) int {
	t.Helper()
	b, _ := json.Marshal(value)
	req, _ := http.NewRequest(method, s.URL+path, bytes.NewReader(b))
	transport := &http.Transport{TLSClientConfig: config}
	defer transport.CloseIdleConnections()
	response, err := (&http.Client{Transport: transport, Timeout: 5 * time.Second}).Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, response.Body)
	return response.StatusCode
}

func configureTest(t *testing.T, s *httptest.Server, config *tls.Config, org string, generation int64, enabled bool) {
	t.Helper()
	payload := map[string]any{"organization_id": org, "id": connID, "generation": generation, "hostname": "trifle-test", "enabled": enabled, "auth_key": ""}
	if enabled {
		payload["auth_key"] = "tskey-auth-test"
	}
	if code := request(t, s, config, "PUT", "/v1/connections", payload); code != 200 {
		t.Fatalf("configure: %d", code)
	}
}

func testRoute(org string) routeConfig {
	return routeConfig{OrganizationID: org, ConnectionID: connID, Generation: 1, ResourceID: sourceID, Version: 1, Kind: "database", Host: "100.64.0.1", Port: 5432}
}

func openTestStream(t *testing.T, s *httptest.Server, config *tls.Config, route routeConfig) (net.Conn, *bufio.Reader) {
	t.Helper()
	c, err := tls.Dial("tcp", s.Listener.Addr().String(), config)
	if err != nil {
		t.Fatal(err)
	}
	_ = c.SetDeadline(time.Now().Add(5 * time.Second))
	b, _ := json.Marshal(route)
	fmt.Fprintf(c, "POST /v1/streams HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s", len(b), b)
	reader := bufio.NewReader(c)
	response, err := http.ReadResponse(reader, nil)
	if err != nil {
		c.Close()
		t.Fatal(err)
	}
	if response.StatusCode != 101 {
		c.Close()
		t.Fatalf("stream: %d", response.StatusCode)
	}
	t.Cleanup(func() { c.Close() })
	return c, reader
}

func TestTenantStreamsAreIsolatedWithOverlappingAddresses(t *testing.T) {
	_, s, config := testGateway(t)
	for _, org := range []string{orgA, orgB} {
		configureTest(t, s, config, org, 1, true)
		route := testRoute(org)
		if code := request(t, s, config, "PUT", "/v1/routes", route); code != 200 {
			t.Fatal(code)
		}
		client, reader := openTestStream(t, s, config, route)
		line, err := reader.ReadString('\n')
		if err != nil {
			t.Fatal(err)
		}
		if line != org+"/"+connID+"\n" {
			t.Fatal("cross-tailnet stream", line)
		}
		client.Write([]byte("query\n"))
		line, err = reader.ReadString('\n')
		if err != nil || line != "query\n" {
			t.Fatalf("stream did not echo: %q %v", line, err)
		}
		client.Close()
	}
}

func TestRouteChangesAndDisconnectCancelStreams(t *testing.T) {
	_, s, config := testGateway(t)
	configureTest(t, s, config, orgA, 1, true)
	route := testRoute(orgA)
	request(t, s, config, "PUT", "/v1/routes", route)
	client, reader := openTestStream(t, s, config, route)
	reader.ReadString('\n')
	changed := route
	changed.Version = 2
	changed.Host = "100.64.0.2"
	if code := request(t, s, config, "PUT", "/v1/routes", changed); code != 200 {
		t.Fatal(code)
	}
	if _, err := reader.ReadByte(); !errors.Is(err, io.EOF) {
		t.Fatal("old stream survived route change")
	}
	client.Close()
	if code := request(t, s, config, "PUT", "/v1/routes", route); code != 409 {
		t.Fatal("stale route accepted", code)
	}
	client, reader = openTestStream(t, s, config, changed)
	reader.ReadString('\n')
	configureTest(t, s, config, orgA, 2, false)
	if _, err := reader.ReadByte(); !errors.Is(err, io.EOF) {
		t.Fatal("stream survived disconnect")
	}
	client.Close()
	if code := request(t, s, config, "POST", "/v1/streams", changed); code != 409 {
		t.Fatal("disabled tailnet accepted", code)
	}
	if code := request(t, s, config, "PUT", "/v1/connections", map[string]any{"organization_id": orgA, "id": connID, "generation": 1, "hostname": "trifle-test", "enabled": true}); code != 409 {
		t.Fatal("stale configuration resurrected node", code)
	}
}

func TestUnregisteredOrTamperedDestinationsAreRejected(t *testing.T) {
	_, s, config := testGateway(t)
	configureTest(t, s, config, orgA, 1, true)
	route := testRoute(orgA)
	if code := request(t, s, config, "POST", "/v1/streams", route); code != 409 {
		t.Fatal(code)
	}
	request(t, s, config, "PUT", "/v1/routes", route)
	changed := route
	changed.Host = "169.254.169.254"
	if code := request(t, s, config, "POST", "/v1/streams", changed); code != 409 {
		t.Fatal(code)
	}
	changed = route
	changed.OrganizationID = orgB
	if code := request(t, s, config, "POST", "/v1/streams", changed); code != 409 {
		t.Fatal(code)
	}
	if code := request(t, s, config, "PUT", "/v1/connections", map[string]any{"organization_id": "../escape", "id": connID, "generation": 1}); code != 400 {
		t.Fatal(code)
	}
}

func TestHigherEnabledGenerationRequiresFreshAuthKey(t *testing.T) {
	_, s, config := testGateway(t)
	configureTest(t, s, config, orgA, 1, true)
	payload := map[string]any{"organization_id": orgA, "id": connID, "generation": 2, "hostname": "trifle-test", "enabled": true}
	if code := request(t, s, config, "PUT", "/v1/connections", payload); code != 422 {
		t.Fatal("generation rotated without enrollment key", code)
	}
	payload["generation"] = 1
	if code := request(t, s, config, "POST", "/v1/status", payload); code != 200 {
		t.Fatal("rejected rotation changed the existing node", code)
	}
}

func TestStreamAdmissionLimits(t *testing.T) {
	for _, tc := range []struct {
		name       string
		own, other int
		allowed    bool
	}{
		{"below connection limit", 255, 0, true},
		{"connection limit", 256, 0, false},
		{"another organization has the same connection ID", 0, 256, true},
		{"below process limit", 0, 4095, true},
		{"process limit", 0, 4096, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			g, s, config := testGateway(t)
			configureTest(t, s, config, orgA, 1, true)
			route := testRoute(orgA)
			if code := request(t, s, config, "PUT", "/v1/routes", route); code != 200 {
				t.Fatal(code)
			}
			g.mu.Lock()
			for i := 0; i < tc.own+tc.other; i++ {
				occupied := route
				if i >= tc.own {
					occupied.OrganizationID = orgB
				}
				g.streams[&stream{route: occupied, cancel: func() {}}] = struct{}{}
			}
			g.mu.Unlock()
			if tc.allowed {
				client, reader := openTestStream(t, s, config, route)
				if _, err := reader.ReadString('\n'); err != nil {
					t.Fatal(err)
				}
				client.Close()
			} else if code := request(t, s, config, "POST", "/v1/streams", route); code != 503 {
				t.Fatal("stream limit not enforced", code)
			}
		})
	}
}

func TestClientCertificateIsRequired(t *testing.T) {
	_, s, config := testGateway(t)
	config = config.Clone()
	config.Certificates = nil
	transport := &http.Transport{TLSClientConfig: config}
	defer transport.CloseIdleConnections()
	response, err := (&http.Client{Transport: transport, Timeout: time.Second}).Get(s.URL + "/healthz")
	if err == nil {
		response.Body.Close()
		t.Fatal("request without client certificate succeeded")
	}
}

func TestStateIsEncryptedAndIdentityBound(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state")
	store, err := newSealedStore(path, orgA, make([]byte, 32))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.WriteState("secret", []byte("private-machine-key")); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(path)
	if bytes.Contains(b, []byte("private-machine-key")) {
		t.Fatal("plaintext persisted")
	}
	restored, err := newSealedStore(path, orgA, make([]byte, 32))
	if err != nil {
		t.Fatal(err)
	}
	value, _ := restored.ReadState("secret")
	if string(value) != "private-machine-key" {
		t.Fatal("state lost")
	}
	if _, err := newSealedStore(path, orgB, make([]byte, 32)); err == nil {
		t.Fatal("state accepted for wrong tenant")
	}
	b[len(b)-1] ^= 1
	os.WriteFile(path, b, 0600)
	if _, err := newSealedStore(path, orgA, make([]byte, 32)); err == nil {
		t.Fatal("tampered state accepted")
	}
}

func TestTailnetResolutionCannotFallBackToHostNetwork(t *testing.T) {
	routes := views.SliceOf([]netip.Prefix{netip.MustParsePrefix("10.40.0.0/16"), netip.MustParsePrefix("0.0.0.0/0")})
	s := &ipnstate.Status{Peer: map[key.NodePublic]*ipnstate.PeerStatus{
		{}: {DNSName: "db.customer.ts.net.", TailscaleIPs: []netip.Addr{netip.MustParseAddr("100.64.0.5"), netip.MustParseAddr("fd7a:115c:a1e0::5")}, PrimaryRoutes: &routes},
	}}
	for _, host := range []string{"db", "DB.CUSTOMER.TS.NET.", "100.64.0.5", "fd7a:115c:a1e0::5", "10.40.1.7"} {
		if _, err := tailnetTarget(s, host); err != nil {
			t.Errorf("%s: %v", host, err)
		}
	}
	for _, host := range []string{"localhost", "127.0.0.1", "169.254.169.254", "example.com", "10.20.1.7", "100.64.0.99"} {
		if _, err := tailnetTarget(s, host); err == nil {
			t.Errorf("unsafe target accepted: %s", host)
		}
	}
}

func TestCatalogRestoresIdentityWithoutBootstrapKey(t *testing.T) {
	g, s, config := testGateway(t)
	configureTest(t, s, config, orgA, 1, true)
	data, _ := os.ReadFile(filepath.Join(g.dir, "catalog.state"))
	if strings.Contains(string(data), "tskey-auth") {
		t.Fatal("auth key stored")
	}
	restored, err := newGateway(g.dir, g.key)
	if err != nil {
		t.Fatal(err)
	}
	restored.factory = func(_ string, _ []byte, c connectionConfig, auth string) (networkNode, error) {
		if auth != "" {
			t.Fatal("bootstrap key reused")
		}
		return &fakeNode{c.identity()}, nil
	}
	if err := restored.startNodes(); err != nil {
		t.Fatal(err)
	}
	defer restored.Close()
	if len(restored.nodes) != 1 {
		t.Fatal("identity not restored")
	}
}
