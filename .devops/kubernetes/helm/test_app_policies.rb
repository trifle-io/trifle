# Run inside the app container with HELM_BIN set or Helm on PATH:
# ruby .devops/kubernetes/helm/test_app_policies.rb
require "minitest/autorun"
require "yaml"
require "open3"

# Egress NetworkPolicy and history retention settings of the app Deployment.
class AppPoliciesChartTest < Minitest::Test
  CHART = File.expand_path("trifle", __dir__)
  HELM = ENV.fetch("HELM_BIN", "helm")
  EGRESS = "trifle-egress"

  def test_no_egress_policy_unless_enabled
    refute render.any? { |doc| doc["kind"] == "NetworkPolicy" && doc.dig("metadata", "name") == EGRESS }
  end

  def test_egress_policy_selects_the_app_and_blocks_private_ranges
    docs = render("--set", "networkPolicy.egress.enabled=true")
    policy = resource(docs, "NetworkPolicy", EGRESS)
    app = resource(docs, "Deployment", "trifle")

    assert_equal app.dig("spec", "selector", "matchLabels"), policy.dig("spec", "podSelector", "matchLabels")
    assert_equal ["Egress"], policy.dig("spec", "policyTypes")

    rules = policy.dig("spec", "egress")
    internet = rules.map { |rule| rule.dig("to", 0, "ipBlock") }.compact.find { |block| block["cidr"] == "0.0.0.0/0" }
    %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10 127.0.0.0/8].each do |cidr|
      assert_includes internet["except"], cidr
    end

    dns = rules.find { |rule| (rule["ports"] || []).any? { |port| port["port"] == 53 } }
    assert_equal %w[TCP UDP], dns["ports"].map { |port| port["protocol"] }.sort

    release = rules.find { |rule| rule.dig("to", 0, "podSelector") }
    assert_equal({"app.kubernetes.io/instance" => "trifle"}, release.dig("to", 0, "podSelector", "matchLabels"))
  end

  def test_egress_policy_allows_listed_namespaces_and_addresses_only
    docs = render(
      "--set", "networkPolicy.egress.enabled=true",
      "--set", "networkPolicy.egress.allowNamespaces={mongo}",
      "--set", "networkPolicy.egress.allowCidrs[0].cidr=10.20.0.15/32",
      "--set", "networkPolicy.egress.allowCidrs[0].ports={5432}",
      "--set", "networkPolicy.egress.allowCidrs[1].cidr=10.30.0.0/24"
    )
    rules = resource(docs, "NetworkPolicy", EGRESS).dig("spec", "egress")

    namespaces = rules.map { |rule| rule.dig("to", 0, "namespaceSelector", "matchLabels", "kubernetes.io/metadata.name") }.compact
    assert_equal ["mongo"], namespaces

    postgres = rules.find { |rule| rule.dig("to", 0, "ipBlock", "cidr") == "10.20.0.15/32" }
    assert_equal [{"protocol" => "TCP", "port" => 5432}], postgres["ports"]

    any_port = rules.find { |rule| rule.dig("to", 0, "ipBlock", "cidr") == "10.30.0.0/24" }
    refute any_port.key?("ports")
  end

  def test_node_local_dns_resolvers_are_allowed_on_port_53_only
    docs = render("--set", "networkPolicy.egress.enabled=true", "--set", "networkPolicy.egress.dnsCidrs={169.254.20.10/32}")
    rules = resource(docs, "NetworkPolicy", EGRESS).dig("spec", "egress")

    node_local = rules.find { |rule| rule.dig("to", 0, "ipBlock", "cidr") == "169.254.20.10/32" }
    assert_equal [53, 53], node_local["ports"].map { |port| port["port"] }

    # Without the setting there is no such rule.
    plain = resource(render("--set", "networkPolicy.egress.enabled=true"), "NetworkPolicy", EGRESS).dig("spec", "egress")
    refute plain.any? { |rule| rule.dig("to", 0, "ipBlock", "cidr").to_s.start_with?("169.254.20.10") }
  end

  def test_retention_defaults_and_overrides
    assert_equal({"MONITOR_EXECUTION_RETENTION_DAYS" => "30", "OBAN_JOB_RETENTION_DAYS" => "7"}, retention_env(render))

    custom = render("--set", "app.retention.monitorExecutionDays=90", "--set", "app.retention.obanJobDays=2")
    assert_equal({"MONITOR_EXECUTION_RETENTION_DAYS" => "90", "OBAN_JOB_RETENTION_DAYS" => "2"}, retention_env(custom))

    # An explicit app.env entry wins and is not rendered twice.
    explicit = render("--set-string", "app.env.OBAN_JOB_RETENTION_DAYS=1")
    names = app_env(explicit).map { |entry| entry["name"] }
    assert_equal 1, names.count("OBAN_JOB_RETENTION_DAYS")
    assert_equal "1", retention_env(explicit)["OBAN_JOB_RETENTION_DAYS"]
  end

  private

  def app_env(docs)
    resource(docs, "Deployment", "trifle").dig("spec", "template", "spec", "containers").first["env"]
  end

  def retention_env(docs)
    app_env(docs).select { |entry| entry["name"].end_with?("_RETENTION_DAYS") && !entry["name"].start_with?("TRIFLE_") }
                 .to_h { |entry| [entry["name"], entry["value"]] }
  end

  def render(*args)
    output, error, status = Open3.capture3(HELM, "template", "trifle", CHART, *args)
    assert status.success?, error
    YAML.load_stream(output).compact
  end

  def resource(docs, kind, name)
    docs.find { |doc| doc["kind"] == kind && doc.dig("metadata", "name") == name } || flunk("Missing #{kind}/#{name}")
  end
end
