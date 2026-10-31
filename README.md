# Finance Tracker Identity Service

Keycloak and Postgres providing authentication for the Finance Tracker app. Local development only.

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

## Realm

The `finance-tracker` realm is imported from `keycloak/realm.json` on first start.

- Client: `finance-tracker-api` (confidential client used by the service; redirect URI `${WEB_ORIGIN}/api/auth/callback`)
- Issuer: `http://localhost:8080/realms/finance-tracker`
- JWKS: `http://localhost:8080/realms/finance-tracker/protocol/openid-connect/certs`

To apply changes to `realm.json`, reset the stack (this deletes all Keycloak data):

```
docker compose down -v && docker compose up -d
```
