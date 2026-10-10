#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/infra/terraform"
OUT="$ROOT/dist"
DOMAIN="${1:-}"
EMAIL="${2:-}"

[[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Uso: $0 dominio.example correo@example.com" >&2; exit 2; }
[[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || { echo "Correo inválido." >&2; exit 2; }
[[ -f "$OUT/backend-deploy.tar.gz" && -f "$OUT/frontend-deploy.tar.gz" ]] || { echo "Ejecuta scripts/build-deployments.sh primero." >&2; exit 1; }

command -v aws >/dev/null 2>&1 || { echo "Instala y configura AWS CLI v2." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Instala jq." >&2; exit 1; }

BUCKET="$(terraform -chdir="$TF_DIR" output -raw artifact_bucket)"
FRONTEND_ID="$(terraform -chdir="$TF_DIR" output -raw frontend_instance_id)"
BACKEND_ID="$(terraform -chdir="$TF_DIR" output -raw backend_instance_id)"
BACKEND_IP="$(terraform -chdir="$TF_DIR" output -raw backend_private_ip)"

aws s3 cp "$OUT/backend-deploy.tar.gz" "s3://$BUCKET/backend/backend-deploy.tar.gz" --sse AES256
aws s3 cp "$OUT/frontend-deploy.tar.gz" "s3://$BUCKET/frontend/frontend-deploy.tar.gz" --sse AES256

quote() { printf "%q" "$1"; }

run_ssm() {
  local instance_id="$1" remote_command="$2" label="$3"
  local parameters command_id status attempt
  parameters="$(jq -cn --arg command "$remote_command" '{commands: [$command]}')"
  command_id="$(aws ssm send-command --instance-ids "$instance_id" --document-name AWS-RunShellScript \
    --comment "$label" --parameters "$parameters" --query 'Command.CommandId' --output text)"
  echo "$label enviado. CommandId=$command_id"
  status="Pending"
  for attempt in $(seq 1 72); do
    status="$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" --query 'Status' --output text 2>/dev/null || echo Pending)"
    case "$status" in
      Success) break ;;
      Failed|TimedOut|Cancelled|Cancelling)
        echo "Error: SSM terminó con estado $status. Detalles:" >&2
        aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" --output json >&2 || true
        return 1
        ;;
    esac
    sleep 5
  done
  if [[ "$status" != "Success" ]]; then
    echo "Tiempo de espera agotado; revisa el comando $command_id en Systems Manager." >&2
    return 1
  fi
  aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" \
    --query 'StandardOutputContent' --output text || true
}

backend_command="set -euo pipefail; install -d -m 0755 /opt/zero-trust; aws s3 cp s3://$BUCKET/backend/backend-deploy.tar.gz /tmp/backend-deploy.tar.gz; tar -xzf /tmp/backend-deploy.tar.gz -C /opt/zero-trust; chmod +x /opt/zero-trust/scripts/install-backend.sh; /opt/zero-trust/scripts/install-backend.sh"
run_ssm "$BACKEND_ID" "$backend_command" "Instalar Backend Zero Trust"

frontend_command="set -euo pipefail; install -d -m 0755 /opt/zero-trust; aws s3 cp s3://$BUCKET/frontend/frontend-deploy.tar.gz /tmp/frontend-deploy.tar.gz; tar -xzf /tmp/frontend-deploy.tar.gz -C /opt/zero-trust; chmod +x /opt/zero-trust/scripts/install-frontend.sh; DOMAIN=$(quote "$DOMAIN") ADMIN_EMAIL=$(quote "$EMAIL") BACKEND_PRIVATE_IP=$(quote "$BACKEND_IP") /opt/zero-trust/scripts/install-frontend.sh"
run_ssm "$FRONTEND_ID" "$frontend_command" "Instalar Frontend, HTTPS y Fail2Ban"

# The S3 objects include the backend TLS private key during transfer. Delete both uploads
# after successful installation; bucket versioning is intentionally disabled for this lab.
aws s3 rm "s3://$BUCKET/backend/backend-deploy.tar.gz"
aws s3 rm "s3://$BUCKET/frontend/frontend-deploy.tar.gz"

echo "Despliegue enviado y completado. Crea el administrador mediante una sesión interactiva de Systems Manager."
