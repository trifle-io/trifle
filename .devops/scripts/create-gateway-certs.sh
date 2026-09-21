#!/usr/bin/env bash
set -euo pipefail

# Creates a dedicated private CA and separate App/gateway certificates.
# Keep this directory outside the repository. Never overwrite existing keys.
CERT_DIR="${1:?Usage: create-gateway-certs.sh ABSOLUTE_DIRECTORY [gateway DNS name]}"
GATEWAY_DNS="${2:-network-gateway}"
[[ "$CERT_DIR" = /* ]] || { echo 'Certificate directory must be absolute' >&2; exit 1; }
[[ "$GATEWAY_DNS" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo 'Invalid gateway DNS name' >&2; exit 1; }
[[ ! -e "$CERT_DIR" ]] || { echo 'Certificate directory already exists' >&2; exit 1; }
umask 077
mkdir -p "$CERT_DIR"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
  -subj '/CN=Trifle Gateway CA' -keyout "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt"
for role in server client; do
  if [[ "$role" == server ]]; then
    CERT_NAME="$GATEWAY_DNS"
    printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "$GATEWAY_DNS" > "$CERT_DIR/extensions"
  else
    CERT_NAME=trifle-app
    printf 'extendedKeyUsage=clientAuth\n' > "$CERT_DIR/extensions"
  fi
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -subj "/CN=$CERT_NAME" -keyout "$CERT_DIR/$role.key" -out "$CERT_DIR/$role.csr"
  openssl x509 -req -days 365 -in "$CERT_DIR/$role.csr" -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" -CAcreateserial -extfile "$CERT_DIR/extensions" -out "$CERT_DIR/$role.crt"
  rm "$CERT_DIR/$role.csr"
done
rm "$CERT_DIR/extensions"
chmod 0644 "$CERT_DIR/ca.crt" "$CERT_DIR/server.crt" "$CERT_DIR/client.crt" "$CERT_DIR/server.key" "$CERT_DIR/client.key"
# The containing directory remains 0700. Individual file mounts let nonroot
# containers read their own runtime keys without exposing the CA signing key.
echo "Created certificates in $CERT_DIR. Give each runtime read access to only its own key; keep ca.key offline."
