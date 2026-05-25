package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

var (
	version   = "dev"
	commit    = "unknown"
	buildDate = "unknown"
)

const (
	defaultCloudURL          = "https://app.trifle.io"
	defaultHealthAddr        = "127.0.0.1:8080"
	defaultPollInterval      = 5 * time.Second
	defaultHeartbeatInterval = 30 * time.Second
	defaultRequestTimeout    = 15 * time.Second
	defaultJobWorkers        = 4
	defaultJobQueueSize      = 64
)

type config struct {
	CloudURL             string
	ConnectorID          string
	ConnectorName        string
	Token                string
	HealthAddr           string
	PollInterval         time.Duration
	HeartbeatInterval    time.Duration
	RequestTimeout       time.Duration
	Capabilities         []string
	AllowedHosts         []string
	CAFile               string
	InsecureSkipVerify   bool
	ControlPlaneDisabled bool
}

type runtimeStatus struct {
	mu                  sync.RWMutex
	StartedAt           time.Time `json:"started_at"`
	LastHeartbeatAt     time.Time `json:"last_heartbeat_at,omitempty"`
	LastPollAt          time.Time `json:"last_poll_at,omitempty"`
	LastSuccessfulJobAt time.Time `json:"last_successful_job_at,omitempty"`
	CloudReachable      bool      `json:"cloud_reachable"`
	LastError           string    `json:"last_error,omitempty"`
}

type runtimeStatusView struct {
	StartedAt           time.Time `json:"started_at"`
	LastHeartbeatAt     time.Time `json:"last_heartbeat_at,omitempty"`
	LastPollAt          time.Time `json:"last_poll_at,omitempty"`
	LastSuccessfulJobAt time.Time `json:"last_successful_job_at,omitempty"`
	CloudReachable      bool      `json:"cloud_reachable"`
	LastError           string    `json:"last_error,omitempty"`
}

type connector struct {
	cfg        config
	httpClient *http.Client
	status     *runtimeStatus
	logger     *log.Logger
	hostname   string
	jobQueue   chan job
	pollSem    chan struct{}
}

type heartbeatRequest struct {
	ConnectorID  string            `json:"connector_id"`
	Name         string            `json:"name,omitempty"`
	Version      string            `json:"version"`
	Commit       string            `json:"commit"`
	BuildDate    string            `json:"build_date"`
	Hostname     string            `json:"hostname"`
	StartedAt    time.Time         `json:"started_at"`
	Capabilities []string          `json:"capabilities"`
	Metadata     map[string]string `json:"metadata,omitempty"`
}

type jobListResponse struct {
	Data struct {
		Jobs []job `json:"jobs"`
	} `json:"data"`
}

