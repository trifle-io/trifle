package main

import (
  "bufio"
  "context"
  "encoding/json"
  "errors"
  "flag"
  "fmt"
  "io"
  "net/url"
  "os"
  "strings"
  "time"

  "github.com/trifle-io/trifle/cli/internal/api"
)

const mcpProtocolVersion = "2024-11-05"

func runMCP(args []string) {
  fs := flag.NewFlagSet("mcp", flag.ExitOnError)
  opts := addCommonFlags(fs)
  fs.Parse(args)

  if err := ensureToken(opts, false); err != nil {
    exitError(err)
  }

  client, err := newClient(opts)
  if err != nil {
    exitError(err)
  }

  if err := serveMCP(context.Background(), client); err != nil {
    exitError(err)
  }
}

type rpcRequest struct {
  JSONRPC string          `json:"jsonrpc"`
  ID      json.RawMessage `json:"id,omitempty"`
  Method  string          `json:"method"`
  Params  json.RawMessage `json:"params,omitempty"`
}

type rpcResponse struct {
  JSONRPC string          `json:"jsonrpc"`
  ID      json.RawMessage `json:"id,omitempty"`
  Result  any             `json:"result,omitempty"`
  Error   *rpcError       `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

func (e *rpcError) Error() string {
	if e == nil {
		return ""
	}
	if e.Message == "" {
		return fmt.Sprintf("rpc error %d", e.Code)
	}
	return e.Message
}

type toolDefinition struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	InputSchema map[string]any `json:"inputSchema"`
}

type toolCallParams struct {
  Name      string         `json:"name"`
  Arguments map[string]any `json:"arguments"`
}

type initializeParams struct {
  ProtocolVersion string         `json:"protocolVersion"`
  Capabilities    map[string]any `json:"capabilities"`
  ClientInfo      map[string]any `json:"clientInfo"`
}

type resourceDescriptor struct {
  URI         string `json:"uri"`
  Name        string `json:"name"`
  Description string `json:"description"`
  MimeType    string `json:"mimeType,omitempty"`
}

type resourceReadParams struct {
  URI string `json:"uri"`
}

type contentItem struct {
  Type string `json:"type"`
  Text string `json:"text"`
}

type toolResult struct {
  Content []contentItem `json:"content"`
  IsError bool          `json:"isError,omitempty"`
}

type resourceReadResult struct {
  Contents []map[string]any `json:"contents"`
}

func serveMCP(ctx context.Context, client *api.Client) error {
  decoder := json.NewDecoder(bufio.NewReader(os.Stdin))
  decoder.UseNumber()
  encoder := json.NewEncoder(os.Stdout)

  for {
    var req rpcRequest
    if err := decoder.Decode(&req); err != nil {
      if errors.Is(err, io.EOF) {
        return nil
      }
      return err
    }

    if req.JSONRPC == "" {
      continue
    }

    response, err := handleMCPRequest(ctx, client, req)
    if err != nil {
      if len(req.ID) == 0 {
        continue
      }

      rpcErr, ok := err.(*rpcError)
      if !ok {
        rpcErr = &rpcError{Code: -32603, Message: err.Error()}
      }

      response = &rpcResponse{
        JSONRPC: "2.0",
        ID:      req.ID,
        Error:   rpcErr,
      }
    }

    if response == nil {
      continue
    }

    if err := encoder.Encode(response); err != nil {
      return err
    }

    if req.Method == "exit" {
      return nil
    }
  }
}

func handleMCPRequest(ctx context.Context, client *api.Client, req rpcRequest) (*rpcResponse, error) {
  switch req.Method {
  case "initialize":
    params := initializeParams{}
    if len(req.Params) > 0 {
      if err := json.Unmarshal(req.Params, &params); err != nil {
        return nil, invalidParamsError("invalid initialize params")
      }
    }

    protocol := params.ProtocolVersion
    if protocol == "" {
      protocol = mcpProtocolVersion
    }

    result := map[string]any{
      "protocolVersion": protocol,
      "capabilities": map[string]any{
        "tools": map[string]any{
          "listChanged": false,
        },
        "resources": map[string]any{
          "listChanged": false,
        },
      },
      "serverInfo": map[string]any{
        "name":    "trifle-cli",
        "version": version,
      },
    }

    return rpcResult(req.ID, result), nil
  case "initialized":
    return nil, nil
  case "shutdown":
    return rpcResult(req.ID, map[string]any{}), nil
  case "exit":
    return rpcResult(req.ID, map[string]any{}), nil
  case "tools/list":
    return rpcResult(req.ID, map[string]any{"tools": toolDefinitions()}), nil
  case "tools/call":
    return handleToolCall(ctx, client, req)
  case "resources/list":
    return rpcResult(req.ID, map[string]any{"resources": resourceList()}), nil
  case "resources/read":
    return handleResourceRead(ctx, client, req)
  default:
    return nil, methodNotFoundError(fmt.Sprintf("method not found: %s", req.Method))
  }
}

func handleToolCall(ctx context.Context, client *api.Client, req rpcRequest) (*rpcResponse, error) {
  if len(req.Params) == 0 {
    return nil, invalidParamsError("missing params")
  }

  var params toolCallParams
  if err := json.Unmarshal(req.Params, &params); err != nil {
    return nil, invalidParamsError("invalid tool call params")
  }

  if params.Name == "" {
    return nil, invalidParamsError("tool name required")
  }

  if params.Arguments == nil {
    params.Arguments = map[string]any{}
  }

  result, err := executeTool(ctx, client, params.Name, params.Arguments)
  if err != nil {
    return rpcResult(req.ID, toolErrorResult(err)), nil
  }

  return rpcResult(req.ID, result), nil
}

func handleResourceRead(ctx context.Context, client *api.Client, req rpcRequest) (*rpcResponse, error) {
  if len(req.Params) == 0 {
    return nil, invalidParamsError("missing params")
  }

  var params resourceReadParams
  if err := json.Unmarshal(req.Params, &params); err != nil {
    return nil, invalidParamsError("invalid resource params")
  }

  if params.URI == "" {
    return nil, invalidParamsError("uri required")
  }

  payload, err := readResource(ctx, client, params.URI)
  if err != nil {
    return rpcResult(req.ID, toolErrorResult(err)), nil
  }

  return rpcResult(req.ID, payload), nil
}

func executeTool(ctx context.Context, client *api.Client, name string, args map[string]any) (toolResult, error) {
  switch name {
  case "list_metrics":
    payload, err := listMetricsPayload(ctx, client, args)
    if err != nil {
      return toolResult{}, err
    }
    return toolResultFromJSON(payload), nil
  case "fetch_series":
    payload, err := fetchSeriesPayload(ctx, client, args)
    if err != nil {
      return toolResult{}, err
    }
    return toolResultFromJSON(payload), nil
  case "aggregate_series":
    payload, err := queryPayload(ctx, client, "aggregate", args)
    if err != nil {
      return toolResult{}, err
    }
    return toolResultFromJSON(payload), nil
  case "format_timeline":
    payload, err := queryPayload(ctx, client, "timeline", args)
    if err != nil {
      return toolResult{}, err
    }
    return toolResultFromJSON(payload), nil
  case "format_category":
    payload, err := queryPayload(ctx, client, "category", args)
    if err != nil {
      return toolResult{}, err
    }
    return toolResultFromJSON(payload), nil
  case "write_metric":
    payload, err := writeMetricPayload(ctx, client, args)
    if err != nil {
      return toolResult{}, err
    }
    return toolResultFromJSON(payload), nil
  case "list_transponders":
    payload, err := listTranspondersPayload(ctx, client)
    if err != nil {
      return toolResult{}, err
    }
    return toolResultFromJSON(payload), nil
  default:
    return toolResult{}, fmt.Errorf("unknown tool: %s", name)
  }
}

func listMetricsPayload(ctx context.Context, client *api.Client, args map[string]any) (map[string]any, error) {
  from, to, err := resolveTimeRange(getStringArg(args, "from"), getStringArg(args, "to"))
  if err != nil {
    return nil, err
  }

  granularity := getStringArg(args, "granularity")
  if granularity == "" {
    granularity, err = resolveGranularity(ctx, client)
    if err != nil {
      return nil, err
    }
  }

  params := map[string]string{
    "from":        from,
    "to":          to,
    "granularity": granularity,
  }

  var response metricsResponse
  if err := client.GetMetrics(ctx, params, &response); err != nil {
    return nil, err
  }

  entries := summarizeKeys(response.Data.Values)

  payload := map[string]any{
    "status": "ok",
    "timeframe": map[string]string{
      "from":        from,
      "to":          to,
      "granularity": granularity,
    },
    "paths":       entries,
    "total_paths": len(entries),
  }

  return payload, nil
}

func fetchSeriesPayload(ctx context.Context, client *api.Client, args map[string]any) (map[string]any, error) {
  from, to, err := resolveTimeRange(getStringArg(args, "from"), getStringArg(args, "to"))
  if err != nil {
    return nil, err
  }

  granularity := getStringArg(args, "granularity")
  if granularity == "" {
    granularity, err = resolveGranularity(ctx, client)
    if err != nil {
      return nil, err
    }
  }

  params := map[string]string{
    "from":        from,
    "to":          to,
    "granularity": granularity,
  }

  key := strings.TrimSpace(getStringArg(args, "key"))
  if key != "" {
    params["key"] = key
  }

  var response metricsResponse
  if err := client.GetMetrics(ctx, params, &response); err != nil {
    return nil, err
  }

  usedKey := key
  if usedKey == "" {
    usedKey = "__system__key__"
  }

  payload := map[string]any{
    "status":     "ok",
    "metric_key": usedKey,
    "timeframe": map[string]string{
      "from":        from,
      "to":          to,
      "granularity": granularity,
    },
    "data": response.Data,
  }

  return payload, nil
}

func queryPayload(ctx context.Context, client *api.Client, mode string, args map[string]any) (map[string]any, error) {
  key := strings.TrimSpace(getStringArg(args, "key"))
  if key == "" {
    return nil, fmt.Errorf("key is required")
  }

  valuePath := strings.TrimSpace(getStringArg(args, "value_path"))
  if valuePath == "" {
    return nil, fmt.Errorf("value_path is required")
  }

  from, to, err := resolveTimeRange(getStringArg(args, "from"), getStringArg(args, "to"))
  if err != nil {
    return nil, err
  }

  granularity := getStringArg(args, "granularity")
  if granularity == "" {
    granularity, err = resolveGranularity(ctx, client)
    if err != nil {
      return nil, err
    }
  }

  payload := map[string]any{
    "mode":        mode,
    "key":         key,
    "value_path":  valuePath,
    "from":        from,
    "to":          to,
    "granularity": granularity,
  }

  if mode == "aggregate" {
    aggregator := strings.TrimSpace(getStringArg(args, "aggregator"))
    if aggregator == "" {
      return nil, fmt.Errorf("aggregator is required")
    }
    payload["aggregator"] = aggregator
  }

  if slicesValue, ok := args["slices"]; ok {
    payload["slices"] = slicesValue
  }

  data, err := queryMetrics(ctx, client, payload)
  if err != nil {
    return nil, err
  }

  return data, nil
}

func writeMetricPayload(ctx context.Context, client *api.Client, args map[string]any) (map[string]any, error) {
  key := strings.TrimSpace(getStringArg(args, "key"))
  if key == "" {
    return nil, fmt.Errorf("key is required")
  }

  values, ok := args["values"]
  if !ok {
    return nil, fmt.Errorf("values is required")
  }

  at := strings.TrimSpace(getStringArg(args, "at"))
  if at == "" {
    at = time.Now().UTC().Format(time.RFC3339)
  }

  payload := map[string]any{
    "key":    key,
    "at":     at,
    "values": values,
  }

  var response map[string]any
  if err := client.PostMetrics(ctx, payload, &response); err != nil {
    return nil, err
  }

  return response, nil
}

func listTranspondersPayload(ctx context.Context, client *api.Client) (map[string]any, error) {
  var response map[string]any
  if err := client.GetTransponders(ctx, &response); err != nil {
    return nil, err
  }

  return response, nil
}

func readResource(ctx context.Context, client *api.Client, uri string) (resourceReadResult, error) {
  parsed, err := url.Parse(uri)
  if err != nil {
    return resourceReadResult{}, err
  }

  if parsed.Scheme != "trifle" {
    return resourceReadResult{}, fmt.Errorf("unsupported scheme: %s", parsed.Scheme)
  }

  switch parsed.Host {
  case "source":
    var response map[string]any
    if err := client.GetSource(ctx, &response); err != nil {
      return resourceReadResult{}, err
    }
    return resourceResult(uri, response)
  case "transponders":
    var response map[string]any
    if err := client.GetTransponders(ctx, &response); err != nil {
      return resourceReadResult{}, err
    }
    return resourceResult(uri, response)
  case "metrics":
    key := strings.TrimPrefix(parsed.Path, "/")
    query := parsed.Query()
    args := map[string]any{
      "from":        query.Get("from"),
      "to":          query.Get("to"),
      "granularity": query.Get("granularity"),
    }
    if key != "" {
      args["key"] = key
      payload, err := fetchSeriesPayload(ctx, client, args)
      if err != nil {
        return resourceReadResult{}, err
      }
      return resourceResult(uri, payload)
    }

    payload, err := listMetricsPayload(ctx, client, args)
    if err != nil {
      return resourceReadResult{}, err
    }
    return resourceResult(uri, payload)
  default:
    return resourceReadResult{}, fmt.Errorf("unknown resource: %s", parsed.Host)
  }
}

func resourceList() []resourceDescriptor {
  return []resourceDescriptor{
    {
      URI:         "trifle://source",
      Name:        "Source configuration",
      Description: "Active analytics source configuration (defaults and granularities).",
      MimeType:    "application/json",
    },
    {
      URI:         "trifle://metrics",
      Name:        "Metrics listing",
      Description: "Available metrics from __system__key__ (use ?from&to&granularity).",
      MimeType:    "application/json",
    },
    {
      URI:         "trifle://metrics/{key}",
      Name:        "Metric series",
      Description: "Raw series for a metric key (use ?from&to&granularity).",
      MimeType:    "application/json",
    },
    {
      URI:         "trifle://transponders",
      Name:        "Transponders",
      Description: "List transponders for the active source.",
      MimeType:    "application/json",
    },
  }
}

func toolDefinitions() []toolDefinition {
  return []toolDefinition{
    {
      Name:        "list_metrics",
      Description: "List available metric keys from the system series.",
      InputSchema: map[string]any{
        "type":       "object",
        "properties": map[string]any{
          "from":        map[string]any{"type": "string"},
          "to":          map[string]any{"type": "string"},
          "granularity": map[string]any{"type": "string"},
        },
      },
    },
    {
      Name:        "fetch_series",
      Description: "Fetch raw series data for a metric key.",
      InputSchema: map[string]any{
        "type":       "object",
        "properties": map[string]any{
          "key":         map[string]any{"type": "string"},
          "from":        map[string]any{"type": "string"},
          "to":          map[string]any{"type": "string"},
          "granularity": map[string]any{"type": "string"},
        },
      },
    },
    {
      Name:        "aggregate_series",
      Description: "Aggregate a metric series (sum, mean, min, max).",
      InputSchema: map[string]any{
        "type":       "object",
        "properties": map[string]any{
          "key":         map[string]any{"type": "string"},
          "value_path":  map[string]any{"type": "string"},
          "aggregator":  map[string]any{"type": "string", "enum": []string{"sum", "mean", "min", "max"}},
          "from":        map[string]any{"type": "string"},
          "to":          map[string]any{"type": "string"},
          "granularity": map[string]any{"type": "string"},
          "slices":      map[string]any{"type": "integer", "minimum": 1},
        },
        "required": []string{"key", "value_path", "aggregator"},
      },
    },
    {
      Name:        "format_timeline",
      Description: "Format a metric series into timeline entries.",
      InputSchema: map[string]any{
        "type":       "object",
        "properties": map[string]any{
          "key":         map[string]any{"type": "string"},
          "value_path":  map[string]any{"type": "string"},
          "from":        map[string]any{"type": "string"},
          "to":          map[string]any{"type": "string"},
          "granularity": map[string]any{"type": "string"},
          "slices":      map[string]any{"type": "integer", "minimum": 1},
        },
        "required": []string{"key", "value_path"},
      },
    },
    {
      Name:        "format_category",
      Description: "Format a metric series into categorical totals.",
      InputSchema: map[string]any{
        "type":       "object",
        "properties": map[string]any{
          "key":         map[string]any{"type": "string"},
          "value_path":  map[string]any{"type": "string"},
          "from":        map[string]any{"type": "string"},
          "to":          map[string]any{"type": "string"},
          "granularity": map[string]any{"type": "string"},
          "slices":      map[string]any{"type": "integer", "minimum": 1},
        },
        "required": []string{"key", "value_path"},
      },
    },
    {
      Name:        "write_metric",
      Description: "Write a metric event.",
      InputSchema: map[string]any{
        "type":       "object",
        "properties": map[string]any{
          "key": map[string]any{"type": "string"},
          "at":  map[string]any{"type": "string"},
          "values": map[string]any{
            "type": []string{"object", "array", "string", "number", "boolean", "null"},
          },
        },
        "required": []string{"key", "values"},
      },
    },
    {
      Name:        "list_transponders",
      Description: "List transponders for the active source.",
      InputSchema: map[string]any{
        "type":       "object",
        "properties": map[string]any{},
      },
    },
  }
}

func toolResultFromJSON(payload any) toolResult {
  encoded, err := json.MarshalIndent(payload, "", "  ")
  if err != nil {
    return toolErrorResult(err)
  }

  return toolResult{
    Content: []contentItem{
      {Type: "text", Text: string(encoded)},
    },
  }
}

func toolErrorResult(err error) toolResult {
  return toolResult{
    Content: []contentItem{
      {Type: "text", Text: err.Error()},
    },
    IsError: true,
  }
}

func resourceResult(uri string, payload any) (resourceReadResult, error) {
  encoded, err := json.MarshalIndent(payload, "", "  ")
  if err != nil {
    return resourceReadResult{}, err
  }

  return resourceReadResult{
    Contents: []map[string]any{
      {
        "uri":      uri,
        "mimeType": "application/json",
        "text":     string(encoded),
      },
    },
  }, nil
}

func rpcResult(id json.RawMessage, result any) *rpcResponse {
  return &rpcResponse{
    JSONRPC: "2.0",
    ID:      id,
    Result:  result,
  }
}

func invalidParamsError(message string) *rpcError {
  return &rpcError{Code: -32602, Message: message}
}

func methodNotFoundError(message string) *rpcError {
  return &rpcError{Code: -32601, Message: message}
}

func getStringArg(args map[string]any, key string) string {
  value, ok := args[key]
  if !ok || value == nil {
    return ""
  }

  switch v := value.(type) {
  case string:
    return v
  case json.Number:
    return v.String()
  default:
    return fmt.Sprint(v)
  }
}
