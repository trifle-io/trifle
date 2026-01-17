package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/trifle-io/trifle/cli/internal/api"
	"github.com/trifle-io/trifle/cli/internal/output"
)

var version = "0.1.0-dev"

var granularityPattern = regexp.MustCompile(`^\d+(s|m|h|d|w|mo|q|y)$`)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "metrics":
		runMetrics(os.Args[2:])
	case "transponders":
		runTransponders(os.Args[2:])
	case "mcp":
		runMCP(os.Args[2:])
	case "version":
		fmt.Println(version)
	case "help", "-h", "--help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		usage()
		os.Exit(1)
	}
}

type commonOptions struct {
	BaseURL string
	Token   string
	Timeout time.Duration
}

func addCommonFlags(fs *flag.FlagSet) *commonOptions {
	opts := &commonOptions{
		BaseURL: os.Getenv("TRIFLE_URL"),
		Token:   os.Getenv("TRIFLE_TOKEN"),
		Timeout: 30 * time.Second,
	}

	fs.StringVar(&opts.BaseURL, "url", opts.BaseURL, "Trifle base URL (or TRIFLE_URL)")
	fs.StringVar(&opts.Token, "token", opts.Token, "API token (or TRIFLE_TOKEN)")
	fs.DurationVar(&opts.Timeout, "timeout", opts.Timeout, "HTTP timeout")
	return opts
}

func ensureToken(opts *commonOptions, allowPrompt bool) error {
	if opts.Token != "" {
		return nil
	}
	if !allowPrompt {
		return fmt.Errorf("missing token: set --token or TRIFLE_TOKEN")
	}

	fmt.Fprint(os.Stderr, "Trifle token: ")
	reader := bufio.NewReader(os.Stdin)
	token, err := reader.ReadString('\n')
	if err != nil {
		return fmt.Errorf("read token: %w", err)
	}
	opts.Token = strings.TrimSpace(token)
	if opts.Token == "" {
		return fmt.Errorf("token is required")
	}
	return nil
}

func newClient(opts *commonOptions) (*api.Client, error) {
	return api.New(opts.BaseURL, opts.Token, opts.Timeout)
}

func runMetrics(args []string) {
	if len(args) == 0 {
		metricsUsage()
		os.Exit(1)
	}

	switch args[0] {
	case "get":
		metricsGet(args[1:])
	case "keys":
		metricsKeys(args[1:])
	case "aggregate":
		metricsAggregate(args[1:])
	case "timeline":
		metricsTimeline(args[1:])
	case "category":
		metricsCategory(args[1:])
	case "push":
		metricsPush(args[1:])
	case "help", "-h", "--help":
		metricsUsage()
	default:
		fmt.Fprintf(os.Stderr, "unknown metrics command: %s\n", args[0])
		metricsUsage()
		os.Exit(1)
	}
}

func metricsGet(args []string) {
	fs := flag.NewFlagSet("metrics get", flag.ExitOnError)
	opts := addCommonFlags(fs)
	key := fs.String("key", "", "Metrics key (optional)")
	from := fs.String("from", "", "RFC3339 start timestamp")
	to := fs.String("to", "", "RFC3339 end timestamp")
	granularity := fs.String("granularity", "", "Granularity (e.g. 1h, 1d)")
	fs.Parse(args)

	if err := ensureToken(opts, true); err != nil {
		exitError(err)
	}

	fromValue, toValue, err := resolveTimeRange(*from, *to)
	if err != nil {
		exitError(err)
	}

	client, err := newClient(opts)
	if err != nil {
		exitError(err)
	}

	granularityValue, err := resolveGranularityValue(context.Background(), client, *granularity)
	if err != nil {
		exitError(err)
	}

	params := map[string]string{
		"from":        fromValue,
		"to":          toValue,
		"granularity": granularityValue,
	}
	if *key != "" {
		params["key"] = *key
	}

	var response map[string]any
	if err := client.GetMetrics(context.Background(), params, &response); err != nil {
		exitError(err)
	}

	if err := output.PrintJSON(os.Stdout, response); err != nil {
		exitError(err)
	}
}

