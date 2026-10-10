# Zero Trust Lab AWS — Frontend + Backend

Proyecto académico para demostrar una aplicación web distribuida en **dos VPC independientes**, con conectividad privada mediante VPC Peering, Frontend React servido por Nginx, API FastAPI con autenticación JWT, TLS tanto externo como interno, autorización por recurso, encabezados de seguridad y bloqueo temporal de IP mediante Fail2Ban.

> **Importante:** este repositorio contiene código e infraestructura como código; no crea recursos en AWS por sí solo. Los recursos se crean cuando tú ejecutas Terraform con una cuenta y permisos de AWS. No contiene contraseñas de administrador ni llaves de certificados generadas para tu despliegue.

## Componentes

- `frontend/`: React + Vite; login y Dashboard con gestión de recursos de demostración. El JWT se guarda solo en memoria JavaScript y se pierde al recargar la página, para evitar persistirlo en `localStorage`.
- `backend/`: FastAPI, JWT HS256 de 15 minutos, hash Argon2id con `argon2-cffi`, SQLAlchemy, SQLite local para laboratorio, endpoints protegidos y tests automatizados.
- `infra/terraform/`: dos VPC, subred pública Frontend, subred pública técnica para NAT del Backend, subred privada Backend, Internet Gateways, NAT Gateway, rutas, VPC Peering, EC2 Ubuntu 24.04, perfiles IAM de alcance limitado, S3 privado y Security Groups.
- `deploy/`: servicio `systemd`, plantillas Nginx/TLS, encabezados CSP/HSTS y filtro/jail de Fail2Ban.
- `scripts/`: creación de una CA interna, empaquetado aislado Frontend/Backend, instalación y despliegue usando AWS Systems Manager (SSM), sin SSH público.
- `docs/IMPLEMENTACION_PASO_A_PASO.md`: guía de despliegue detallada.
- `docs/ENTREGA_Y_EVIDENCIAS.md`: pruebas y evidencias sugeridas para la evaluación.
- `docs/Guia_Implementacion_AWS_Zero_Trust.docx`: guía complementaria de la conversación.
- `diagrams/arquitectura.mmd`: diagrama editable Mermaid.

## Arquitectura resumida

```text
Navegador -- HTTPS:443 --> EIP/DNS --> Nginx + React (10.10.1.10)
                                         |
                                         | VPC Peering + TLS verificado :8443
                                         v
                              FastAPI / JWT (10.20.2.10)
                              subred privada, sin IP pública
                                         |
                                         v
                              SQLite (laboratorio)
```

El Backend solo acepta TCP/8443 desde la IP privada /32 del Frontend. No se permite TCP/22 público; la administración y la ejecución de scripts se hacen mediante Systems Manager. El NAT Gateway está en una subred pública técnica del Backend VPC; la instancia de API permanece en la subred privada.

## Inicio rápido

Lee primero `docs/IMPLEMENTACION_PASO_A_PASO.md`. El orden normal de despliegue es:

1. Instalar AWS CLI, Terraform, Node.js, OpenSSL y `jq`; configurar credenciales de AWS.
2. Copiar `infra/terraform/terraform.tfvars.example` a `infra/terraform/terraform.tfvars` y ajustar región, dominio y correo.
3. Ejecutar `terraform init`, `terraform validate`, `terraform plan` y `terraform apply` desde `infra/terraform/`.
4. Crear el certificado TLS interno con `scripts/generate-internal-certs.sh "$(terraform -chdir=infra/terraform output -raw backend_private_ip)"`.
5. Asegurar que el DNS A del dominio apunte a `frontend_public_ip` y que ya se haya propagado.
6. Ejecutar `scripts/build-deployments.sh` y luego `scripts/deploy-via-ssm.sh dominio.example correo@example.com`.
7. Abrir una sesión interactiva SSM en la instancia Backend para crear el usuario administrador con `python -m app.create_user`.
8. Ejecutar las pruebas y tomar las capturas enumeradas en `docs/ENTREGA_Y_EVIDENCIAS.md`.

No ejecutes el despliegue con `domain_name` de ejemplo. Certbot necesita un dominio tuyo, con DNS público correcto y TCP/80 accesible durante la emisión/renovación.

## Desarrollo local

Requisitos: Python 3.11 o superior, Node.js 22 LTS recomendado y npm.

Terminal 1 — API:

```bash
cd backend
python -m venv .venv
# Linux/macOS/WSL:
source .venv/bin/activate
pip install -r requirements.txt
export ENVIRONMENT=development
export JWT_SECRET_KEY="$(openssl rand -hex 32)"
export DATABASE_URL="sqlite:///./dev.db"
python -m app.create_user --username admin --role admin
uvicorn app.main:app --reload --port 8000
```

Terminal 2 — interfaz:

```bash
cd frontend
npm install
npm run dev
```

Abre `http://127.0.0.1:5173`. El proxy de desarrollo de Vite reenvía `/api` a `http://127.0.0.1:8000`. Para los tests, desde `backend/`, ejecuta:

```bash
ENVIRONMENT=test JWT_SECRET_KEY='solo-para-tests-no-usar-en-produccion-0123456789' pytest -q
```

## Seguridad y alcance

- Las claves JWT y contraseñas no se almacenan en el código fuente. El instalador crea un secreto aleatorio en `/etc/zero-trust-api.env` con permisos restringidos.
- La CA privada (`certs/generated/ca.key`) se conserva localmente y nunca se sube. El paquete Frontend recibe solo el certificado público de esa CA.
- El paquete de despliegue Backend contiene temporalmente la llave privada del certificado interno, pero solo puede leerse desde el prefijo S3 `backend/`; el rol Frontend solo tiene permiso de lectura sobre `frontend/*`. El script de despliegue borra ambos objetos S3 cuando ambos despliegues terminan bien.
- La carpeta `dist/`, `certs/generated/` y archivos Terraform de estado están excluidos por `.gitignore`; no los añadas a un repositorio público.
- SQLite es una elección didáctica. En una aplicación real, migra a RDS/Aurora privado, implementa copias de seguridad, gestión/rotación de secretos, monitorización, WAF y un proceso de parcheo.
- El filtro Fail2Ban actúa en el proxy público: observa solo el código HTTP y la ruta de login, no contraseñas, cuerpos de peticiones ni tokens.

## Costos

AWS puede cobrar por EC2, almacenamiento EBS, IPv4 pública, NAT Gateway, transferencia, Route 53 y otros recursos. En particular, el NAT Gateway tiene cargos por hora y procesamiento aunque la API reciba poco tráfico. Establece un presupuesto/alerta antes de `terraform apply` y ejecuta `terraform destroy` al terminar la práctica. Revisa primero el plan de Terraform y la página de precios de tu región; los créditos/free tier no están garantizados.

## Recursos oficiales

- [AWS VPC Peering y rutas](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-routing.html)
- [AWS Systems Manager prerequisites](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-prerequisites.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Certbot](https://certbot.eff.org/)
- [FastAPI security](https://fastapi.tiangolo.com/tutorial/security/)