type job struct {
	ID      string          `json:"id"`
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

type jobCompletionRequest struct {
	Status string   `json:"status"`
	Result any      `json:"result,omitempty"`
	Error  string   `json:"error,omitempty"`
	Logs   []string `json:"logs,omitempty"`
}

type tcpCheckPayload struct {
	Address        string `json:"address,omitempty"`
	Host           string `json:"host,omitempty"`
	Port           int    `json:"port,omitempty"`
	TimeoutSeconds int    `json:"timeout_seconds,omitempty"`
}

type tcpCheckResult struct {
	Address   string `json:"address"`
	Host      string `json:"host"`
	Port      int    `json:"port"`
	Reachable bool   `json:"reachable"`
	LatencyMS int64  `json:"latency_ms,omitempty"`
	Error     string `json:"error,omitempty"`
	CheckedAt string `json:"checked_at"`
}

func main() {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "version":
			fmt.Printf("trifle-connector %s commit=%s built=%s\n", version, commit, buildDate)
			return
		case "healthcheck":
			if err := runHealthcheck(); err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			return
		}
	}

	logger := log.New(os.Stdout, "", log.LstdFlags|log.LUTC)
	cfg, err := loadConfig()
	if err != nil {
		logger.Printf("level=error msg=%q error=%q", "invalid configuration", err)
		os.Exit(2)
	}

	client, err := newHTTPClient(cfg)
	if err != nil {
		logger.Printf("level=error msg=%q error=%q", "failed to configure HTTP client", err)
		os.Exit(2)
	}

	hostname, _ := os.Hostname()
	if cfg.ConnectorID == "" {
		cfg.ConnectorID = hostname
	}

	status := &runtimeStatus{StartedAt: time.Now().UTC()}
	a := &connector{
		cfg:        cfg,
		httpClient: client,
		status:     status,
		logger:     logger,
		hostname:   hostname,
		jobQueue:   make(chan job, defaultJobQueueSize),
		pollSem:    make(chan struct{}, 1),
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	healthServer, err := startHealthServer(ctx, cfg.HealthAddr, status, logger)
	if err != nil {
		logger.Printf("level=error msg=%q error=%q", "failed to bind health server", err)
		os.Exit(2)
	}

	if cfg.ControlPlaneDisabled {
		logger.Printf("level=info msg=%q health_addr=%q", "control plane disabled; serving health only", cfg.HealthAddr)
		<-ctx.Done()
	} else {
		logger.Printf(
			"level=info msg=%q connector_id=%q cloud_url=%q health_addr=%q capabilities=%q",
			"starting trifle connector",
			cfg.ConnectorID,
			cfg.CloudURL,
			cfg.HealthAddr,
			strings.Join(cfg.Capabilities, ","),
		)
		a.run(ctx)
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = healthServer.Shutdown(shutdownCtx)
}

func (a *connector) run(ctx context.Context) {
	heartbeatTicker := time.NewTicker(a.cfg.HeartbeatInterval)
	pollTicker := time.NewTicker(a.cfg.PollInterval)
	defer heartbeatTicker.Stop()
	defer pollTicker.Stop()

	for workerID := 0; workerID < defaultJobWorkers; workerID++ {
		go a.runJobWorker(ctx, workerID)
	}

	a.sendHeartbeat(ctx)
	a.dispatchPoll(ctx)

	for {
		select {
		case <-ctx.Done():
			a.logger.Printf("level=info msg=%q", "connector shutting down")
			return
		case <-heartbeatTicker.C:
			a.sendHeartbeat(ctx)
		case <-pollTicker.C:
			a.dispatchPoll(ctx)
		}
	}
}

func (a *connector) dispatchPoll(ctx context.Context) {
	select {
	case a.pollSem <- struct{}{}:
		go func() {
			defer func() { <-a.pollSem }()
			a.pollJobs(ctx)
		}()
	default:
		a.logger.Printf("level=debug msg=%q", "previous job poll still running")
	}
}

func (a *connector) sendHeartbeat(ctx context.Context) {
	payload := heartbeatRequest{
		ConnectorID:  a.cfg.ConnectorID,
		Name:         a.cfg.ConnectorName,
		Version:      version,
		Commit:       commit,
		BuildDate:    buildDate,
		Hostname:     a.hostname,
		StartedAt:    a.status.StartedAt,
		Capabilities: a.cfg.Capabilities,
		Metadata: map[string]string{
			"runtime":                  "docker",
			"allowed_hosts_configured": strconv.FormatBool(len(a.cfg.AllowedHosts) > 0),
		},
	}

	err := a.postJSON(ctx, "/api/v1/connectors/heartbeat", payload, nil)
	if err != nil {
		if isNotFound(err) {
			a.markControlPlanePending()
			a.logger.Printf("level=warn msg=%q error=%q", "cloud heartbeat endpoint is not available yet", err)
		} else {
			a.markError(err)
			a.logger.Printf("level=warn msg=%q error=%q", "heartbeat failed", err)
		}
		return
	}

	a.status.mu.Lock()
	a.status.LastHeartbeatAt = time.Now().UTC()
	a.status.CloudReachable = true
	a.status.LastError = ""
	a.status.mu.Unlock()
}

func (a *connector) pollJobs(ctx context.Context) {
	endpoint := fmt.Sprintf("/api/v1/connectors/jobs?connector_id=%s", url.QueryEscape(a.cfg.ConnectorID))
	var response jobListResponse

	err := a.getJSON(ctx, endpoint, &response)
	if err != nil {
		if isNotFound(err) {
			a.markControlPlanePending()
			a.logger.Printf("level=debug msg=%q error=%q", "cloud jobs endpoint is not available yet", err)
		} else {
			a.markError(err)
			a.logger.Printf("level=warn msg=%q error=%q", "job poll failed", err)
		}
		return
	}

	a.status.mu.Lock()
	a.status.LastPollAt = time.Now().UTC()
	a.status.CloudReachable = true
	a.status.LastError = ""
	a.status.mu.Unlock()

	for _, j := range response.Data.Jobs {
		a.enqueueJob(ctx, j)
	}
}

func (a *connector) enqueueJob(ctx context.Context, j job) {
	select {
	case a.jobQueue <- j:
	case <-ctx.Done():
	default:
		a.logger.Printf("level=warn msg=%q job_id=%q type=%q", "job queue is full", j.ID, j.Type)
		if j.ID != "" {
			a.completeJob(ctx, j.ID, jobCompletionRequest{
				Status: "error",
				Error:  "connector job queue is full",
			})
		}
	}
}

func (a *connector) runJobWorker(ctx context.Context, workerID int) {
	for {
		select {
		case <-ctx.Done():
			return
		case j := <-a.jobQueue:
			a.logger.Printf("level=debug msg=%q worker=%d job_id=%q type=%q", "handling job", workerID, j.ID, j.Type)
			a.handleJob(ctx, j)
		}
	}
}

func (a *connector) handleJob(ctx context.Context, j job) {
	if j.ID == "" {
		a.logger.Printf("level=warn msg=%q type=%q", "received job without id", j.Type)
		return
	}

	switch j.Type {
	case "ping":
		a.completeJob(ctx, j.ID, jobCompletionRequest{
			Status: "ok",
			Result: map[string]any{
				"pong":         true,
				"connector_id": a.cfg.ConnectorID,
				"handled_at":   time.Now().UTC(),
			},
		})
	case "tcp_check", "database_tcp_check":
		a.handleTCPCheck(ctx, j)
	default:
		a.completeJob(ctx, j.ID, jobCompletionRequest{
			Status: "error",
			Error:  fmt.Sprintf("unsupported job type %q", j.Type),
		})
	}
}

func (a *connector) handleTCPCheck(ctx context.Context, j job) {
	var payload tcpCheckPayload
	if err := json.Unmarshal(j.Payload, &payload); err != nil {
		a.completeJob(ctx, j.ID, jobCompletionRequest{Status: "error", Error: "invalid tcp_check payload"})
		return
	}

	host, port, err := resolveTCPCheckTarget(payload)
	if err != nil {
		a.completeJob(ctx, j.ID, jobCompletionRequest{Status: "error", Error: err.Error()})
		return
	}
	if !hostAllowed(host, port, a.cfg.AllowedHosts) {
		a.completeJob(ctx, j.ID, jobCompletionRequest{
			Status: "error",
			Error:  fmt.Sprintf("target %s is not allowed by TRIFLE_CONNECTOR_ALLOWED_HOSTS", net.JoinHostPort(host, strconv.Itoa(port))),
		})
		return
	}

	timeout := 5 * time.Second
	if payload.TimeoutSeconds > 0 {
		timeout = time.Duration(payload.TimeoutSeconds) * time.Second
	}
	if timeout > 30*time.Second {
		timeout = 30 * time.Second
	}

	checkCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	address := net.JoinHostPort(host, strconv.Itoa(port))
	start := time.Now()
	conn, err := (&net.Dialer{Timeout: timeout}).DialContext(checkCtx, "tcp", address)
	latency := time.Since(start).Milliseconds()
	result := tcpCheckResult{
		Address:   address,
		Host:      host,
		Port:      port,
		Reachable: err == nil,
		LatencyMS: latency,
		CheckedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}
	if err != nil {
		result.Error = err.Error()
	} else {
		_ = conn.Close()
	}

	a.completeJob(ctx, j.ID, jobCompletionRequest{Status: "ok", Result: result})
}

func (a *connector) completeJob(ctx context.Context, id string, payload jobCompletionRequest) {
	path := fmt.Sprintf("/api/v1/connectors/jobs/%s/complete", url.PathEscape(id))
	if err := a.postJSON(ctx, path, payload, nil); err != nil {
		a.markError(err)
		a.logger.Printf("level=warn msg=%q job_id=%q error=%q", "job completion failed", id, err)
		return
	}

	a.status.mu.Lock()
	a.status.LastSuccessfulJobAt = time.Now().UTC()
	a.status.CloudReachable = true
	a.status.LastError = ""
	a.status.mu.Unlock()
}

func (a *connector) getJSON(ctx context.Context, path string, out any) error {
	req, err := a.newRequest(ctx, http.MethodGet, path, nil)
	if err != nil {
		return err
	}

	return a.doJSON(req, out)
}

func (a *connector) postJSON(ctx context.Context, path string, in any, out any) error {
	var body bytes.Buffer
	if err := json.NewEncoder(&body).Encode(in); err != nil {
		return err
	}

	req, err := a.newRequest(ctx, http.MethodPost, path, &body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	return a.doJSON(req, out)
}

func (a *connector) newRequest(ctx context.Context, method string, path string, body io.Reader) (*http.Request, error) {
	base, err := url.Parse(a.cfg.CloudURL)
	if err != nil {
		return nil, err
	}
	ref, err := url.Parse(path)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, method, base.ResolveReference(ref).String(), body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+a.cfg.Token)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "trifle-connector/"+version)
	return req, nil
}

