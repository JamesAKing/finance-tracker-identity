#!/usr/bin/env bash
set -euo pipefail

image="${1:?Usage: scripts/smoke-test.sh <image>}"
network="keycloak-smoke-test"
base_url="http://localhost:18080/auth"
secrets_dir="$(mktemp -d)"

cleanup() {
  docker rm -f smoke-keycloak smoke-db >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$secrets_dir"
}
trap cleanup EXIT

printf 'db-password' >"$secrets_dir/db"
printf 'admin-password' >"$secrets_dir/admin"
printf 'client-secret' >"$secrets_dir/client"
chmod 755 "$secrets_dir"
chmod 644 "$secrets_dir"/*

docker network create "$network" >/dev/null
docker run -d --name smoke-db --network "$network" \
  -e POSTGRES_DB=keycloak -e POSTGRES_USER=keycloak -e POSTGRES_PASSWORD=db-password \
  postgres:17-alpine >/dev/null

docker run -d --name smoke-keycloak --network "$network" -p 18080:8080 \
  -v "$secrets_dir:/run/secrets:ro" \
  -e KC_HOSTNAME="$base_url" \
  -e KC_DB_URL=jdbc:postgresql://smoke-db:5432/keycloak \
  -e KC_DB_USERNAME=keycloak \
  -e KC_DB_PASSWORD_FILE=/run/secrets/db \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD_FILE=/run/secrets/admin \
  -e API_CLIENT_SECRET_FILE=/run/secrets/client \
  -e WEB_ORIGIN=https://app.example.com \
  -e SMTP_HOST=mail.example.com -e SMTP_PORT=587 -e SMTP_FROM=no-reply@example.com \
  -e SMTP_AUTH=false -e SMTP_USER= -e SMTP_PASSWORD= -e SMTP_SSL=false -e SMTP_STARTTLS=true \
  "$image" >/dev/null

status=""
for _ in $(seq 1 60); do
  status="$(docker inspect -f '{{.State.Health.Status}}' smoke-keycloak)"
  [[ "$status" == "healthy" ]] && break
  sleep 3
done
if [[ "$status" != "healthy" ]]; then
  docker logs smoke-keycloak
  echo "Keycloak did not become healthy" >&2
  exit 1
fi

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

issuer="$(curl -fsS "$base_url/realms/finance-tracker/.well-known/openid-configuration" | jq -r .issuer)"
[[ "$issuer" == "$base_url/realms/finance-tracker" ]] || fail "issuer is $issuer"

token="$(curl -fsS -d grant_type=password -d client_id=admin-cli -d username=admin -d password=admin-password \
  "$base_url/realms/master/protocol/openid-connect/token" | jq -r .access_token)"
admin_get() { curl -fsS -H "Authorization: Bearer $token" "$base_url/admin/realms/finance-tracker$1"; }

realm="$(admin_get "")"
[[ "$(jq -r .passwordPolicy <<<"$realm")" == "length(12) and maxLength(128) and notUsername and notEmail" ]] ||
  fail "password policy not applied"
[[ "$(jq -r .bruteForceProtected <<<"$realm")" == "true" ]] || fail "brute force protection off"
[[ "$(jq -r .smtpServer.host <<<"$realm")" == "mail.example.com" ]] || fail "SMTP host not set from env"

client="$(admin_get "/clients?clientId=finance-tracker-api" | jq '.[0]')"
[[ "$(jq -r '.redirectUris[0]' <<<"$client")" == "https://app.example.com/api/auth/callback" ]] ||
  fail "redirect URI not set from WEB_ORIGIN"
client_id="$(jq -r .id <<<"$client")"
[[ "$(admin_get "/clients/$client_id/client-secret" | jq -r .value)" == "client-secret" ]] ||
  fail "client secret not read from file"

echo "Smoke test passed"
