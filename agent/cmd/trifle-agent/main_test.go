package main

import (
	"net"
	"testing"
	"time"
)

func TestLoadConfigRequiresToken(t *testing.T) {
	clearAgentEnv(t)

	_, err := loadConfig()
	if err == nil {
		t.Fatal("expected missing token error")
	}
}

func TestLoadConfigAllowsHealthOnlyModeWithoutToken(t *testing.T) {
	clearAgentEnv(t)
	t.Setenv("TRIFLE_AGENT_CONTROL_PLANE_DISABLED", "true")
	t.Setenv("TRIFLE_AGENT_POLL_INTERVAL", "10")
	t.Setenv("TRIFLE_AGENT_HEARTBEAT_INTERVAL", "45s")
	t.Setenv("TRIFLE_AGENT_ALLOWED_HOSTS", "db.internal,10.0.0.0/8")

	cfg, err := loadConfig()
	if err != nil {
		t.Fatalf("expected config to load: %v", err)
	}
	if !cfg.ControlPlaneDisabled {
		t.Fatal("expected control plane to be disabled")
	}
	if cfg.PollInterval != 10*time.Second {
		t.Fatalf("expected numeric poll interval to be seconds, got %s", cfg.PollInterval)
	}
	if cfg.HeartbeatInterval != 45*time.Second {
		t.Fatalf("expected heartbeat interval from env, got %s", cfg.HeartbeatInterval)
	}
	if len(cfg.AllowedHosts) != 2 {
		t.Fatalf("expected allowed hosts to parse, got %#v", cfg.AllowedHosts)
	}
}

func TestResolveTCPCheckTarget(t *testing.T) {
	host, port, err := resolveTCPCheckTarget(tcpCheckPayload{Address: "db.internal:5432"})
	if err != nil {
		t.Fatalf("expected address target to resolve: %v", err)
	}
	if host != "db.internal" || port != 5432 {
		t.Fatalf("unexpected target %s:%d", host, port)
	}

	_, _, err = resolveTCPCheckTarget(tcpCheckPayload{Host: "db.internal", Port: 70000})
	if err == nil {
		t.Fatal("expected invalid port error")
	}
}

func TestHostAllowed(t *testing.T) {
	rules := []string{
		"db.internal:5432",
		"*.svc.cluster.local",
		"10.0.0.0/8",
		"[2001:db8::1]:6379",
	}

	cases := []struct {
		name string
		host string
		port int
		want bool
	}{
		{name: "exact host and port", host: "db.internal", port: 5432, want: true},
		{name: "exact host wrong port", host: "db.internal", port: 3306, want: false},
		{name: "wildcard suffix", host: "postgres.default.svc.cluster.local", port: 5432, want: true},
		{name: "cidr", host: "10.12.3.4", port: 27017, want: true},
		{name: "ipv6 with port", host: "2001:db8::1", port: 6379, want: true},
		{name: "blocked", host: "metadata.google.internal", port: 80, want: false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := hostAllowed(tc.host, tc.port, rules); got != tc.want {
				t.Fatalf("hostAllowed(%q, %d) = %v, want %v", tc.host, tc.port, got, tc.want)
			}
		})
	}
}

func TestHealthcheckTargetUsesLoopbackForWildcardBind(t *testing.T) {
	got := healthcheckTarget("0.0.0.0:8080")
	want := net.JoinHostPort("127.0.0.1", "8080")
	if got != want {
		t.Fatalf("healthcheckTarget returned %q, want %q", got, want)
	}
}

func TestSplitCSV(t *testing.T) {
	got := splitCSV(" postgres, mysql ,,redis ")
	if len(got) != 3 || got[0] != "postgres" || got[1] != "mysql" || got[2] != "redis" {
		t.Fatalf("unexpected splitCSV result: %#v", got)
	}
}

func clearAgentEnv(t *testing.T) {
	t.Helper()

	keys := []string{
		"TRIFLE_CLOUD_URL",
		"TRIFLE_AGENT_ID",
		"TRIFLE_AGENT_NAME",
		"TRIFLE_AGENT_TOKEN",
		"TRIFLE_AGENT_HEALTH_ADDR",
		"TRIFLE_AGENT_POLL_INTERVAL",
		"TRIFLE_AGENT_HEARTBEAT_INTERVAL",
		"TRIFLE_AGENT_REQUEST_TIMEOUT",
		"TRIFLE_AGENT_CAPABILITIES",
		"TRIFLE_AGENT_ALLOWED_HOSTS",
		"TRIFLE_AGENT_CA_FILE",
		"TRIFLE_AGENT_INSECURE_SKIP_VERIFY",
		"TRIFLE_AGENT_CONTROL_PLANE_DISABLED",
	}

	for _, key := range keys {
		t.Setenv(key, "")
	}
}