func (a *connector) doJSON(req *http.Request, out any) error {
	resp, err := a.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNoContent {
		return nil
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return err
	}

	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return httpStatusError{StatusCode: resp.StatusCode, Body: strings.TrimSpace(string(body))}
	}

	if out == nil || len(bytes.TrimSpace(body)) == 0 {
		return nil
	}
	return json.Unmarshal(body, out)
}

func (a *connector) markError(err error) {
	a.status.mu.Lock()
	defer a.status.mu.Unlock()
	a.status.CloudReachable = false
	a.status.LastError = err.Error()
}

func (a *connector) markControlPlanePending() {
	a.status.mu.Lock()
	defer a.status.mu.Unlock()
	a.status.CloudReachable = false
	a.status.LastError = ""
}

func (status *runtimeStatus) Snapshot() runtimeStatusView {
	status.mu.RLock()
	defer status.mu.RUnlock()

	return runtimeStatusView{
		StartedAt:           status.StartedAt,
		LastHeartbeatAt:     status.LastHeartbeatAt,
		LastPollAt:          status.LastPollAt,
		LastSuccessfulJobAt: status.LastSuccessfulJobAt,
		CloudReachable:      status.CloudReachable,
		LastError:           status.LastError,
	}
}

func startHealthServer(ctx context.Context, addr string, status *runtimeStatus, logger *log.Logger) (*http.Server, error) {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		snapshot := status.Snapshot()

		w.Header().Set("Content-Type", "application/json")
		if !snapshot.CloudReachable && snapshot.LastError != "" {
			w.WriteHeader(http.StatusServiceUnavailable)
		}
		_ = json.NewEncoder(w).Encode(snapshot)
	})

	server := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	listener, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, err
	}

	go func() {
		if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Printf("level=error msg=%q error=%q", "health server failed", err)
		}
	}()

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()

	return server, nil
}