func metricsKeys(args []string) {
	fs := flag.NewFlagSet("metrics keys", flag.ExitOnError)
	opts := addCommonFlags(fs)
	from := fs.String("from", "", "RFC3339 start timestamp")
	to := fs.String("to", "", "RFC3339 end timestamp")
	granularity := fs.String("granularity", "", "Granularity (e.g. 1h, 1d)")
	format := fs.String("format", "json", "Output format: json|table|csv")
	fs.Parse(args)

	if err := ensureToken(opts, true); err != nil {
		exitError(err)
	}

	fromValue, toValue, err := resolveTimeRange(*from, *to)
	if err != nil {
		exitError(err)
	}

	client, err := newClient(opts)
	if err != nil {
		exitError(err)
	}

	granularityValue, err := resolveGranularityValue(context.Background(), client, *granularity)
	if err != nil {
		exitError(err)
	}

	params := map[string]string{
		"from":        fromValue,
		"to":          toValue,
		"granularity": granularityValue,
	}

	var response metricsResponse
	if err := client.GetMetrics(context.Background(), params, &response); err != nil {
		exitError(err)
	}

	entries := summarizeKeys(response.Data.Values)
	payload := map[string]any{
		"status": "ok",
		"timeframe": map[string]string{
			"from":        fromValue,
			"to":          toValue,
			"granularity": granularityValue,
		},
		"paths":       entries,
		"total_paths": len(entries),
	}

	switch strings.ToLower(*format) {
	case "table", "csv":
		table := output.Table{Columns: []string{"metric_key", "observations"}}
		for _, entry := range entries {
			table.Rows = append(table.Rows, []string{entry.MetricKey, fmt.Sprint(entry.Observations)})
		}
		if *format == "table" {
			output.PrintTable(os.Stdout, table)
		} else if err := output.PrintCSV(os.Stdout, table); err != nil {
			exitError(err)
		}
	default:
		if err := output.PrintJSON(os.Stdout, payload); err != nil {
			exitError(err)
		}
	}
}

func metricsAggregate(args []string) {
	fs := flag.NewFlagSet("metrics aggregate", flag.ExitOnError)
	opts := addCommonFlags(fs)
	key := fs.String("key", "", "Metrics key")
	valuePath := fs.String("value-path", "", "Value path")
	aggregator := fs.String("aggregator", "", "Aggregator (sum|mean|min|max)")
	from := fs.String("from", "", "RFC3339 start timestamp")
	to := fs.String("to", "", "RFC3339 end timestamp")
	granularity := fs.String("granularity", "", "Granularity (e.g. 1h, 1d)")
	slices := fs.Int("slices", 1, "Optional number of slices")
	format := fs.String("format", "json", "Output format: json|table|csv")
	fs.Parse(args)

	if *key == "" || *valuePath == "" || *aggregator == "" {
		exitError(errors.New("--key, --value-path, and --aggregator are required"))
	}

	if err := ensureToken(opts, true); err != nil {
		exitError(err)
	}

	fromValue, toValue, err := resolveTimeRange(*from, *to)
	if err != nil {
		exitError(err)
	}

	client, err := newClient(opts)
	if err != nil {
		exitError(err)
	}

	granularityValue, err := resolveGranularityValue(context.Background(), client, *granularity)
	if err != nil {
		exitError(err)
	}

	payload := map[string]any{
		"mode":        "aggregate",
		"key":         *key,
		"value_path":  *valuePath,
		"aggregator":  *aggregator,
		"from":        fromValue,
		"to":          toValue,
		"granularity": granularityValue,
		"slices":      *slices,
	}

	data, err := queryMetrics(context.Background(), client, payload)
	if err != nil {
		exitError(err)
	}

	if err := output.PrintTableOrJSON(data, strings.ToLower(*format)); err != nil {
		exitError(err)
	}
}

func metricsTimeline(args []string) {
	fs := flag.NewFlagSet("metrics timeline", flag.ExitOnError)
	opts := addCommonFlags(fs)
	key := fs.String("key", "", "Metrics key")
	valuePath := fs.String("value-path", "", "Value path")
	from := fs.String("from", "", "RFC3339 start timestamp")
	to := fs.String("to", "", "RFC3339 end timestamp")
	granularity := fs.String("granularity", "", "Granularity (e.g. 1h, 1d)")
	slices := fs.Int("slices", 1, "Optional number of slices")
	format := fs.String("format", "json", "Output format: json|table|csv")
	fs.Parse(args)

	if *key == "" || *valuePath == "" {
		exitError(errors.New("--key and --value-path are required"))
	}

	if err := ensureToken(opts, true); err != nil {
		exitError(err)
	}

	fromValue, toValue, err := resolveTimeRange(*from, *to)
	if err != nil {
		exitError(err)
	}

	client, err := newClient(opts)
	if err != nil {
		exitError(err)
	}

	granularityValue, err := resolveGranularityValue(context.Background(), client, *granularity)
	if err != nil {
		exitError(err)
	}

	payload := map[string]any{
		"mode":        "timeline",
		"key":         *key,
		"value_path":  *valuePath,
		"from":        fromValue,
		"to":          toValue,
		"granularity": granularityValue,
		"slices":      *slices,
	}

	data, err := queryMetrics(context.Background(), client, payload)
	if err != nil {
		exitError(err)
	}

	if err := output.PrintTableOrJSON(data, strings.ToLower(*format)); err != nil {
		exitError(err)
	}
}

