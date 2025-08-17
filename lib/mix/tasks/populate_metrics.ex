defmodule Mix.Tasks.PopulateMetrics do
  @moduledoc """
  Populates metrics data for testing purposes.
  
  Usage:
    mix populate_metrics --token=your_token_here
    
  Options:
    --token: The API token for the project
    --count: Number of requests to generate (default: 50)
    --hours: Time range in hours (default: 48)
    --batch-size: Size of each batch for large datasets (default: 10)
    --batch-delay: Delay between batches in seconds (default: 3)
  """
  use Mix.Task

  @shortdoc "Populate metrics data for testing"

  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      strict: [
        token: :string,
        count: :integer,
        hours: :integer,
        batch_size: :integer,
        batch_delay: :integer
      ]
    )

    token = opts[:token] || raise "Missing required --token option"
    count = opts[:count] || 50
    hours = opts[:hours] || 48
    batch_size = opts[:batch_size] || 10
    batch_delay = opts[:batch_delay] || 3

    Application.ensure_all_started(:hackney)
    
    # Configure hackney pool to limit concurrent connections - very conservative
    :hackney_pool.start_pool(:trifle_pool, [timeout: 15000, max_connections: 1])
    
    IO.puts("🚀 Starting to populate #{count} metrics in batches of #{batch_size} over #{hours} hours")
    
    # Check server health before starting
    case check_server_health() do
      :ok -> 
        IO.puts("✅ Server health check passed")
      :error -> 
        IO.puts("❌ Server appears to be down or unresponsive. Please restart your Phoenix server and try again.")
        System.halt(1)
    end
    
    # Process metrics in batches
    total_batches = ceil(count / batch_size)
    submitted = 0
    
    1..total_batches
    |> Enum.reduce_while(submitted, fn batch_num, acc_submitted ->
      remaining = count - acc_submitted
      current_batch_size = min(batch_size, remaining)
      
      IO.puts("\n📦 Batch #{batch_num}/#{total_batches}: Submitting #{current_batch_size} metrics (total: #{acc_submitted}/#{count})")
      
      # Process current batch
      batch_result = process_batch(token, current_batch_size, hours, acc_submitted)
      
      case batch_result do
        {:ok, batch_submitted} ->
          new_total = acc_submitted + batch_submitted
          
          if new_total < count do
            IO.puts("⏳ Waiting #{batch_delay} seconds before next batch...")
            Process.sleep(batch_delay * 1000)
          end
          
          {:cont, new_total}
        
        {:error, reason} ->
          IO.puts("❌ Batch #{batch_num} failed: #{reason}")
          {:halt, acc_submitted}
      end
    end)
    
    IO.puts("\n🎉 Completed populating #{count} metrics!")
  end

  defp check_server_health do
    IO.puts("🔍 Checking server health...")
    
    case :hackney.get("http://localhost:4000", [], "", [with_body: true, timeout: 5000, pool: :trifle_pool]) do
      {:ok, status, _headers, _body} when status >= 200 and status < 500 ->
        :ok
      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  defp process_batch(token, batch_size, hours, offset) do
    # Generate timestamps randomly distributed over the time range
    now = DateTime.utc_now()
    start_time = DateTime.shift(now, second: -hours * 3600)
    
    metrics_keys = [
      "page_views",
      "user_signups", 
      "api_calls",
      "errors",
      "performance",
      "sales"
    ]

    1..batch_size
    |> Enum.reduce_while({:ok, 0}, fn i, {:ok, success_count} ->
      # Random timestamp within the range
      random_seconds = :rand.uniform(hours * 3600)
      timestamp = DateTime.shift(start_time, second: random_seconds)
      
      # Random metric key
      key = Enum.random(metrics_keys)
      
      # Generate realistic nested values based on the key
      values = generate_values(key)
      
      # Submit the metric
      case submit_metric(token, key, timestamp, values) do
        {:ok, _} -> 
          new_count = success_count + 1
          global_count = offset + new_count
          
          if rem(global_count, 5) == 0 do
            IO.puts("  ✅ Submitted #{new_count}/#{batch_size} (global: #{global_count})")
          end
          
          # Small delay to avoid overwhelming
          Process.sleep(100)
          {:cont, {:ok, new_count}}
        
        {:error, reason} -> 
          IO.puts("  ❌ Failed to submit metric #{i}: #{reason}")
          # Wait longer on failures
          Process.sleep(1000)
          {:halt, {:error, reason}}
      end
    end)
  end

  defp generate_values("page_views") do
    %{
      "total" => :rand.uniform(1000) + 50,
      "unique" => :rand.uniform(500) + 20,
      "pages" => %{
        "home" => :rand.uniform(300),
        "dashboard" => %{
          "overview" => :rand.uniform(100),
          "analytics" => %{
            "charts" => :rand.uniform(40),
            "tables" => :rand.uniform(30),
            "exports" => %{
              "pdf" => :rand.uniform(10),
              "csv" => :rand.uniform(15),
              "json" => :rand.uniform(8)
            }
          },
          "settings" => :rand.uniform(50)
        },
        "profile" => %{
          "view" => :rand.uniform(60),
          "edit" => :rand.uniform(40),
          "preferences" => %{
            "notifications" => :rand.uniform(20),
            "privacy" => :rand.uniform(15),
            "security" => %{
              "password" => :rand.uniform(8),
              "two_factor" => :rand.uniform(5),
              "sessions" => :rand.uniform(3)
            }
          }
        }
      },
      "sources" => %{
        "direct" => :rand.uniform(200),
        "search" => %{
          "google" => :rand.uniform(250),
          "bing" => :rand.uniform(50),
          "yahoo" => :rand.uniform(30)
        },
        "social" => %{
          "facebook" => :rand.uniform(80),
          "twitter" => :rand.uniform(60),
          "linkedin" => %{
            "organic" => :rand.uniform(25),
            "paid" => :rand.uniform(15),
            "referral" => %{
              "company" => :rand.uniform(8),
              "employee" => :rand.uniform(12),
              "partner" => :rand.uniform(5)
            }
          }
        }
      }
    }
  end

  defp generate_values("user_signups") do
    %{
      "count" => :rand.uniform(20) + 1,
      "sources" => %{
        "organic" => :rand.uniform(10),
        "referral" => :rand.uniform(5),
        "paid" => :rand.uniform(8)
      },
      "conversion_rate" => (:rand.uniform(50) + 10) / 10  # 1.0 - 6.0%
    }
  end

  defp generate_values("api_calls") do
    %{
      "total" => :rand.uniform(5000) + 100,
      "endpoints" => %{
        "/api/users" => %{
          "GET" => :rand.uniform(600),
          "POST" => :rand.uniform(200),
          "PUT" => %{
            "profile" => :rand.uniform(80),
            "preferences" => :rand.uniform(40),
            "security" => %{
              "password" => :rand.uniform(20),
              "mfa" => :rand.uniform(15)
            }
          },
          "DELETE" => :rand.uniform(10)
        },
        "/api/projects" => %{
          "GET" => :rand.uniform(500),
          "POST" => :rand.uniform(150),
          "operations" => %{
            "deploy" => :rand.uniform(80),
            "rollback" => :rand.uniform(20),
            "scale" => %{
              "up" => :rand.uniform(30),
              "down" => :rand.uniform(15),
              "auto" => %{
                "cpu_threshold" => :rand.uniform(10),
                "memory_threshold" => :rand.uniform(8)
              }
            }
          }
        },
        "/api/metrics" => %{
          "ingest" => :rand.uniform(800),
          "query" => %{
            "realtime" => :rand.uniform(400),
            "historical" => %{
              "daily" => :rand.uniform(150),
              "weekly" => :rand.uniform(80),
              "monthly" => %{
                "aggregated" => :rand.uniform(30),
                "detailed" => :rand.uniform(20)
              }
            }
          }
        },
        "/api/tokens" => %{
          "create" => :rand.uniform(50),
          "validate" => :rand.uniform(200),
          "revoke" => %{
            "manual" => :rand.uniform(10),
            "expired" => :rand.uniform(15),
            "suspicious" => %{
              "brute_force" => :rand.uniform(3),
              "anomaly" => :rand.uniform(2)
            }
          }
        }
      },
      "status_codes" => %{
        "2xx" => %{
          "200" => :rand.uniform(3500) + 400,
          "201" => :rand.uniform(300),
          "204" => %{
            "delete" => :rand.uniform(50),
            "update" => :rand.uniform(80)
          }
        },
        "4xx" => %{
          "400" => %{
            "validation" => :rand.uniform(60),
            "malformed" => :rand.uniform(30)
          },
          "401" => :rand.uniform(40),
          "403" => %{
            "permission" => :rand.uniform(20),
            "rate_limit" => %{
              "hourly" => :rand.uniform(8),
              "daily" => :rand.uniform(5)
            }
          },
          "404" => :rand.uniform(25)
        },
        "5xx" => %{
          "500" => %{
            "internal" => :rand.uniform(15),
            "database" => %{
              "timeout" => :rand.uniform(3),
              "connection" => :rand.uniform(2)
            }
          },
          "503" => :rand.uniform(5)
        }
      }
    }
  end

  defp generate_values("errors") do
    %{
      "count" => :rand.uniform(30),
      "types" => %{
        "validation" => %{
          "form" => %{
            "required_fields" => :rand.uniform(8),
            "invalid_format" => :rand.uniform(5),
            "length" => %{
              "too_short" => :rand.uniform(3),
              "too_long" => :rand.uniform(2)
            }
          },
          "api" => :rand.uniform(4)
        },
        "database" => %{
          "connection" => :rand.uniform(2),
          "query" => %{
            "syntax" => :rand.uniform(1),
            "timeout" => :rand.uniform(2),
            "deadlock" => :rand.uniform(1)
          }
        },
        "network" => %{
          "timeout" => :rand.uniform(4),
          "connection_refused" => :rand.uniform(2),
          "dns" => %{
            "resolution" => :rand.uniform(1),
            "server_failure" => :rand.uniform(1)
          }
        },
        "authentication" => %{
          "invalid_credentials" => :rand.uniform(6),
          "expired_token" => :rand.uniform(3),
          "permission_denied" => %{
            "read" => :rand.uniform(1),
            "write" => :rand.uniform(2),
            "admin" => %{
              "user_management" => :rand.uniform(1),
              "system_config" => :rand.uniform(1)
            }
          }
        }
      },
      "severity" => %{
        "low" => %{
          "warning" => :rand.uniform(15),
          "info" => :rand.uniform(10),
          "debug" => %{
            "trace" => :rand.uniform(5),
            "performance" => :rand.uniform(3)
          }
        },
        "medium" => %{
          "error" => :rand.uniform(6),
          "degraded" => %{
            "slow_response" => :rand.uniform(2),
            "partial_failure" => :rand.uniform(1)
          }
        },
        "high" => %{
          "critical" => :rand.uniform(2),
          "fatal" => %{
            "system_crash" => :rand.uniform(1),
            "data_corruption" => %{
              "database" => :rand.uniform(2), # 1-2
              "file_system" => :rand.uniform(2) # 1-2
            }
          }
        }
      }
    }
  end

  defp generate_values("performance") do
    %{
      "avg_response_time" => :rand.uniform(2000) + 100,  # 100-2100ms
      "requests" => %{
        "fast" => %{
          "under_100ms" => :rand.uniform(400),
          "100_to_500ms" => %{
            "database" => :rand.uniform(200),
            "api" => :rand.uniform(150),
            "static" => %{
              "images" => :rand.uniform(50),
              "css" => :rand.uniform(30),
              "js" => %{
                "framework" => :rand.uniform(20),
                "application" => :rand.uniform(15)
              }
            }
          }
        },
        "medium" => %{
          "500ms_to_1s" => :rand.uniform(200),
          "1s_to_2s" => %{
            "complex_query" => :rand.uniform(80),
            "external_api" => %{
              "third_party" => :rand.uniform(40),
              "payment" => %{
                "stripe" => :rand.uniform(15),
                "paypal" => :rand.uniform(10)
              }
            }
          }
        },
        "slow" => %{
          "2s_to_5s" => :rand.uniform(60),
          "over_5s" => %{
            "timeout" => :rand.uniform(30),
            "heavy_computation" => %{
              "report_generation" => :rand.uniform(15),
              "data_export" => %{
                "csv" => :rand.uniform(8),
                "pdf" => :rand.uniform(5),
                "bulk_operations" => %{
                  "user_import" => :rand.uniform(3),
                  "data_migration" => :rand.uniform(2)
                }
              }
            }
          }
        }
      },
      "system" => %{
        "memory_usage" => %{
          "heap" => (:rand.uniform(60) + 20),  # 20-80%
          "non_heap" => %{
            "metaspace" => (:rand.uniform(30) + 10),
            "compressed_class" => (:rand.uniform(20) + 5)
          }
        },
        "cpu_usage" => %{
          "user" => (:rand.uniform(40) + 10),    # 10-50%
          "system" => (:rand.uniform(20) + 5),    # 5-25%
          "io_wait" => %{
            "disk" => (:rand.uniform(10) + 2),
            "network" => %{
              "inbound" => (:rand.uniform(5) + 1),
              "outbound" => (:rand.uniform(3) + 1)
            }
          }
        },
        "disk" => %{
          "usage" => (:rand.uniform(70) + 10),    # 10-80%
          "iops" => %{
            "read" => :rand.uniform(1000) + 100,
            "write" => %{
              "application" => :rand.uniform(500),
              "logs" => :rand.uniform(200),
              "temp" => %{
                "cache" => :rand.uniform(100),
                "session" => :rand.uniform(50)
              }
            }
          }
        }
      }
    }
  end

  defp generate_values("sales") do
    %{
      "revenue" => :rand.uniform(10000) + 500,  # $500-$10500
      "orders" => :rand.uniform(50) + 5,
      "products" => %{
        "premium" => :rand.uniform(20),
        "basic" => :rand.uniform(30),
        "enterprise" => :rand.uniform(5)
      },
      "avg_order_value" => (:rand.uniform(500) + 100) / 10  # $10-$60
    }
  end

  defp generate_values(_key) do
    # Fallback generic structure
    %{
      "count" => :rand.uniform(100) + 1,
      "value" => :rand.uniform(1000) + 50,
      "categories" => %{
        "a" => :rand.uniform(200),
        "b" => :rand.uniform(150),
        "c" => :rand.uniform(100)
      }
    }
  end

  defp submit_metric(token, key, timestamp, values) do
    url = "http://localhost:4000/api/metrics"
    
    payload = %{
      "key" => key,
      "at" => DateTime.to_iso8601(timestamp),
      "values" => values
    }
    
    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{token}"}
    ]
    
    body = Jason.encode!(payload)
    
    case :hackney.post(url, headers, body, [with_body: true, pool: :trifle_pool]) do
      {:ok, 201, _headers, response_body} ->
        {:ok, response_body}
      {:ok, status, _headers, response_body} ->
        {:error, "HTTP #{status}: #{response_body}"}
      {:error, reason} ->
        {:error, reason}
    end
  end
end