func loadConfig() (config, error) {
	cfg := config{
		CloudURL:           getEnv("TRIFLE_CLOUD_URL", defaultCloudURL),
		ConnectorID:        getEnv("TRIFLE_CONNECTOR_ID", ""),
		ConnectorName:      getEnv("TRIFLE_CONNECTOR_NAME", ""),
		Token:              getEnv("TRIFLE_CONNECTOR_TOKEN", ""),
		HealthAddr:         getEnv("TRIFLE_CONNECTOR_HEALTH_ADDR", defaultHealthAddr),
		Capabilities:       splitCSV(getEnv("TRIFLE_CONNECTOR_CAPABILITIES", "postgres,mysql,mongo,redis")),
		AllowedHosts:       splitCSV(getEnv("TRIFLE_CONNECTOR_ALLOWED_HOSTS", "")),
		CAFile:             getEnv("TRIFLE_CONNECTOR_CA_FILE", ""),
		InsecureSkipVerify: truthy(getEnv("TRIFLE_CONNECTOR_INSECURE_SKIP_VERIFY", "")),
	}

	if truthy(getEnv("TRIFLE_CONNECTOR_CONTROL_PLANE_DISABLED", "")) {
		cfg.ControlPlaneDisabled = true
	}

	var err error
	if cfg.PollInterval, err = getDurationEnv("TRIFLE_CONNECTOR_POLL_INTERVAL", defaultPollInterval); err != nil {
		return cfg, err
	}
	if cfg.HeartbeatInterval, err = getDurationEnv("TRIFLE_CONNECTOR_HEARTBEAT_INTERVAL", defaultHeartbeatInterval); err != nil {
		return cfg, err
	}
	if cfg.RequestTimeout, err = getDurationEnv("TRIFLE_CONNECTOR_REQUEST_TIMEOUT", defaultRequestTimeout); err != nil {
		return cfg, err
	}

	if cfg.Token == "" && !cfg.ControlPlaneDisabled {
		return cfg, errors.New("TRIFLE_CONNECTOR_TOKEN is required")
	}
	if !cfg.ControlPlaneDisabled {
		if err := validateCloudURL(cfg.CloudURL); err != nil {
			return cfg, fmt.Errorf("TRIFLE_CLOUD_URL is invalid: %w", err)
		}
	}
	if cfg.PollInterval < time.Second {
		return cfg, errors.New("TRIFLE_CONNECTOR_POLL_INTERVAL must be at least 1s")
	}
	if cfg.HeartbeatInterval < time.Second {
		return cfg, errors.New("TRIFLE_CONNECTOR_HEARTBEAT_INTERVAL must be at least 1s")
	}
	if cfg.HealthAddr == "" {
		return cfg, errors.New("TRIFLE_CONNECTOR_HEALTH_ADDR cannot be empty")
	}

	return cfg, nil
}