func metricsCategory(args []string) {
	fs := flag.NewFlagSet("metrics category", flag.ExitOnError)
	opts := addCommonFlags(fs)
	key := fs.String("key", "", "Metrics key")
	valuePath := fs.String("value-path", "", "Value path")
	from := fs.String("from", "", "RFC3339 start timestamp")
	to := fs.String("to", "", "RFC3339 end timestamp")
	granularity := fs.String("granularity", "", "Granularity (e.g. 1h, 1d)")
	slices := fs.Int("slices", 1, "Optional number of slices")
	format := fs.String("format", "json", "Output format: json|table|csv")
	fs.Parse(args)

	if *key == "" || *valuePath == "" {
		exitError(errors.New("--key and --value-path are required"))
	}

	if err := ensureToken(opts, true); err != nil {
		exitError(err)
	}

	fromValue, toValue, err := resolveTimeRange(*from, *to)
	if err != nil {
		exitError(err)
	}

	client, err := newClient(opts)
	if err != nil {
		exitError(err)
	}

	granularityValue, err := resolveGranularityValue(context.Background(), client, *granularity)
	if err != nil {
		exitError(err)
	}

	payload := map[string]any{
		"mode":        "category",
		"key":         *key,
		"value_path":  *valuePath,
		"from":        fromValue,
		"to":          toValue,
		"granularity": granularityValue,
		"slices":      *slices,
	}

	data, err := queryMetrics(context.Background(), client, payload)
	if err != nil {
		exitError(err)
	}

	if err := output.PrintTableOrJSON(data, strings.ToLower(*format)); err != nil {
		exitError(err)
	}
}

func metricsPush(args []string) {
	fs := flag.NewFlagSet("metrics push", flag.ExitOnError)
	opts := addCommonFlags(fs)
	key := fs.String("key", "", "Metrics key")
	at := fs.String("at", "", "RFC3339 timestamp (default: now)")
	valuesJSON := fs.String("values", "", "Values payload as JSON")
	valuesFile := fs.String("values-file", "", "Path to JSON file with values payload")
	fs.Parse(args)

	if *key == "" {
		exitError(errors.New("--key is required"))
	}

	if err := ensureToken(opts, true); err != nil {
		exitError(err)
	}

	values, err := loadJSONPayload(*valuesJSON, *valuesFile)
	if err != nil {
		exitError(err)
	}

	if values == nil {
		exitError(errors.New("--values or --values-file is required"))
	}

	atValue := strings.TrimSpace(*at)
	if atValue == "" {
		atValue = time.Now().UTC().Format(time.RFC3339)
	} else if err := validateTimestamp("at", atValue); err != nil {
		exitError(err)
	}

	client, err := newClient(opts)
	if err != nil {
		exitError(err)
	}

	payload := map[string]any{
		"key":    *key,
		"at":     atValue,
		"values": values,
	}

	var response map[string]any
	if err := client.PostMetrics(context.Background(), payload, &response); err != nil {
		exitError(err)
	}

	if err := output.PrintJSON(os.Stdout, response); err != nil {
		exitError(err)
	}
}

func runTransponders(args []string) {
	if len(args) == 0 {
		transponderUsage()
		os.Exit(1)
	}

	switch args[0] {
	case "list":
		transpondersList(args[1:])
	case "create":
		transpondersCreate(args[1:])
	case "update":
		transpondersUpdate(args[1:])
	case "help", "-h", "--help":
		transponderUsage()
	default:
		fmt.Fprintf(os.Stderr, "unknown transponders command: %s\n", args[0])
		transponderUsage()
		os.Exit(1)
	}
}

