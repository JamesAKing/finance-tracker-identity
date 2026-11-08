# Finance Tracker Identity Service

Keycloak and Postgres providing authentication for the Finance Tracker app.

- `docker-compose.yml` runs Keycloak for local development (`start-dev`).
- `Dockerfile` builds the production Keycloak image (see [Production image](#production-image)).

## Setup

1. Create your env file and set the passwords:

   ```
   cp .env.example .env
   ```

2. Start the services:

   ```
   docker compose up -d
   ```

3. Open `http://localhost:8080` and log in as `admin` with `KC_ADMIN_PASSWORD`.

Emails Keycloak sends (e.g. verification) are caught by Mailpit: `http://localhost:8025`.

## Shared network

This stack creates the `finance-tracker` Docker network and puts Keycloak on it, so the
service and client containers can reach it at `http://keycloak:8080`. Start identity
before the other repos' containers; they expect the network to exist.

`KC_HOSTNAME` is pinned to `http://localhost:8080`, so the issuer is always
`http://localhost:8080/realms/finance-tracker`, whether a request arrives from the browser
or from another container. Without it, a container calling `keycloak:8080` would get a
different issuer and token validation would fail.

## Realm

The `finance-tracker` realm is imported from `keycloak/realm.json` on first start.

- Client: `finance-tracker-api` (confidential client used by the service; redirect URI `${WEB_ORIGIN}/api/auth/callback`)
- Issuer: `http://localhost:8080/realms/finance-tracker`
- JWKS: `http://localhost:8080/realms/finance-tracker/protocol/openid-connect/certs`

To apply changes to `realm.json`, reset the stack (this deletes all Keycloak data):

```
docker compose down -v && docker compose up -d
```

### Realm settings

- Registration, email login, password reset and email verification are on.
- Password policy: at least 12 characters, at most 128, and not the same as the username or
  email.
- Brute force protection: after 10 failed logins, the account is locked for a short time. The
  wait grows by 60 seconds each time, up to 15 minutes. Locks are never permanent.
- Values in `${...}` come from environment variables when the realm is imported:
  `API_CLIENT_SECRET`, `WEB_ORIGIN` and the `SMTP_*` settings. `docker-compose.yml` sets the
  `SMTP_*` values to Mailpit for local use.

## Production image

`Dockerfile` builds an optimised Keycloak image for production. It is built once in CI and
pushed to GHCR as `ghcr.io/jamesaking/finance-tracker-identity:<commit SHA>`, for amd64 and
arm64.

Built into the image:

- Postgres as the database.
- Health checks on. The management port (9000) serves `/auth/health/ready`. The container's
  `HEALTHCHECK` calls it. The image has no `curl` or `wget`, so the check uses bash.
- Keycloak is served under `/auth`, so it can share one hostname with the app.
- `KC_HTTP_ENABLED=true` and `KC_PROXY_HEADERS=xforwarded`: Keycloak speaks plain HTTP to the
  HTTPS proxy in front of it, and trusts the proxy's `X-Forwarded-*` headers.
- The realm in `keycloak/realm.json`. It is imported on first start. If the realm already
  exists, it is left alone.
- Runs as user 1000, not root.

Set at runtime:

| Variable                         | Value                                                        |
| -------------------------------- | ------------------------------------------------------------ |
| `KC_HOSTNAME`                    | The public URL, with `/auth`, for example `https://app.example.com/auth` |
| `KC_DB_URL`                      | `jdbc:postgresql://<host>:5432/<db>`                         |
| `KC_DB_USERNAME`                 | Database user                                                |
| `KC_DB_PASSWORD`                 | Database password (secret)                                   |
| `KC_BOOTSTRAP_ADMIN_USERNAME`    | First admin user, created on first start                     |
| `KC_BOOTSTRAP_ADMIN_PASSWORD`    | Its password (secret)                                        |
| `API_CLIENT_SECRET`              | The service's client secret (secret)                         |
| `WEB_ORIGIN`                     | The app's origin, for example `https://app.example.com`     |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`, `SMTP_AUTH`, `SMTP_USER`, `SMTP_PASSWORD` (secret), `SMTP_SSL`, `SMTP_STARTTLS` | Email server settings |

Each secret can also come from a file: set `<NAME>_FILE` to its path, for example
`KC_DB_PASSWORD_FILE=/run/secrets/keycloak_db_password`. This is how Docker secrets reach
Keycloak. `keycloak/entrypoint.sh` reads the files, then starts Keycloak. Set the variable or
the `_FILE` variable, not both.

The issuer always comes from `KC_HOSTNAME`. Request headers can't change it.

### CI

`.github/workflows/ci.yml` runs on every PR and on `master`:

- lints the Dockerfile with hadolint, and both scripts with shellcheck;
- checks that `keycloak/realm.json` is valid JSON;
- builds the image and runs `scripts/smoke-test.sh`. The script starts Postgres and Keycloak,
  waits until Keycloak is healthy, and checks that:
  - the issuer is correct;
  - the realm's password policy, brute force protection and SMTP settings are applied;
  - the redirect URI and client secret came from the environment and the secret file.

`.github/workflows/images.yml` builds the image on every PR and scans it with Trivy. It fails
on high or critical vulnerabilities that have a fix. On `master`, it also pushes the image.

All GitHub Actions are pinned to a commit SHA. Dependabot (`.github/dependabot.yml`) opens weekly
PRs to update the Keycloak, Postgres and Mailpit images, and the actions.

### Known vulnerability exceptions

`.trivyignore` lists vulnerabilities that the scan skips. Each has an end date (`exp:`). After
that date, the scan fails again, so the exception has to be checked.

| CVE              | Why it is skipped                                                                 | Until      |
| ---------------- | --------------------------------------------------------------------------------- | ---------- |
| CVE-2026-102554  | Denial of service in `guava` 33.6.0, which Keycloak bundles. Keycloak 26.8.1 and 26.8.2 both ship it, so it can't be fixed here. Remove it when Keycloak updates `guava` to 33.7.2 or later | 2026-12-08 |