func newHTTPClient(cfg config) (*http.Client, error) {
	tlsConfig := &tls.Config{
		MinVersion:         tls.VersionTLS12,
		InsecureSkipVerify: cfg.InsecureSkipVerify,
	}

	if cfg.CAFile != "" {
		certs, err := os.ReadFile(cfg.CAFile)
		if err != nil {
			return nil, err
		}
		pool, err := x509.SystemCertPool()
		if err != nil {
			pool = x509.NewCertPool()
		}
		if !pool.AppendCertsFromPEM(certs) {
			return nil, fmt.Errorf("no certificates found in %s", cfg.CAFile)
		}
		tlsConfig.RootCAs = pool
	}

	transport := &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: (&net.Dialer{
			Timeout:   10 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          10,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		TLSClientConfig:       tlsConfig,
	}

	return &http.Client{Timeout: cfg.RequestTimeout, Transport: transport}, nil
}

func runHealthcheck() error {
	fs := flag.NewFlagSet("healthcheck", flag.ContinueOnError)
	addr := fs.String("addr", getEnv("TRIFLE_CONNECTOR_HEALTH_ADDR", defaultHealthAddr), "health endpoint address")
	if err := fs.Parse(os.Args[2:]); err != nil {
		return err
	}

	client := http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get("http://" + healthcheckTarget(*addr) + "/healthz")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("healthcheck returned %s", resp.Status)
	}
	return nil
}