func transpondersList(args []string) {
	fs := flag.NewFlagSet("transponders list", flag.ExitOnError)
	opts := addCommonFlags(fs)
	fs.Parse(args)

	if err := ensureToken(opts, true); err != nil {
		exitError(err)
	}

	client, err := newClient(opts)
	if err != nil {
		exitError(err)
	}

	var response map[string]any
	if err := client.GetTransponders(context.Background(), &response); err != nil {
		exitError(err)
	}

	if err := output.PrintJSON(os.Stdout, response); err != nil {
		exitError(err)
	}
}

func transpondersCreate(args []string) {
	fs := flag.NewFlagSet("transponders create", flag.ExitOnError)
	opts := addCommonFlags(fs)
	payloadJSON := fs.String("payload", "", "JSON payload for transponder")
	payloadFile := fs.String("payload-file", "", "Path to JSON file for payload")
	fs.Parse(args)

	if err := ensureToken(opts, true); err != nil {
		exitError(err)
	}

	payload, err := loadJSONPayload(*payloadJSON, *payloadFile)
	if err != nil {
		exitError(err)
	}
	if payload == nil {
		exitError(errors.New("--payload or --payload-file is required"))
	}
	payloadMap, ok := payload.(map[string]any)
	if !ok {
		exitError(errors.New("payload must be a JSON object"))
	}

	client, err := newClient(opts)
	if err != nil {
		exitError(err)
	}

	var response map[string]any
	if err := client.CreateTransponder(context.Background(), payloadMap, &response); err != nil {
		exitError(err)
	}

	if err := output.PrintJSON(os.Stdout, response); err != nil {
		exitError(err)
	}
}

func transpondersUpdate(args []string) {
	fs := flag.NewFlagSet("transponders update", flag.ExitOnError)
	opts := addCommonFlags(fs)
	id := fs.String("id", "", "Transponder ID")
	payloadJSON := fs.String("payload", "", "JSON payload for transponder")
	payloadFile := fs.String("payload-file", "", "Path to JSON file for payload")
	fs.Parse(args)

	if *id == "" {
		exitError(errors.New("--id is required"))
	}

	if err := ensureToken(opts, true); err != nil {
		exitError(err)
	}

	payload, err := loadJSONPayload(*payloadJSON, *payloadFile)
	if err != nil {
		exitError(err)
	}
	if payload == nil {
		exitError(errors.New("--payload or --payload-file is required"))
	}
	payloadMap, ok := payload.(map[string]any)
	if !ok {
		exitError(errors.New("payload must be a JSON object"))
	}

	client, err := newClient(opts)
	if err != nil {
		exitError(err)
	}

	var response map[string]any
	if err := client.UpdateTransponder(context.Background(), *id, payloadMap, &response); err != nil {
		exitError(err)
	}

	if err := output.PrintJSON(os.Stdout, response); err != nil {
		exitError(err)
	}
}

type metricsResponse struct {
	Data seriesData `json:"data"`
}

type seriesData struct {
	At     []string                 `json:"at"`
	Values []map[string]interface{} `json:"values"`
}

type keysEntry struct {
	MetricKey    string `json:"metric_key"`
	Observations int64  `json:"observations"`
}

type sourceResponse struct {
	Data sourceConfig `json:"data"`
}

type sourceConfig struct {
	DefaultGranularity     string   `json:"default_granularity"`
	AvailableGranularities []string `json:"available_granularities"`
}

