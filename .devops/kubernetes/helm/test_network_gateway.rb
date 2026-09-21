# Run inside the app container with HELM_BIN set or Helm on PATH:
# ruby .devops/kubernetes/helm/test_network_gateway.rb
require "minitest/autorun"
require "yaml"
require "json"
require "openssl"
require "base64"
require "open3"
require "socket"
require "tmpdir"
require "timeout"

class NetworkGatewayChartTest < Minitest::Test
  CHART = File.expand_path("trifle", __dir__)
  SAAS = ["-f", File.join(CHART, "values-saas.yaml")].freeze
  NAME = "trifle-network-gateway"

  def test_self_hosted_defaults_create_no_gateway_resources_or_configuration
    docs = render
    refute docs.any? { |doc| doc.dig("metadata", "name").include?("network-gateway") }
    pod = resource(docs, "Deployment", "trifle").dig("spec", "template", "spec")
    refute pod["containers"].first["env"].any? { |env| env["name"].start_with?("TRIFLE_GATEWAY_") }
    refute (pod["volumes"] || []).any? { |volume| volume["name"] == "gateway-certs" }
  end

  def test_saas_has_one_gateway_independent_of_app_replicas_and_autoscaling
    [["--set", "replicaCount=6"], ["--set", "autoscaling.enabled=true"]].each do |overrides|
      docs = render(*SAAS, *overrides)
      gateway = resource(docs, "Deployment", NAME)
      assert_equal 1, gateway.dig("spec", "replicas")
      assert_equal "Recreate", gateway.dig("spec", "strategy", "type")
      refute docs.any? { |doc| doc["kind"] == "HorizontalPodAutoscaler" && doc.dig("spec", "scaleTargetRef", "name") == NAME }

      service = resource(docs, "Service", NAME)
      assert_equal "ClusterIP", service.dig("spec", "type")
      assert_equal gateway.dig("spec", "template", "metadata", "labels"), service.dig("spec", "selector")
      app = resource(docs, "Deployment", "trifle")
      env = app.dig("spec", "template", "spec", "containers").first["env"]
      assert_equal "https://#{NAME}:8443", env.find { |entry| entry["name"] == "TRIFLE_GATEWAY_URL" }["value"]
      policy = resource(docs, "NetworkPolicy", NAME)
      assert_equal app.dig("spec", "selector", "matchLabels"), policy.dig("spec", "ingress", 0, "from", 0, "podSelector", "matchLabels")
      assert_equal [{"protocol" => "TCP", "port" => 8443}], policy.dig("spec", "ingress", 0, "ports")
    end
  end

  def test_self_hosted_can_opt_in_and_saas_can_explicitly_disable
    assert resource(render("--set", "networkGateway.enabled=true"), "Deployment", NAME)
    refute render(*SAAS, "--set", "networkGateway.enabled=false").any? { |doc| doc.dig("metadata", "name") == NAME }
  end

  def test_generated_credentials_are_valid_and_separate_between_runtimes
    docs = render(*SAAS)
    state = resource(docs, "Secret", "#{NAME}-state")
    assert_equal 32, Base64.strict_decode64(decode(state, "state-key")).bytesize
    server = resource(docs, "Secret", "#{NAME}-server")
    client = resource(docs, "Secret", "#{NAME}-client")
    assert_equal %w[ca.crt server.crt server.key], server["data"].keys.sort
    assert_equal %w[ca.crt client.crt client.key], client["data"].keys.sort
    assert_equal decode(server, "ca.crt"), decode(client, "ca.crt")
    refute_equal decode(server, "server.key"), decode(client, "client.key")
    ca = OpenSSL::X509::Certificate.new(decode(server, "ca.crt"))
    store = OpenSSL::X509::Store.new
    store.add_cert(ca)
    {server => "server", client => "client"}.each do |secret, role|
      cert = OpenSSL::X509::Certificate.new(decode(secret, "#{role}.crt"))
      key = OpenSSL::PKey.read(decode(secret, "#{role}.key"))
      assert store.verify(cert), store.error_string
      assert cert.check_private_key(key)
      assert_operator cert.not_after, :>, Time.now + 364 * 86_400
    end
    cert = OpenSSL::X509::Certificate.new(decode(server, "server.crt"))
    [NAME, "#{NAME}.default", "#{NAME}.default.svc"].each do |hostname|
      assert OpenSSL::SSL.verify_certificate_identity(cert, hostname)
    end

    [state, server, client, resource(docs, "PersistentVolumeClaim", NAME)].each do |doc|
      assert_equal "keep", doc.dig("metadata", "annotations", "helm.sh/resource-policy")
    end
    gateway_pod = resource(docs, "Deployment", NAME).dig("spec", "template", "spec")
    app_pod = resource(docs, "Deployment", "trifle").dig("spec", "template", "spec")
    assert_equal "#{NAME}-server", gateway_pod["volumes"].find { |v| v["name"] == "certs" }.dig("secret", "secretName")
    assert_equal "#{NAME}-client", app_pod["volumes"].find { |v| v["name"] == "gateway-certs" }.dig("secret", "secretName")
    refute gateway_pod["automountServiceAccountToken"]
  end

  def test_existing_secrets_are_reused_byte_for_byte_on_upgrade
    original = render(*SAAS)
    with_api(original) do |config|
      upgraded = render(*SAAS, "--is-upgrade", "--dry-run=server", "--kubeconfig", config)
      %w[state server client].each do |role|
        assert_equal resource(original, "Secret", "#{NAME}-#{role}")["data"], resource(upgraded, "Secret", "#{NAME}-#{role}")["data"]
      end
    end
  end

  def test_lost_credentials_are_never_regenerated_over_existing_state
    original = render(*SAAS)
    ["#{NAME}-state", "#{NAME}-server", "#{NAME}-client", :all].each do |missing|
      remaining = original.reject { |doc| doc["kind"] == "Secret" && (missing == :all || doc.dig("metadata", "name") == missing) }
      with_api(remaining) do |config|
        assert_render_error("restore the original gateway Secrets", *SAAS, "--is-upgrade", "--dry-run=server", "--kubeconfig", config)
      end
    end
  end

  def test_incomplete_existing_secret_fails_instead_of_replacing_credentials
    original = render(*SAAS)
    resource(original, "Secret", "#{NAME}-server")["data"].delete("server.key")
    with_api(original) do |config|
      assert_render_error("Gateway server Secret is missing server.key", *SAAS, "--dry-run=server", "--kubeconfig", config)
    end
  end

  def test_external_secret_references_skip_generation_and_partial_configuration_fails
    docs = render(*SAAS, "--set", "networkGateway.stateKeySecret=external-state,networkGateway.serverTLSSecret=external-server,networkGateway.clientTLSSecret=external-client")
    refute docs.any? { |doc| doc["kind"] == "Secret" && doc.dig("metadata", "name").start_with?(NAME) }
    pod = resource(docs, "Deployment", NAME).dig("spec", "template", "spec")
    assert_equal "external-server", pod["volumes"].find { |v| v["name"] == "certs" }.dig("secret", "secretName")
    assert_equal "external-state", pod["containers"].first["env"].find { |v| v["name"] == "TRIFLE_GATEWAY_STATE_KEY" }.dig("valueFrom", "secretKeyRef", "name")
    assert_render_error("Set all three networkGateway Secret names", *SAAS, "--set", "networkGateway.stateKeySecret=external-state")
  end

  def test_gateway_supports_registry_credentials_and_its_own_scheduling
    docs = render(*SAAS, "--set", "imagePullSecrets[0].name=registry,networkGateway.nodeSelector.pool=apps,networkGateway.tolerations[0].key=gateway,networkGateway.tolerations[0].operator=Exists,networkGateway.image.tag=test-release")
    pod = resource(docs, "Deployment", NAME).dig("spec", "template", "spec")
    assert_equal [{"name" => "registry"}], pod["imagePullSecrets"]
    assert_equal({"pool" => "apps"}, pod["nodeSelector"])
    assert_equal [{"key" => "gateway", "operator" => "Exists"}], pod["tolerations"]
    assert_equal "trifle/network-gateway:test-release", pod["containers"].first["image"]
  end

  def test_long_release_names_keep_gateway_and_secret_names_valid
    docs = render(*SAAS, "--set", "fullnameOverride=#{'x' * 63}")
    docs.select { |doc| doc.dig("metadata", "name").include?("network-gateway") }.each do |doc|
      assert_operator doc.dig("metadata", "name").length, :<=, 63
    end
  end

  private

  def command(*args)
    Timeout.timeout(30) { Open3.capture3(ENV.fetch("HELM_BIN", "helm"), "template", "trifle", CHART, *args) }
  end

  def render(*args)
    output, error, status = command(*args)
    assert status.success?, error
    YAML.load_stream(output).compact
  end

  def assert_render_error(message, *args)
    _output, error, status = command(*args)
    refute status.success?
    assert_includes error, message
  end

  def resource(docs, kind, name)
    docs.find { |doc| doc["kind"] == kind && doc.dig("metadata", "name") == name } || flunk("Missing #{kind}/#{name}")
  end

  def decode(secret, key)
    Base64.strict_decode64(secret.fetch("data").fetch(key))
  end

  # A local, read-only Kubernetes API fixture exercises Helm's real lookup path.
  # No cluster credentials, mutations, or dependency on a running cluster.
  def with_api(docs)
    server = TCPServer.new("127.0.0.1", 0)
    worker = Thread.new do
      loop do
        socket = server.accept
        begin
          request = socket.gets
          while (header = socket.gets) && header != "\r\n"; end
          path = request.split[1].split("?").first
          body = api_response(path, docs)
          code = body ? "200 OK" : "404 Not Found"
          body ||= {"apiVersion" => "v1", "kind" => "Status", "status" => "Failure", "reason" => "NotFound", "code" => 404}
          json = JSON.generate(body)
          socket.write("HTTP/1.1 #{code}\r\nContent-Type: application/json\r\nContent-Length: #{json.bytesize}\r\nConnection: close\r\n\r\n#{json}")
        ensure
          socket.close
        end
      end
    end
    Dir.mktmpdir("trifle-helm-api") do |dir|
      config = File.join(dir, "config")
      File.write(config, {"apiVersion" => "v1", "kind" => "Config", "current-context" => "fixture", "clusters" => [{"name" => "fixture", "cluster" => {"server" => "http://127.0.0.1:#{server.addr[1]}"}}], "contexts" => [{"name" => "fixture", "context" => {"cluster" => "fixture", "user" => "fixture"}}], "users" => [{"name" => "fixture", "user" => {}}]}.to_yaml, perm: 0o600)
      yield config
    end
  ensure
    worker&.kill
    worker&.join
    server&.close
  end

  def api_response(path, docs)
    case path
    when "/version"
      {"major" => "1", "minor" => "31", "gitVersion" => "v1.31.0"}
    when "/api"
      {"apiVersion" => "v1", "kind" => "APIVersions", "versions" => ["v1"]}
    when "/apis"
      {"apiVersion" => "v1", "kind" => "APIGroupList", "groups" => []}
    when "/api/v1"
      {"apiVersion" => "v1", "kind" => "APIResourceList", "groupVersion" => "v1", "resources" => {"secrets" => "Secret", "persistentvolumeclaims" => "PersistentVolumeClaim"}.map { |name, kind| {"name" => name, "kind" => kind, "namespaced" => true, "verbs" => ["get", "list"]} }}
    when %r{\A/api/v1/namespaces/default/(secrets|persistentvolumeclaims)/([^/]+)\z}
      kind = Regexp.last_match(1) == "secrets" ? "Secret" : "PersistentVolumeClaim"
      name = Regexp.last_match(2)
      docs.find { |doc| doc["kind"] == kind && doc.dig("metadata", "name") == name }
    end
  end
end
