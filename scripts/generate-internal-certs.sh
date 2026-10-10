#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/certs/generated"
BACKEND_IP="${1:-10.20.2.10}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: instala OpenSSL antes de continuar." >&2
  exit 1
fi
if [[ ! "$BACKEND_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Uso: $0 [IP_PRIVADA_BACKEND]" >&2
  exit 2
fi
if [[ -e "$OUT/ca.key" || -e "$OUT/backend.key" ]]; then
  echo "Ya existen llaves en $OUT. No se sobrescribirán automáticamente." >&2
  echo "Respáldalas de forma segura o elimina el directorio solo si entiendes las consecuencias." >&2
  exit 3
fi

umask 077
mkdir -p "$OUT"
openssl genrsa -out "$OUT/ca.key" 4096
openssl req -x509 -new -key "$OUT/ca.key" -sha256 -days 3650 \
  -subj "/CN=Zero Trust Lab Internal CA" -out "$OUT/ca.crt"
openssl genrsa -out "$OUT/backend.key" 3072
openssl req -new -key "$OUT/backend.key" \
  -subj "/CN=backend.internal" -out "$OUT/backend.csr"
cat > "$OUT/backend.ext" <<EXT
basicConstraints=CA:FALSE
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:backend.internal,IP:$BACKEND_IP
EXT
openssl x509 -req -in "$OUT/backend.csr" -CA "$OUT/ca.crt" -CAkey "$OUT/ca.key" \
  -CAcreateserial -out "$OUT/backend.crt" -days 825 -sha256 -extfile "$OUT/backend.ext"
chmod 600 "$OUT/ca.key" "$OUT/backend.key"
chmod 644 "$OUT/ca.crt" "$OUT/backend.crt"
rm -f "$OUT/backend.csr" "$OUT/backend.ext" "$OUT/ca.srl"
echo "Certificado interno creado para backend.internal y $BACKEND_IP."
echo "IMPORTANTE: certs/generated/ca.key no se sube a AWS ni se empaqueta; guárdala fuera del servidor como llave privada de CA."
