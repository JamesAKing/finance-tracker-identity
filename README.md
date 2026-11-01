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
