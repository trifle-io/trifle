defmodule Mix.Tasks.SeedMetrics do
  @moduledoc """
  Seeds metrics data directly to any Trifle.Stats driver for testing purposes.

  Usage:
    # For project-based drivers
    mix seed_metrics --source=project:0ec3422a-f6d8-42b6-b818-030033407a7e
    
    # For database-based drivers  
    mix seed_metrics --source=database:a1b2c3d4-e5f6-7890-abcd-ef1234567890

  Options:
    --source: Combined source reference in the format "project:<id>" or "database:<id>"
    --type / --id: Legacy flags kept for backward compatibility with existing scripts
    --count: Number of metrics to generate (default: 50)
    --hours: Time range in hours (default: 48)
    --batch-size: Size of each batch for large datasets (default: 100)
    --batch-delay: Delay between batches in milliseconds (default: 100)
  """
  use Mix.Task

  @shortdoc "Seed metrics data directly to any Trifle.Stats driver"

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          source: :string,
          type: :string,
          id: :string,
          count: :integer,
          hours: :integer,
          batch_size: :integer,
          batch_delay: :integer
        ]
      )

    {type, id} =
      case parse_source(opts) do
        {:ok, type, id} -> {type, id}
        {:error, message} -> raise message
      end

    count = opts[:count] || 50
    hours = opts[:hours] || 48
    batch_size = opts[:batch_size] || 100
    batch_delay = opts[:batch_delay] || 100

    # Start the application to access Ecto and other dependencies
    Mix.Task.run("app.start")

    IO.puts("🚀 Starting to seed #{count} metrics in batches of #{batch_size} over #{hours} hours")
    IO.puts("   Type: #{type}, ID: #{id}")

    {source, config} = load_source_and_config(type, id)

    IO.puts("✅ Successfully loaded #{type} configuration")

    maybe_log_transponders(source)
    designator_configs = build_designator_configs(config)

    # Process metrics in batches
    total_batches = ceil(count / batch_size)
    submitted = 0

    1..total_batches
    |> Enum.reduce_while(submitted, fn batch_num, acc_submitted ->
      remaining = count - acc_submitted
      current_batch_size = min(batch_size, remaining)

      IO.puts(
        "\n📦 Batch #{batch_num}/#{total_batches}: Seeding #{current_batch_size} metrics (total: #{acc_submitted}/#{count})"
      )

      # Process current batch
      batch_result =
        process_batch(config, designator_configs, current_batch_size, hours, acc_submitted)

      case batch_result do
        {:ok, batch_submitted} ->
          new_total = acc_submitted + batch_submitted

          if new_total < count do
            if batch_delay > 0 do
              Process.sleep(batch_delay)
            end
          end

          {:cont, new_total}

        {:error, reason} ->
          IO.puts("❌ Batch #{batch_num} failed: #{reason}")
          {:halt, acc_submitted}
      end
    end)

    IO.puts("\n🎉 Completed seeding #{count} metrics!")
  end

  defp load_source_and_config("project", id) do
    try do
      project = Trifle.Organizations.get_project!(id)
      IO.puts("   Project: #{project.name}")

      {Trifle.Stats.Source.from_project(project),
       Trifle.Organizations.Project.stats_config(project)}
    rescue
      Ecto.NoResultsError ->
        raise "Project with ID #{id} not found"
    end
  end

  defp load_source_and_config("database", id) do
    case Trifle.Repo.get(Trifle.Organizations.Database, id) do
      nil ->
        raise "Database with ID #{id} not found"

      database ->
        IO.puts("   Database: #{database.display_name} (#{database.driver})")

        {Trifle.Stats.Source.from_database(database),
         Trifle.Organizations.Database.stats_config(database)}
    end
  end

  defp process_batch(config, designator_configs, batch_size, hours, offset) do
    # Generate timestamps randomly distributed over the time range using the database's timezone
    timezone = config.time_zone || "Etc/UTC"
    now = DateTime.now!(timezone)
    start_time = DateTime.shift(now, second: -hours * 3600)

    metrics_keys = [
      "page_views",
      "user_signups",
      "api_calls",
      "errors",
      "performance",
      "sales",
      "conversion",
      "engagement",
      "retention",
      "revenue",
      "latency_distribution",
      "payload_distribution"
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

      try do
        classification_key = classification_metric_for(key)

        case classification_key do
          nil ->
            _result = Trifle.Stats.track(key, timestamp, values, config)

          designator ->
            class_config = Map.fetch!(designator_configs, designator)
            classified_values = classify_values(values, class_config.designator)
            _result = Trifle.Stats.track(key, timestamp, classified_values, class_config)
            maybe_track_3d_support(key, timestamp, values, designator_configs)
        end

        new_count = success_count + 1
        global_count = offset + new_count

        if rem(global_count, 10) == 0 do
          IO.puts("  ✅ Seeded #{new_count}/#{batch_size} (global: #{global_count})")
        end

        {:cont, {:ok, new_count}}
      rescue
        error ->
          IO.puts("  ❌ Failed to seed metric #{i}: #{inspect(error)}")
          {:halt, {:error, error}}
      end
    end)
  end

  defp parse_source(opts) do
    cond do
      source = opts[:source] ->
        case String.split(source, ":", parts: 2) do
          [type, id] when type in ["project", "database"] -> {:ok, type, id}
          _ -> {:error, "Invalid --source format. Use project:<id> or database:<id>"}
        end

      opts[:type] && opts[:id] ->
        type = opts[:type]

        if type in ["project", "database"] do
          {:ok, type, opts[:id]}
        else
          {:error, "Invalid --type option. Must be 'project' or 'database'"}
        end

      opts[:type] && is_nil(opts[:id]) ->
        {:error, "Missing required --id option"}

      opts[:id] && is_nil(opts[:type]) ->
        {:error, "Missing required --type option (project or database)"}

      true ->
        {:error, "Missing required --source option (project:<id> or database:<id>)"}
    end
  end

  defp build_designator_configs(config) do
    latency_designator = Trifle.Stats.Designator.Linear.new(0, 2_000, 100)
    payload_designator = Trifle.Stats.Designator.Geometric.new(1, 1_000_000)

    %{
      latency: Trifle.Stats.Configuration.set_designator(config, latency_designator),
      payload: Trifle.Stats.Configuration.set_designator(config, payload_designator)
    }
  end

  defp classification_metric_for("latency_distribution"), do: :latency
  defp classification_metric_for("payload_distribution"), do: :payload
  defp classification_metric_for(_), do: nil

  defp maybe_track_3d_support(
         "latency_distribution",
         timestamp,
         %{"latency_ms" => latency_ms},
         designator_configs
       )
       when is_number(latency_ms) do
    case Map.fetch(designator_configs, :latency) do
      {:ok, %{designator: designator} = config} when not is_nil(designator) ->
        x_bucket = bucket_label(designator, latency_ms)
        secondary = jitter_secondary_latency(latency_ms)
        normalized_secondary = normalize_secondary_latency(secondary, latency_ms)
        y_bucket = bucket_label(designator, normalized_secondary)

        if x_bucket && y_bucket do
          payload = %{"latency" => %{x_bucket => %{y_bucket => 1}}}
          _ = Trifle.Stats.track("latency_distribution", timestamp, payload, config)
        end

      _ ->
        :ok
    end
  end

  defp maybe_track_3d_support(_key, _timestamp, _values, _designator_configs), do: :ok

  defp bucket_label(designator, value) when is_number(value) do
    designator.__struct__.designate(designator, value)
    |> to_string()
    |> String.replace(".", "_")
  end

  defp bucket_label(_designator, _value), do: nil

  defp jitter_secondary_latency(latency_ms) when is_number(latency_ms) do
    # Secondary dimension correlated but not identical to primary latency
    variability = 0.55 + :rand.uniform() * 0.9
    shifted = latency_ms * variability + :rand.normal() * 30
    max(1.0, shifted)
  end

  defp normalize_secondary_latency(value, fallback) do
    cond do
      safe_number?(value) ->
        max(1.0, value)

      true ->
        fallback
    end
  end

  defp safe_number?(value) when is_number(value) do
    # In Elixir/Erlang, NaN is the only float that is not equal to itself.
    value == value
  end

  defp safe_number?(_), do: false

  defp classify_values(values, designator) when is_map(values) do
    Map.new(values, fn {k, v} ->
      if is_map(v) do
        {k, classify_values(v, designator)}
      else
        {k, %{classify_value(v, designator) => 1}}
      end
    end)
  end

  defp classify_values(values, _designator), do: values

  defp classify_value(value, designator) when is_number(value) and not is_nil(designator) do
    bucket_label(designator, value)
  end

  defp classify_value(value, _designator), do: to_string(value)

  defp maybe_log_transponders(source) do
    source
    |> Trifle.Stats.Source.transponders()
    |> case do
      [] ->
        :ok

      list ->
        IO.puts("   Transponders (#{length(list)}):")

        Enum.each(list, fn transponder ->
          display = transponder.name || transponder.key
          IO.puts("     • #{display}")
        end)
    end
  end

  # All the generate_values functions remain the same as the original
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
      # 1.0 - 6.0%
      "conversion_rate" => (:rand.uniform(50) + 10) / 10,
      "demographics" => %{
        "age_groups" => %{
          "18_24" => :rand.uniform(5),
          "25_34" => %{
            "professional" => :rand.uniform(8),
            "student" => :rand.uniform(3)
          },
          "35_44" => :rand.uniform(6),
          "45_plus" => %{
            "executive" => :rand.uniform(2),
            "consultant" => :rand.uniform(1)
          }
        }
      }
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
              "database" => :rand.uniform(1),
              "file_system" => :rand.uniform(1)
            }
          }
        }
      }
    }
  end

  defp generate_values("latency_distribution") do
    jitter = :rand.normal() * 75
    base = :rand.uniform(1_800) + 50
    value = Float.round(max(base + jitter, 1.0), 2)

    %{
      "latency_ms" => value,
      "path" => Enum.random(["/api/users", "/api/projects", "/api/auth"])
    }
  end

  defp generate_values("payload_distribution") do
    bucket =
      Enum.random([64, 128, 256, 512, 1_024, 2_048, 4_096, 8_192, 16_384, 65_536, 262_144])

    fluctuation = :rand.uniform(bucket) / 2
    direction = Enum.random([-1, 1])
    value = Float.round(max(bucket + direction * fluctuation, 1.0), 1)

    %{
      "payload_bytes" => value,
      "transport" => Enum.random(["http", "grpc", "websocket"])
    }
  end

  defp generate_values("performance") do
    %{
      # 100-2100ms
      "avg_response_time" => :rand.uniform(2000) + 100,
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
          # 20-80%
          "heap" => :rand.uniform(60) + 20,
          "non_heap" => %{
            "metaspace" => :rand.uniform(30) + 10,
            "compressed_class" => :rand.uniform(20) + 5
          }
        },
        "cpu_usage" => %{
          # 10-50%
          "user" => :rand.uniform(40) + 10,
          # 5-25%
          "system" => :rand.uniform(20) + 5,
          "io_wait" => %{
            "disk" => :rand.uniform(10) + 2,
            "network" => %{
              "inbound" => :rand.uniform(5) + 1,
              "outbound" => :rand.uniform(3) + 1
            }
          }
        }
      }
    }
  end

  defp generate_values("sales") do
    %{
      # $500-$10500
      "revenue" => :rand.uniform(10000) + 500,
      "orders" => :rand.uniform(50) + 5,
      "products" => %{
        "premium" => :rand.uniform(20),
        "basic" => :rand.uniform(30),
        "enterprise" => :rand.uniform(5)
      },
      # $10-$60
      "avg_order_value" => (:rand.uniform(500) + 100) / 10,
      "payment_methods" => %{
        "credit_card" => %{
          "visa" => :rand.uniform(25),
          "mastercard" => :rand.uniform(20),
          "amex" => %{
            "personal" => :rand.uniform(8),
            "business" => :rand.uniform(5)
          }
        },
        "digital" => %{
          "paypal" => :rand.uniform(15),
          "stripe" => :rand.uniform(10),
          "crypto" => %{
            "bitcoin" => :rand.uniform(3),
            "ethereum" => :rand.uniform(2)
          }
        }
      }
    }
  end

  defp generate_values("conversion") do
    %{
      # 5.0 - 15.0%
      "rate" => (:rand.uniform(100) + 50) / 10,
      "funnel" => %{
        "awareness" => %{
          "visitors" => :rand.uniform(1000) + 500,
          "sources" => %{
            "organic" => :rand.uniform(400),
            "paid" => :rand.uniform(200),
            "social" => %{
              "facebook" => :rand.uniform(150),
              "twitter" => :rand.uniform(100),
              "linkedin" => %{
                "organic" => :rand.uniform(50),
                "sponsored" => :rand.uniform(30)
              }
            }
          }
        },
        "interest" => %{
          "engaged_users" => :rand.uniform(400) + 100,
          "actions" => %{
            "newsletter_signup" => :rand.uniform(80),
            "demo_request" => :rand.uniform(60),
            "pricing_view" => %{
              "basic" => :rand.uniform(120),
              "premium" => :rand.uniform(80),
              "enterprise" => %{
                "contact_sales" => :rand.uniform(25),
                "custom_quote" => :rand.uniform(15)
              }
            }
          }
        },
        "decision" => %{
          "trial_signups" => :rand.uniform(100) + 20,
          "trial_outcomes" => %{
            "converted" => :rand.uniform(30),
            "churned" => :rand.uniform(40),
            "extended" => %{
              "requested_extension" => :rand.uniform(15),
              "upgraded_plan" => :rand.uniform(10)
            }
          }
        }
      }
    }
  end

  defp generate_values("engagement") do
    %{
      # 5-35 minutes
      "session_duration" => :rand.uniform(1800) + 300,
      "page_depth" => %{
        "single_page" => :rand.uniform(200),
        "2_to_5_pages" => %{
          "browsing" => :rand.uniform(300),
          "searching" => :rand.uniform(150),
          "comparing" => %{
            "features" => :rand.uniform(80),
            "pricing" => :rand.uniform(60),
            "reviews" => %{
              "reading" => :rand.uniform(40),
              "writing" => :rand.uniform(15)
            }
          }
        },
        "deep_engagement" => %{
          "6_to_10_pages" => :rand.uniform(100),
          "11_plus_pages" => %{
            "power_users" => :rand.uniform(50),
            "researchers" => :rand.uniform(30),
            "evaluators" => %{
              "technical" => :rand.uniform(20),
              "business" => :rand.uniform(15)
            }
          }
        }
      },
      "interactions" => %{
        "clicks" => %{
          "navigation" => :rand.uniform(800),
          "content" => :rand.uniform(600),
          "cta" => %{
            "primary" => :rand.uniform(120),
            "secondary" => :rand.uniform(80),
            "footer" => %{
              "links" => :rand.uniform(40),
              "social" => :rand.uniform(25)
            }
          }
        }
      }
    }
  end

  defp generate_values("retention") do
    %{
      # 20-100%
      "day_1" => (:rand.uniform(800) + 200) / 10,
      # 10-70%
      "day_7" => (:rand.uniform(600) + 100) / 10,
      # 5-45%
      "day_30" => (:rand.uniform(400) + 50) / 10,
      "cohorts" => %{
        "this_month" => %{
          "new_users" => :rand.uniform(500) + 100,
          "retained" => %{
            "week_1" => :rand.uniform(400),
            "week_2" => :rand.uniform(300),
            "week_4" => %{
              "active" => :rand.uniform(200),
              "engaged" => :rand.uniform(150),
              "paying" => %{
                "new_subscribers" => :rand.uniform(50),
                "upgraded" => :rand.uniform(30)
              }
            }
          }
        },
        "last_month" => %{
          "returning_users" => :rand.uniform(300) + 50,
          "activity_levels" => %{
            "high" => :rand.uniform(100),
            "medium" => :rand.uniform(150),
            "low" => %{
              "at_risk" => :rand.uniform(80),
              "dormant" => :rand.uniform(50)
            }
          }
        }
      }
    }
  end

  defp generate_values("revenue") do
    %{
      # $5000-$55000
      "total" => :rand.uniform(50000) + 5000,
      "recurring" => %{
        "monthly" => :rand.uniform(30000) + 3000,
        "annual" => %{
          "discounted" => :rand.uniform(15000),
          "full_price" => :rand.uniform(10000),
          "enterprise" => %{
            "contracts" => :rand.uniform(5000),
            "custom" => %{
              "implementation" => :rand.uniform(2000),
              "support" => :rand.uniform(1500)
            }
          }
        }
      },
      "one_time" => %{
        "setup_fees" => :rand.uniform(3000),
        "consulting" => %{
          "hours" => :rand.uniform(200),
          "projects" => %{
            "integration" => :rand.uniform(5000),
            "training" => :rand.uniform(2000),
            "customization" => %{
              "ui_changes" => :rand.uniform(1000),
              "workflow" => :rand.uniform(1500)
            }
          }
        }
      },
      "churn_impact" => %{
        "lost_mrr" => :rand.uniform(2000),
        "recovered" => %{
          "win_back" => :rand.uniform(500),
          "downgrades" => %{
            "retained_basic" => :rand.uniform(300),
            "paused" => :rand.uniform(150)
          }
        }
      }
    }
  end

  defp generate_values(_key) do
    # Fallback generic structure with deep nesting
    %{
      "count" => :rand.uniform(100) + 1,
      "value" => :rand.uniform(1000) + 50,
      "categories" => %{
        "primary" => %{
          "type_a" => :rand.uniform(200),
          "type_b" => %{
            "subtype_1" => :rand.uniform(100),
            "subtype_2" => :rand.uniform(75),
            "complex" => %{
              "nested_value" => :rand.uniform(50),
              "deep_metric" => %{
                "level_4" => :rand.uniform(25),
                "level_5" => :rand.uniform(15)
              }
            }
          }
        },
        "secondary" => %{
          "alternative" => :rand.uniform(150),
          "backup" => %{
            "system_a" => :rand.uniform(80),
            "system_b" => :rand.uniform(60)
          }
        }
      }
    }
  end
end
