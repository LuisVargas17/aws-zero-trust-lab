#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/frontend/dist"
NGINX_ROOT="$ROOT/deploy/frontend/nginx"
F2B_ROOT="$ROOT/deploy/frontend/fail2ban"
CA_FILE="$ROOT/certs/generated/ca.crt"
DOMAIN="${DOMAIN:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
BACKEND_PRIVATE_IP="${BACKEND_PRIVATE_IP:-10.20.2.10}"

[[ -d "$DIST" ]] || { echo "Falta el build frontend/dist. Ejecuta npm run build antes de empaquetar." >&2; exit 1; }
[[ -f "$CA_FILE" ]] || { echo "Falta certs/generated/ca.crt; genera el certificado interno antes." >&2; exit 1; }
[[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "DOMAIN inválido. Usa un dominio DNS, sin protocolo ni ruta." >&2; exit 2; }
[[ "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || { echo "ADMIN_EMAIL inválido." >&2; exit 2; }
[[ "$BACKEND_PRIVATE_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "BACKEND_PRIVATE_IP inválido." >&2; exit 2; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx fail2ban nftables ca-certificates

install -d -o root -g root -m 0755 /var/www/zero-trust /var/www/certbot
cp -a "$DIST/." /var/www/zero-trust/
chown -R root:root /var/www/zero-trust
find /var/www/zero-trust -type d -exec chmod 0755 {} \;
find /var/www/zero-trust -type f -exec chmod 0644 {} \;
install -o root -g root -m 0644 "$CA_FILE" /etc/ssl/certs/zero-trust-internal-ca.pem
install -o root -g root -m 0644 "$NGINX_ROOT/proxy-params.conf" /etc/nginx/snippets/zero-trust-proxy-params.conf
install -o root -g root -m 0644 "$NGINX_ROOT/auth-log.conf" /etc/nginx/conf.d/zero-trust-auth-log.conf

sed -e "s|__DOMAIN__|$DOMAIN|g" "$NGINX_ROOT/http-site.conf.template" > /etc/nginx/sites-available/zero-trust
ln -sfn /etc/nginx/sites-available/zero-trust /etc/nginx/sites-enabled/zero-trust
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# Antes de esta fase, el registro DNS A del dominio debe apuntar a la EIP del Frontend y propagarse.
certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" \
  --email "$ADMIN_EMAIL" --agree-tos --no-eff-email --non-interactive

sed -e "s|__DOMAIN__|$DOMAIN|g" -e "s|__BACKEND_PRIVATE_IP__|$BACKEND_PRIVATE_IP|g" \
  "$NGINX_ROOT/site.conf.template" > /etc/nginx/sites-available/zero-trust
nginx -t
systemctl reload nginx

install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx <<'HOOK'
#!/usr/bin/env bash
set -e
systemctl reload nginx
HOOK
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx

install -d -m 0755 /etc/fail2ban/filter.d
install -o root -g root -m 0644 "$F2B_ROOT/zero-trust-auth.conf" /etc/fail2ban/filter.d/zero-trust-auth.conf
install -o root -g root -m 0644 "$F2B_ROOT/jail.local" /etc/fail2ban/jail.d/zero-trust-auth.local
# Create the log before starting Fail2Ban; Nginx will append failed login responses.
touch /var/log/nginx/zero_trust_auth.log
chown www-data:adm /var/log/nginx/zero_trust_auth.log
chmod 0640 /var/log/nginx/zero_trust_auth.log
systemctl enable --now fail2ban
systemctl restart fail2ban

printf '\nFrontend desplegado. Verifica:\n'
printf '  nginx -t\n  certbot certificates\n  fail2ban-client status zero-trust-auth\n  curl -I https://%s\n' "$DOMAIN"
