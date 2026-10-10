#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ROOT="$ROOT/backend"
CERT_ROOT="$ROOT/certs/generated"
SERVICE_FILE="$ROOT/deploy/backend/zero-trust-api.service"

for file in "$APP_ROOT/app/main.py" "$APP_ROOT/requirements.txt" "$CERT_ROOT/backend.crt" "$CERT_ROOT/backend.key" "$SERVICE_FILE"; do
  [[ -f "$file" ]] || { echo "Falta archivo requerido: $file" >&2; exit 1; }
done

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv python3-pip ca-certificates openssl

if ! id -u ztapi >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/zero-trust-api --no-create-home --shell /usr/sbin/nologin --user-group ztapi
fi
install -d -o root -g ztapi -m 0750 /opt/zero-trust/backend
install -d -o root -g root -m 0755 /opt/zero-trust/venv
install -d -o ztapi -g ztapi -m 0750 /var/lib/zero-trust-api
install -d -o root -g ztapi -m 0750 /etc/zero-trust-api
cp -a "$APP_ROOT/." /opt/zero-trust/backend/
chown -R root:ztapi /opt/zero-trust/backend
find /opt/zero-trust/backend -type d -exec chmod 0750 {} \;
find /opt/zero-trust/backend -type f -exec chmod 0640 {} \;

if [[ ! -x /opt/zero-trust/venv/bin/python ]]; then
  python3 -m venv /opt/zero-trust/venv
fi
/opt/zero-trust/venv/bin/pip install --upgrade pip
/opt/zero-trust/venv/bin/pip install -r /opt/zero-trust/backend/requirements.txt

install -o root -g ztapi -m 0640 "$CERT_ROOT/backend.crt" /etc/zero-trust-api/backend.crt
install -o root -g ztapi -m 0640 "$CERT_ROOT/backend.key" /etc/zero-trust-api/backend.key

if [[ ! -f /etc/zero-trust-api.env ]]; then
  JWT_SECRET="$(openssl rand -hex 48)"
  umask 027
  cat > /etc/zero-trust-api.env <<ENV
ENVIRONMENT=production
DATABASE_URL=sqlite:////var/lib/zero-trust-api/app.db
JWT_SECRET_KEY=$JWT_SECRET
JWT_ISSUER=zero-trust-lab
JWT_AUDIENCE=zero-trust-frontend
JWT_ACCESS_TOKEN_MINUTES=15
FRONTEND_PROXY_IP=10.10.1.10
ENV
  chown root:ztapi /etc/zero-trust-api.env
  chmod 0640 /etc/zero-trust-api.env
fi

install -o root -g root -m 0644 "$SERVICE_FILE" /etc/systemd/system/zero-trust-api.service
systemctl daemon-reload
systemctl enable --now zero-trust-api
systemctl restart zero-trust-api
sleep 2
systemctl --no-pager --full status zero-trust-api
printf '\nBackend instalado. Siguiente paso: crear el usuario administrador a través de SSM:\n'
printf "sudo -u ztapi bash -lc 'set -a; source /etc/zero-trust-api.env; set +a; cd /opt/zero-trust/backend; /opt/zero-trust/venv/bin/python -m app.create_user --username admin --role admin'\n"