func summarizeKeys(values []map[string]interface{}) []keysEntry {
	counts := map[string]int64{}

	for _, row := range values {
		rawKeys, ok := row["keys"]
		if !ok {
			continue
		}

		keysMap, ok := rawKeys.(map[string]interface{})
		if !ok {
			continue
		}

		for key, value := range keysMap {
			counts[key] += toInt64(value)
		}
	}

	keys := make([]string, 0, len(counts))
	for key := range counts {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	entries := make([]keysEntry, 0, len(keys))
	for _, key := range keys {
		entries = append(entries, keysEntry{MetricKey: key, Observations: counts[key]})
	}

	return entries
}

func toInt64(value interface{}) int64 {
	switch v := value.(type) {
	case float64:
		return int64(v)
	case float32:
		return int64(v)
	case int64:
		return v
	case int:
		return int64(v)
	case json.Number:
		if parsed, err := v.Int64(); err == nil {
			return parsed
		}
	}

	return 0
}

func resolveTimeRange(from, to string) (string, string, error) {
	from = strings.TrimSpace(from)
	to = strings.TrimSpace(to)

	if from == "" && to == "" {
		now := time.Now().UTC()
		from = now.Add(-24 * time.Hour).Format(time.RFC3339)
		to = now.Format(time.RFC3339)
		return from, to, nil
	}

	if from == "" || to == "" {
		return "", "", fmt.Errorf("from and to are required together (RFC3339, e.g. 2024-01-02T15:04:05Z)")
	}

	if err := validateTimestamp("from", from); err != nil {
		return "", "", err
	}
	if err := validateTimestamp("to", to); err != nil {
		return "", "", err
	}

	return from, to, nil
}

func validateTimestamp(label, value string) error {
	if _, err := time.Parse(time.RFC3339Nano, value); err != nil {
		return fmt.Errorf("%s must be RFC3339 (e.g. 2024-01-02T15:04:05Z or 2024-01-02T15:04:05+00:00)", label)
	}
	return nil
}

func resolveGranularityValue(ctx context.Context, client *api.Client, granularity string) (string, error) {
	granularity = strings.TrimSpace(granularity)
	if granularity == "" {
		return resolveGranularity(ctx, client)
	}
	return validateGranularity(granularity)
}

func validateGranularity(value string) (string, error) {
	normalized := strings.ToLower(strings.TrimSpace(value))
	if normalized == "" {
		return "", fmt.Errorf("granularity is required")
	}
	if !granularityPattern.MatchString(normalized) {
		return "", fmt.Errorf("granularity must be <number><unit> using s, m, h, d, w, mo, q, y (e.g. 1h, 15m, 1d)")
	}
	return normalized, nil
}

func resolveGranularity(ctx context.Context, client *api.Client) (string, error) {
	var response sourceResponse
	if err := client.GetSource(ctx, &response); err != nil {
		return "", err
	}

	if response.Data.DefaultGranularity != "" {
		return response.Data.DefaultGranularity, nil
	}

	available := response.Data.AvailableGranularities
	for _, candidate := range []string{"1h", "1d"} {
		for _, value := range available {
			if value == candidate {
				return candidate, nil
			}
		}
	}

	if len(available) > 0 {
		return available[0], nil
	}

	return "1h", nil
}

func queryMetrics(ctx context.Context, client *api.Client, payload map[string]any) (map[string]any, error) {
	var response map[string]any
	if err := client.QueryMetrics(ctx, payload, &response); err != nil {
		return nil, err
	}

	rawData, ok := response["data"]
	if !ok {
		return nil, fmt.Errorf("missing data in response")
	}

	data, ok := rawData.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("unexpected data shape")
	}

	return data, nil
}

func loadJSONPayload(rawJSON, filePath string) (any, error) {
	if filePath != "" {
		contents, err := os.ReadFile(filepath.Clean(filePath))
		if err != nil {
			return nil, fmt.Errorf("read payload file: %w", err)
		}
		rawJSON = string(contents)
	}

	if strings.TrimSpace(rawJSON) == "" {
		return nil, nil
	}

	var payload any
	if err := json.Unmarshal([]byte(rawJSON), &payload); err != nil {
		return nil, fmt.Errorf("parse JSON payload: %w", err)
	}

	return payload, nil
}

func usage() {
	fmt.Println("trifle <command> [options]")
	fmt.Println()
	fmt.Println("Commands:")
	fmt.Println("  metrics        Query or push metrics")
	fmt.Println("  transponders   Manage transponders")
	fmt.Println("  mcp            MCP server mode")
	fmt.Println("  version        Print version")
	fmt.Println()
	fmt.Println("Run 'trifle <command> --help' for details.")
}

func metricsUsage() {
	fmt.Println("trifle metrics <command> [options]")
	fmt.Println()
	fmt.Println("Commands:")
	fmt.Println("  get       Fetch raw timeseries data")
	fmt.Println("  keys      List available metric keys")
	fmt.Println("  aggregate Aggregate a metric series")
	fmt.Println("  timeline  Format a metric timeline")
	fmt.Println("  category  Format a metric category breakdown")
	fmt.Println("  push      Submit a metric payload")
}

func transponderUsage() {
	fmt.Println("trifle transponders <command> [options]")
	fmt.Println()
	fmt.Println("Commands:")
	fmt.Println("  list    List transponders")
	fmt.Println("  create  Create a transponder")
	fmt.Println("  update  Update a transponder")
}

func exitError(err error) {
	var apiErr *api.Error
	if errors.As(err, &apiErr) {
		fmt.Fprintln(os.Stderr, apiErr.Error())
	} else if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
	}
	os.Exit(1)
}
