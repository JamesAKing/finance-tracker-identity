#!/usr/bin/env bash
set -euo pipefail

secret_vars=(KC_DB_PASSWORD KC_BOOTSTRAP_ADMIN_PASSWORD API_CLIENT_SECRET SMTP_PASSWORD)

for name in "${secret_vars[@]}"; do
  file_var="${name}_FILE"
  path="${!file_var:-}"
  [[ -z "$path" ]] && continue

  if [[ -n "${!name:-}" ]]; then
    echo "Set $name or $file_var, not both" >&2
    exit 1
  fi

  export "$name=$(<"$path")"
done

exec /opt/keycloak/bin/kc.sh "$@"
