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

  defp assert_env(overrides, expected) do
    for template <- @templates do
      {rendered, status} =
        System.cmd(
          System.get_env("HELM_BIN", "helm"),
          ["template", "observability-test", @chart, "--show-only", "templates/#{template}"] ++
            overrides,
          stderr_to_stdout: true
        )

      assert status == 0, rendered
      assert length(Regex.scan(~r/- name: TRIFLE_OBSERVABILITY_ENABLED\s/, rendered)) == 1

      assert Regex.run(
               ~r/- name: TRIFLE_OBSERVABILITY_ENABLED\s+value: "([^"]*)"/,
               rendered,
               capture: :all_but_first
             ) == [expected]
    end
  end
end
