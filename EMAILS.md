# Email Provider Configuration Guide

This document explains how to configure outgoing email for Trifle using the Helm chart. The application supports Swoosh adapters, and the deployment surfaces the same knobs through `app.mailer` values. All configuration should be done via `values.yaml` (or an environment-specific override such as `values-production.yaml`).

## Table of Contents

- [General Concepts](#general-concepts)
- [Shared Helm Values](#shared-helm-values)
- [Default Local Adapter](#default-local-adapter)
- [SMTP Adapter](#smtp-adapter)
- [Postmark Adapter](#postmark-adapter)
- [SendGrid Adapter](#sendgrid-adapter)
- [Mailgun Adapter (HTTP API)](#mailgun-adapter-http-api)
- [Mailgun Adapter (SMTP)](#mailgun-adapter-smtp)
- [Sendinblue/Brevo Adapter](#sendinbluebrevo-adapter)
- [Helm Deployment Summary](#helm-deployment-summary)

---

## General Concepts

1. **Adapter**: Swoosh uses adapters to talk to different email providers. The Helm value `app.mailer.adapter` determines which adapter the runtime activates.
2. **From address**: Configure the sender name and email globally in `app.mailer.from`. The runtime converts these into `MAILER_FROM_NAME` and `MAILER_FROM_EMAIL` env vars; Swoosh uses the tuple `{name, email}` as the default `from` value.
3. **API Client (Finch)**: For adapters that call HTTP APIs (Postmark, SendGrid, Mailgun API, Sendinblue/Brevo) the release is already running Finch, so runtime automatically enables the `Swoosh.ApiClient.Finch` client. SMTP and the Local mailbox do not need it.
4. **Secrets**: The Helm chart copies sensitive values into the `{{ include "trifle.fullname" . }}-secret` Secret. Environment variables in the Deployment, migration job, and init-user job reference those secrets. You do **not** need to craft Kubernetes secrets manually unless you want to override the chart behavior.
5. **Runtime config**: `config/runtime.exs` reads the environment variables emitted by Helm and translates them into Swoosh configuration. You shouldn’t need to edit the file for normal deployments—set values in Helm and redeploy.

---

## Shared Helm Values

In every example you will see the following structure:

```yaml
app:
  mailer:
    adapter: "..."            # which provider
    from:
      name: "Trifle"          # displayed sender name
      email: "no-reply@example.com"
    ...                        # provider-specific fields
```

Any fields under `smtp`, `postmark`, `sendgrid`, `mailgun`, or `sendinblue` only apply when the corresponding adapter is selected. Blank strings (`""`) are treated as “unset”.

### Available adapters

| Adapter value | Intended provider | Notes |
|---------------|------------------|-------|
| `local`       | Swoosh.Local     | Development only—messages land in `/dev/mailbox`. |
| `smtp`        | Any SMTP server  | Classic username/password credentials. |
| `postmark`    | Postmark API     | Requires API token, uses Finch. |
| `sendgrid`    | SendGrid API     | Requires API key, uses Finch. |
| `mailgun`     | Mailgun HTTP API | Requires private API key & domain; optional EU base URL. |
| `sendinblue` / `brevo` | Brevo (Sendinblue) API | Same API key works; adapter is marked deprecated upstream but still functional. |

If you enter any other value, runtime raises an error at boot.

---

## Default Local Adapter

Out of the box `app.mailer.adapter` is set to `"local"`. This means:

- Helm deploys without additional configuration.
- Runtime config sets `Swoosh.Adapters.Local`, which writes messages to the local mailbox.
- In a Phoenix dev profile you can inspect messages at `/dev/mailbox`.
- No external credentials are needed.

Use this mode for development and integration testing.

---

## SMTP Adapter

Choose the SMTP adapter when you want to talk to an SMTP relay directly (e.g., SendGrid SMTP, Mailgun SMTP, an internal Postfix, AWS SES SMTP endpoint).

```yaml
app:
  mailer:
    adapter: "smtp"
    from:
      name: "Trifle"
      email: "no-reply@example.com"
    smtp:
      relay: "smtp.example.com"      # required
      username: "smtp-user"          # optional if relay supports anonymous auth
      password: "smtp-password"      # required when username is set
      port: 587                       # default if omitted
      auth: "if_available"           # allowed values: "always", "never", "if_available"
      tls: "if_available"            # same options as auth
      ssl: false                      # set to true to force SSL (usually port 465)
      retries: 2                      # optional retry count
```

**Notes:**
- `relay` must be set or the release fails to boot.
- `username` / `password` are stored in the Helm-managed secret and loaded into `SMTP_USERNAME` / `SMTP_PASSWORD` env vars.
- `auth`, `tls`, and `ssl` are string flags in Helm but runtime converts them to the atoms/booleans Swoosh expects.
- If you leave `auth` / `tls` blank they default to `:if_available`. Setting `ssl` to `true` or `false` controls the `ssl` option directly.

---

## Postmark Adapter

Use Postmark’s HTTP API. No SMTP settings required.

```yaml
app:
  mailer:
    adapter: "postmark"
    from:
      name: "Trifle"
      email: "no-reply@example.com"
    postmark:
      apiKey: "POSTMARK_SERVER_TOKEN"
```

**Where to get values:**
- Log in to Postmark → `Server → API Tokens` → copy the *Server API Token* (not the account token).
- Paste it into `postmark.apiKey` in your values file. Helm base64-encodes it into the secret. Runtime config sets `adapter: Swoosh.Adapters.Postmark` and ensures Finch is enabled.

---

## SendGrid Adapter

Use SendGrid’s v3 API with an API key.

```yaml
app:
  mailer:
    adapter: "sendgrid"
    from:
      name: "Trifle"
      email: "no-reply@example.com"
    sendgrid:
      apiKey: "SENDGRID_API_KEY"
```

**Where to get values:**
- In SendGrid go to `Settings → API Keys` and create a key (the “Full Access” mail send scope is sufficient). Paste that key into `sendgrid.apiKey`.
- Helm stores it in the secret; runtime config uses `Swoosh.Adapters.Sendgrid` and Finch.

---

## Mailgun Adapter (HTTP API)

This is the recommended Mailgun configuration since it uses the private API key rather than SMTP credentials.

```yaml
app:
  mailer:
    adapter: "mailgun"
    from:
      name: "Trifle"
      email: "no-reply@yourdomain.com"
    mailgun:
      apiKey: "MAILGUN_PRIVATE_API_KEY"
      domain: "mg.yourdomain.com"
      baseUrl: "https://api.eu.mailgun.net/v3"  # optional; use for EU region
```

**Steps to get the values:**
1. In Mailgun, open `Settings → API Security → API Keys`.
2. Create a new key with the **Sending** role (limited scope) or reuse an existing private key.
3. Copy the private API key and place it in `mailgun.apiKey`. Remember the value is shown only once when generated.
4. Set `mailgun.domain` to the Mailgun-sending domain you verified (e.g., `mg.yourdomain.com`).
5. If your Mailgun account is on the EU infrastructure, add `mailgun.baseUrl: "https://api.eu.mailgun.net/v3"`. Leave it blank for the default US endpoint.

Runtime sets `adapter: Swoosh.Adapters.Mailgun`, merges the optional base URL, and enables Finch.

---

## Mailgun Adapter (SMTP)

If you prefer SMTP credentials instead of the HTTP API, configure the SMTP adapter with Mailgun’s SMTP endpoint.

```yaml
app:
  mailer:
    adapter: "smtp"
    from:
      name: "Trifle"
      email: "no-reply@yourdomain.com"
    smtp:
      relay: "smtp.mailgun.org"
      username: "postmaster@mg.yourdomain.com"
      password: "MAILGUN_SMTP_PASSWORD"
      port: 587
      auth: "always"
      tls: "always"
      ssl: false
```

**Where to get username/password:**
- From the Mailgun dashboard, open your domain → `Domain Settings → SMTP credentials`.
- Use the `postmaster@your-domain` account (or create a custom SMTP user). Copy the generated password.
- Paste the username/password into the Helm values. Helm places them in the release secret and runtime config uses Swoosh’s SMTP adapter.

Choose either the HTTP API option **or** the SMTP option, not both.

---

## Sendinblue/Brevo Adapter

Brevo (formerly Sendinblue) exposes transactional email via their API. Swoosh’s `Sendinblue` adapter still works; runtime aliases it for good measure.

```yaml
app:
  mailer:
    adapter: "sendinblue"  # or "brevo"; both map to the same adapter
    from:
      name: "Trifle"
      email: "no-reply@yourdomain.com"
    sendinblue:
      apiKey: "BREVO_TRANSACTIONAL_API_KEY"
```

**How to obtain the API key:**
1. In Brevo’s dashboard navigate to `SMTP & API → Transactions → API keys`.
2. Generate a **Transactional** API key (gives send access only) and copy it.
3. Paste the key into `sendinblue.apiKey`.

Runtime treats `adapter: "sendinblue"` or `"brevo"` the same way, configuring `Swoosh.Adapters.Sendinblue` and enabling Finch.

---

## Helm Deployment Summary

1. **Edit `values.yaml` or supply `--set` overrides** with the desired adapter and credentials.
2. Helm writes the sensitive fields into the release secret under keys such as `smtp-username`, `postmark-api-key`, etc.
3. The Deployment, migration job, and initial-user job all receive the same environment variable set (`MAILER_*`, `SMTP_*`, provider API keys) so the release behaves consistently in every phase.
4. `config/runtime.exs` evaluates those env vars at boot and configures Swoosh accordingly.
5. Verify email delivery after deployment:
   - For API adapters: check the provider console for recent deliveries.
   - For SMTP adapters: check relay logs or send a test invitation from the UI.
   - For `local`: open `/dev/mailbox` in your browser.

Remember to keep API keys and SMTP passwords secure. Avoid committing actual values—override them via `values-production.yaml`, `helm upgrade --set`, or Kubernetes secrets if you prefer to manage credentials separately.

