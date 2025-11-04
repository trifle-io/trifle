# Google Single Sign-On for Trifle

Google OAuth can be enabled for Trifle so that members sign in with their Google Workspace accounts. This guide covers the steps to create the Google Cloud credentials, configure deployment secrets, and set up organization-level domain rules.

## 1. Create a Google OAuth Client

1. Sign in to the [Google Cloud Console](https://console.cloud.google.com/apis/credentials).
2. Select your project (or create a new one) and navigate to **APIs & Services → Credentials**.
3. Click **Create Credentials → OAuth client ID** and choose **Web application**.
4. Name the client (e.g., `Trifle OAuth`).
5. Add the redirect URI:
   - Default: `https://your-trifle-host/auth/google/callback`
   - Local development: `http://localhost:4000/auth/google/callback`
   - You can override this later with the `GOOGLE_OAUTH_REDIRECT_URI` environment variable.
6. Save the client to obtain the **Client ID** and **Client Secret**.
7. (Optional) Configure the OAuth consent screen if this is the first OAuth client in the project.

## 2. Configure Deployment Secrets

Provide the Google credentials to Trifle via environment variables (Helm values in Kubernetes deployments):

```bash
GOOGLE_OAUTH_CLIENT_ID=<your-client-id>
GOOGLE_OAUTH_CLIENT_SECRET=<your-client-secret>
# Optional: override the redirect URI if it differs from the default
GOOGLE_OAUTH_REDIRECT_URI=https://your-trifle-host/auth/google/callback
```

For the Helm chart, set the following values (for example in `values-production.yaml`):

```yaml
app:
  googleOAuth:
    clientId: "<your-client-id>"
    clientSecret: "<your-client-secret>"
    redirectUri: "https://your-trifle-host/auth/google/callback"
```

`clientSecret` is stored in the release secret and mounted as an environment variable automatically.

For Helm deployments, add the values under your chart’s configuration, for example:

```yaml
app:
  googleOAuth:
    clientId: "<your-client-id>"
    clientSecret: "<your-client-secret>"
    redirectUri: "https://your-trifle-host/auth/google/callback"
```

After updating the configuration, redeploy the release so the Trifle application picks up the new variables.

## 3. Allow Organization Domains

Once the deployment knows about the Google credentials, organization administrators can configure allowed domains under **Organization → Delivery Options → Google Single Sign-On**:

- Enable Google sign-in for the organization.
- Enter one domain per line (e.g., `example.com`). Domains are enforced globally, so a domain can belong to only one organization at a time.
- Decide whether new users from those domains should be auto-provisioned into the organization.

Only domains listed here will be accepted for new Google sign-ins. Existing members can continue to log in even if their domain is later removed.

## 4. Login Experience

- The login screen shows a “Sign in with Google” button whenever Google OAuth credentials are present.
- Users with matching domains are created automatically (and confirmed) when auto-provisioning is enabled.
- If auto-provisioning is disabled, users receive an informative message and must request access via an invitation.

## 5. Managed vs. Self-Hosted Modes

- **Managed/SaaS deployments** typically ship with Google credentials provisioned as part of the platform. Customers only manage domain lists in the UI.
- **Self-hosted deployments** must provide their own Google OAuth client (steps 1 and 2 above). All organizations in the deployment share the same OAuth credentials.

## Troubleshooting

- **Missing credentials**: the Google SSO card in the Organization settings will indicate that OAuth credentials are not configured.
- **Invalid domain**: ensure the domain is entered without protocol or path (`example.com`) and is not already claimed by another organization.
- **Callback errors**: verify that the redirect URI in Google Cloud matches the Trifle URL (consider HTTPS vs. HTTP and trailing slashes).
