package api

import (
  "bytes"
  "context"
  "encoding/json"
  "fmt"
  "io"
  "net/http"
  "net/url"
  "strings"
  "time"
)

const (
  defaultTimeout = 30 * time.Second
  apiBasePath    = "/api/v1"
)

type Client struct {
  baseURL string
  token   string
  http    *http.Client
}

type Error struct {
  StatusCode int
  Body       string
}

func (e *Error) Error() string {
  if e.Body == "" {
    return fmt.Sprintf("api request failed with status %d", e.StatusCode)
  }

  return fmt.Sprintf("api request failed with status %d: %s", e.StatusCode, e.Body)
}

func New(baseURL, token string, timeout time.Duration) (*Client, error) {
  normalized := normalizeBaseURL(baseURL)
  if normalized == "" {
    return nil, fmt.Errorf("missing base URL")
  }

  if _, err := url.ParseRequestURI(normalized); err != nil {
    return nil, fmt.Errorf("invalid base URL: %w", err)
  }

  if timeout <= 0 {
    timeout = defaultTimeout
  }

  return &Client{
    baseURL: normalized,
    token:   token,
    http: &http.Client{
      Timeout: timeout,
    },
  }, nil
}

func (c *Client) SetToken(token string) {
  c.token = token
}

func (c *Client) GetMetrics(ctx context.Context, params map[string]string, out any) error {
  return c.doJSON(ctx, http.MethodGet, apiBasePath+"/metrics", params, out)
}

func (c *Client) PostMetrics(ctx context.Context, payload any, out any) error {
  return c.doJSON(ctx, http.MethodPost, apiBasePath+"/metrics", payload, out)
}

func (c *Client) QueryMetrics(ctx context.Context, payload any, out any) error {
  return c.doJSON(ctx, http.MethodPost, apiBasePath+"/metrics/query", payload, out)
}

func (c *Client) GetSource(ctx context.Context, out any) error {
  return c.doJSON(ctx, http.MethodGet, apiBasePath+"/source", nil, out)
}

func (c *Client) GetTransponders(ctx context.Context, out any) error {
  return c.doJSON(ctx, http.MethodGet, apiBasePath+"/transponders", nil, out)
}

func (c *Client) CreateTransponder(ctx context.Context, payload any, out any) error {
  return c.doJSON(ctx, http.MethodPost, apiBasePath+"/transponders", payload, out)
}

func (c *Client) UpdateTransponder(ctx context.Context, id string, payload any, out any) error {
  return c.doJSON(ctx, http.MethodPut, apiBasePath+"/transponders/"+id, payload, out)
}

func (c *Client) doJSON(ctx context.Context, method, path string, payload any, out any) error {
  fullURL := c.baseURL + path

  var body io.Reader
  if method == http.MethodGet {
    if params, ok := payload.(map[string]string); ok && len(params) > 0 {
      query := url.Values{}
      for key, value := range params {
        if value == "" {
          continue
        }
        query.Set(key, value)
      }
      if encoded := query.Encode(); encoded != "" {
        fullURL += "?" + encoded
      }
    }
  } else if payload != nil {
    encoded, err := json.Marshal(payload)
    if err != nil {
      return fmt.Errorf("encode payload: %w", err)
    }
    body = bytes.NewReader(encoded)
  }

  req, err := http.NewRequestWithContext(ctx, method, fullURL, body)
  if err != nil {
    return fmt.Errorf("build request: %w", err)
  }

  if c.token != "" {
    req.Header.Set("Authorization", "Bearer "+c.token)
  }
  if method != http.MethodGet {
    req.Header.Set("Content-Type", "application/json")
  }

  resp, err := c.http.Do(req)
  if err != nil {
    return fmt.Errorf("request failed: %w", err)
  }
  defer resp.Body.Close()

  responseBody, err := io.ReadAll(resp.Body)
  if err != nil {
    return fmt.Errorf("read response: %w", err)
  }

  if resp.StatusCode >= 400 {
    return &Error{StatusCode: resp.StatusCode, Body: strings.TrimSpace(string(responseBody))}
  }

  if out == nil {
    return nil
  }

  if len(responseBody) == 0 {
    return nil
  }

  if err := json.Unmarshal(responseBody, out); err != nil {
    return fmt.Errorf("decode response: %w", err)
  }

  return nil
}

func normalizeBaseURL(baseURL string) string {
  baseURL = strings.TrimSpace(baseURL)
  if baseURL == "" {
    return ""
  }

  if !strings.HasPrefix(baseURL, "http://") && !strings.HasPrefix(baseURL, "https://") {
    baseURL = "http://" + baseURL
  }

  return strings.TrimRight(baseURL, "/")
}