func validateCloudURL(value string) error {
	parsed, err := url.Parse(value)
	if err != nil {
		return err
	}
	if parsed.Scheme == "" || parsed.Host == "" {
		return errors.New("must include scheme and host")
	}
	if parsed.Scheme != "https" && parsed.Scheme != "http" {
		return errors.New("scheme must be http or https")
	}
	return nil
}

func resolveTCPCheckTarget(payload tcpCheckPayload) (string, int, error) {
	host := strings.TrimSpace(payload.Host)
	port := payload.Port

	if payload.Address != "" {
		addressHost, addressPort, err := net.SplitHostPort(strings.TrimSpace(payload.Address))
		if err != nil {
			return "", 0, fmt.Errorf("address must be host:port")
		}
		parsedPort, err := strconv.Atoi(addressPort)
		if err != nil {
			return "", 0, fmt.Errorf("address port must be numeric")
		}
		host = addressHost
		port = parsedPort
	}

	host = normalizeHost(host)
	if host == "" {
		return "", 0, errors.New("host is required")
	}
	if port < 1 || port > 65535 {
		return "", 0, errors.New("port must be between 1 and 65535")
	}

	return host, port, nil
}

func hostAllowed(host string, port int, rules []string) bool {
	if len(rules) == 0 {
		return false
	}

	targetHost := normalizeHost(host)
	targetIP := net.ParseIP(targetHost)

	for _, rule := range rules {
		ruleHost, rulePort := parseAllowedHostRule(rule)
		if ruleHost == "" {
			continue
		}
		if rulePort != 0 && rulePort != port {
			continue
		}

		if ruleHost == "*" {
			return true
		}
		if strings.HasPrefix(ruleHost, "*.") {
			suffix := strings.TrimPrefix(ruleHost, "*")
			if strings.HasSuffix(targetHost, suffix) && targetHost != strings.TrimPrefix(suffix, ".") {
				return true
			}
			continue
		}
		if _, network, err := net.ParseCIDR(ruleHost); err == nil {
			if targetIP != nil && network.Contains(targetIP) {
				return true
			}
			continue
		}
		if normalizeHost(ruleHost) == targetHost {
			return true
		}
	}

	return false
}

func parseAllowedHostRule(rule string) (string, int) {
	rule = strings.TrimSpace(strings.ToLower(rule))
	if rule == "" {
		return "", 0
	}

	host, portText, err := net.SplitHostPort(rule)
	if err == nil {
		port, err := strconv.Atoi(portText)
		if err != nil || port < 1 || port > 65535 {
			return "", 0
		}
		return normalizeHost(host), port
	}

	if strings.Count(rule, ":") == 1 {
		parts := strings.Split(rule, ":")
		port, err := strconv.Atoi(parts[1])
		if err == nil && port >= 1 && port <= 65535 {
			return normalizeHost(parts[0]), port
		}
	}

	return normalizeHost(rule), 0
}

func normalizeHost(host string) string {
	host = strings.TrimSpace(strings.ToLower(host))
	host = strings.Trim(host, "[]")
	host = strings.TrimSuffix(host, ".")
	return host
}

func healthcheckTarget(addr string) string {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	return net.JoinHostPort(host, port)
}

type httpStatusError struct {
	StatusCode int
	Body       string
}

func (e httpStatusError) Error() string {
	if e.Body == "" {
		return fmt.Sprintf("cloud returned HTTP %d", e.StatusCode)
	}
	return fmt.Sprintf("cloud returned HTTP %d: %s", e.StatusCode, e.Body)
}

func isNotFound(err error) bool {
	var statusErr httpStatusError
	return errors.As(err, &statusErr) && statusErr.StatusCode == http.StatusNotFound
}

func getEnv(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func getDurationEnv(key string, fallback time.Duration) (time.Duration, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}
	if onlyDigits(value) {
		value += "s"
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return 0, fmt.Errorf("%s has invalid duration %q: %w", key, value, err)
	}
	return parsed, nil
}

func onlyDigits(value string) bool {
	if value == "" {
		return false
	}
	for _, r := range value {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}

func truthy(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "true", "yes", "on", "enabled":
		return true
	default:
		return false
	}
}
