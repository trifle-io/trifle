# Run inside the app container with Helm available on PATH (or set HELM_BIN):
# elixir .devops/kubernetes/helm/test_observability.exs
ExUnit.start()

defmodule Trifle.Helm.ObservabilityTest do
  use ExUnit.Case, async: true

  @chart Path.expand("trifle", __DIR__)
  @templates ~w(deployment.yaml job-migrate.yaml job-init-user.yaml)

  test "internal observability is enabled by default in the app and release jobs" do
    assert_env([], "true")
  end

  test "explicit false disables internal observability in every workload" do
    assert_env(["--set", "app.observability.enabled=false"], "false")
  end

  test "app.env can disable observability without duplicate environment entries" do
    assert_env(["--set-string", "app.env.TRIFLE_OBSERVABILITY_ENABLED=false"], "false")
  end

  test "app.env takes precedence over the structured value in either direction" do
    assert_env(
      [
        "--set",
        "app.observability.enabled=false",
        "--set-string",
        "app.env.TRIFLE_OBSERVABILITY_ENABLED=true"
      ],
      "true"
    )
  end

  test "older values files without an observability section retain the default" do
    assert_env(["--set", "app.observability=null"], "true")
  end

  test "internal metric defaults and overrides are rendered in every workload" do
    assert_observability_setting([], "TRIFLE_OBSERVABILITY_GRANULARITIES", "1m,1h,1d,1mo")
    assert_observability_setting([], "TRIFLE_OBSERVABILITY_DEFAULT_TIMEFRAME", "6h")
    assert_observability_setting([], "TRIFLE_OBSERVABILITY_DEFAULT_GRANULARITY", "1m")
    assert_observability_setting([], "TRIFLE_OBSERVABILITY_TIME_ZONE", "UTC")

    overrides = [
      "--set-string",
      "app.env.TRIFLE_OBSERVABILITY_GRANULARITIES=5m\\,6h\\,1d",
      "--set-string",
      "app.env.TRIFLE_OBSERVABILITY_DEFAULT_TIMEFRAME=24h",
      "--set-string",
      "app.env.TRIFLE_OBSERVABILITY_DEFAULT_GRANULARITY=6h",
      "--set-string",
      "app.env.TRIFLE_OBSERVABILITY_TIME_ZONE=Asia/Dubai"
    ]

    assert_observability_setting(
      overrides,
      "TRIFLE_OBSERVABILITY_GRANULARITIES",
      "5m,6h,1d"
    )

    assert_observability_setting(
      overrides,
      "TRIFLE_OBSERVABILITY_DEFAULT_TIMEFRAME",
      "24h"
    )

    assert_observability_setting(
      overrides,
      "TRIFLE_OBSERVABILITY_DEFAULT_GRANULARITY",
      "6h"
    )

    assert_observability_setting(overrides, "TRIFLE_OBSERVABILITY_TIME_ZONE", "Asia/Dubai")
  end

  test "dedicated MongoDB and S3 settings are passed to every workload" do
    overrides = [
      "--set-string",
      "app.observability.mongodbUrl=mongodb://user:password@mongo.example:27017/trifle_observability",
      "--set-string",
      "app.observability.indexBackend=mongo",
      "--set-string",
      "app.traces.storageBackend=s3",
      "--set-string",
      "app.traces.s3.endpoint=https://object.example",
      "--set-string",
      "app.traces.s3.buckets[0]=traces-a",
      "--set-string",
      "app.traces.s3.buckets[1]=traces-b",
      "--set-string",
      "app.traces.s3.accessKeyId=access",
      "--set-string",
      "app.traces.s3.secretAccessKey=secret"
    ]

    for template <- @templates do
      rendered = render(template, overrides)

      for variable <- ~w(TRIFLE_OBSERVABILITY_MONGODB_URL TRIFLE_OBSERVABILITY_INDEX_BACKEND
                          TRIFLE_TRACES_STORAGE_BACKEND TRIFLE_TRACES_S3_ENDPOINT
                          TRIFLE_TRACES_S3_BUCKETS TRIFLE_TRACES_S3_ACCESS_KEY_ID
                          TRIFLE_TRACES_S3_SECRET_ACCESS_KEY) do
        assert length(Regex.scan(~r/- name: #{variable}\s/, rendered)) == 1
      end

      assert rendered =~ ~s(value: "traces-a,traces-b")
      assert rendered =~ "key: observability-mongodb-url"
      assert rendered =~ "key: traces-s3-access-key-id"
      assert rendered =~ "key: traces-s3-secret-access-key"
      refute rendered =~ "key: sqlite-object-store-access-key-id"
      refute rendered =~ "key: sqlite-object-store-secret-access-key"
    end

    secret = render("secret.yaml", overrides)
    assert secret =~ "observability-mongodb-url:"
    assert secret =~ "traces-s3-access-key-id:"
    assert secret =~ "traces-s3-secret-access-key:"
  end

  test "dedicated observability Secrets can supply MongoDB and S3 credentials" do
    overrides = [
      "--set-string",
      "app.observability.indexBackend=mongo",
      "--set-string",
      "app.observability.mongodbUrlSecretRef.name=observability-secret",
      "--set-string",
      "app.observability.mongodbUrlSecretRef.key=mongo",
      "--set-string",
      "app.traces.storageBackend=s3",
      "--set-string",
      "app.traces.s3.credentialsSecretRef.name=observability-secret",
      "--set-string",
      "app.traces.s3.credentialsSecretRef.accessKeyIdKey=access",
      "--set-string",
      "app.traces.s3.credentialsSecretRef.secretAccessKeyKey=secret"
    ]

    for template <- @templates do
      rendered = render(template, overrides)

      assert rendered =~ ~r/name: "observability-secret"\s+key: "mongo"/
      assert rendered =~ ~r/name: "observability-secret"\s+key: "access"/
      assert rendered =~ ~r/name: "observability-secret"\s+key: "secret"/
    end
  end

  defp assert_env(overrides, expected) do
    for template <- @templates do
      rendered = render(template, overrides)
      assert length(Regex.scan(~r/- name: TRIFLE_OBSERVABILITY_ENABLED\s/, rendered)) == 1

      assert Regex.run(
               ~r/- name: TRIFLE_OBSERVABILITY_ENABLED\s+value: "([^"]*)"/,
               rendered,
               capture: :all_but_first
             ) == [expected]
    end
  end

  defp assert_observability_setting(overrides, variable, expected) do
    for template <- @templates do
      rendered = render(template, overrides)
      assert length(Regex.scan(~r/- name: #{variable}\s/, rendered)) == 1

      assert Regex.run(
               ~r/- name: #{variable}\s+value: "([^"]*)"/,
               rendered,
               capture: :all_but_first
             ) == [expected]
    end
  end

  defp render(template, overrides) do
    {rendered, status} =
      System.cmd(
        System.get_env("HELM_BIN", "helm"),
        ["template", "observability-test", @chart, "--show-only", "templates/#{template}"] ++
          overrides,
        stderr_to_stdout: true
      )

    assert status == 0, rendered
    rendered
  end
end
