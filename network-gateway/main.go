package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		addr := os.Getenv("TRIFLE_GATEWAY_ADDR")
		if addr == "" {
			addr = "127.0.0.1:8443"
		}
		host, port, err := net.SplitHostPort(addr)
		if err != nil {
			log.Fatal(err)
		}
		if host == "" || host == "0.0.0.0" || host == "::" {
			host = "127.0.0.1"
		}
		conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, port), 3*time.Second)
		if err != nil {
			log.Fatal(err)
		}
		conn.Close()
		return
	}
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	// Authentication belongs to individual organizations, never the process.
	for _, name := range []string{"TS_AUTHKEY", "TS_AUTH_KEY", "TS_CLIENT_SECRET", "TS_CLIENT_ID", "TS_ID_TOKEN", "TS_AUDIENCE"} {
		if os.Getenv(name) != "" {
			return fmt.Errorf("%s cannot be used in a multi-tenant gateway", name)
		}
	}
	key, err := base64.StdEncoding.DecodeString(os.Getenv("TRIFLE_GATEWAY_STATE_KEY"))
	if err != nil || len(key) != 32 {
		return errors.New("TRIFLE_GATEWAY_STATE_KEY must be a base64-encoded 32-byte key")
	}
	dir := os.Getenv("TRIFLE_GATEWAY_STATE_DIR")
	if dir == "" {
		dir = "/data"
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	lock, err := os.OpenFile(filepath.Join(dir, "gateway.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return errors.New("gateway state already has an owner")
	}
	ca, err := os.ReadFile(os.Getenv("TRIFLE_GATEWAY_CLIENT_CA"))
	if err != nil {
		return err
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(ca) {
		return errors.New("invalid client CA")
	}
	g, err := newGateway(dir, key)
	if err != nil {
		return err
	}
	if err := g.startNodes(); err != nil {
		return err
	}
	defer g.Close()
	addr := os.Getenv("TRIFLE_GATEWAY_ADDR")
	if addr == "" {
		addr = ":8443"
	}
	server := &http.Server{
		Addr: addr, Handler: g, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, IdleTimeout: 60 * time.Second,
		TLSConfig:    &tls.Config{MinVersion: tls.VersionTLS13, ClientAuth: tls.RequireAndVerifyClientCert, ClientCAs: pool, NextProtos: []string{"http/1.1"}},
		TLSNextProto: map[string]func(*http.Server, *tls.Conn, http.Handler){},
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdown)
	}()
	log.Printf("network gateway listening on %s", addr)
	err = server.ListenAndServeTLS(os.Getenv("TRIFLE_GATEWAY_TLS_CERT"), os.Getenv("TRIFLE_GATEWAY_TLS_KEY"))
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
