#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/dist"
CERTS="$ROOT/certs/generated"

for file in "$CERTS/ca.crt" "$CERTS/backend.crt" "$CERTS/backend.key"; do
  [[ -f "$file" ]] || { echo "Falta $file. Ejecuta scripts/generate-internal-certs.sh primero." >&2; exit 1; }
done

if ! command -v npm >/dev/null 2>&1; then
  echo "Error: instala Node.js LTS y npm para construir el frontend." >&2
  exit 1
fi
(
  cd "$ROOT/frontend"
  npm install
  npm run build
)

rm -rf "$OUT/staging"
mkdir -p "$OUT/staging/backend" "$OUT/staging/frontend" "$OUT/staging/shared"
# Backend package receives only its application files and backend server private key.
mkdir -p "$OUT/staging/backend/backend" "$OUT/staging/backend/deploy/backend" "$OUT/staging/backend/certs/generated" "$OUT/staging/backend/scripts"
cp -a "$ROOT/backend/app" "$OUT/staging/backend/backend/"
cp "$ROOT/backend/requirements.txt" "$OUT/staging/backend/backend/"
cp "$ROOT/deploy/backend/zero-trust-api.service" "$OUT/staging/backend/deploy/backend/"
cp "$ROOT/scripts/install-backend.sh" "$OUT/staging/backend/scripts/"
cp "$CERTS/backend.crt" "$CERTS/backend.key" "$OUT/staging/backend/certs/generated/"

# Frontend package receives only static files, the public CA certificate, and proxy/security configuration.
mkdir -p "$OUT/staging/frontend/frontend" "$OUT/staging/frontend/deploy/frontend" "$OUT/staging/frontend/certs/generated" "$OUT/staging/frontend/scripts"
cp -a "$ROOT/frontend/dist" "$OUT/staging/frontend/frontend/"
cp -a "$ROOT/deploy/frontend/." "$OUT/staging/frontend/deploy/frontend/"
cp "$ROOT/scripts/install-frontend.sh" "$OUT/staging/frontend/scripts/"
cp "$CERTS/ca.crt" "$OUT/staging/frontend/certs/generated/"

mkdir -p "$OUT"
tar -czf "$OUT/backend-deploy.tar.gz" -C "$OUT/staging/backend" .
tar -czf "$OUT/frontend-deploy.tar.gz" -C "$OUT/staging/frontend" .
rm -rf "$OUT/staging"
chmod 0644 "$OUT/backend-deploy.tar.gz" "$OUT/frontend-deploy.tar.gz"
echo "Paquetes creados:"
echo "  $OUT/backend-deploy.tar.gz"
echo "  $OUT/frontend-deploy.tar.gz"
echo "No se incluye certs/generated/ca.key: mantenla fuera de AWS y de los paquetes."
