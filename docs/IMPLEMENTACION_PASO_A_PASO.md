# Guía de implementación paso a paso

## 0. Qué vas a desplegar y qué no hace automáticamente esta guía

Vas a desplegar una aplicación web dividida en dos VPC independientes. La VPC Frontend expone Nginx por HTTPS y entrega los archivos estáticos de React. Nginx reenvía `/api/` por la conexión privada VPC Peering y TLS verificado a FastAPI. La API valida un JWT en cada ruta protegida y restringe los registros según identidad/rol. Fail2Ban detecta respuestas `401` repetidas en el endpoint de login y bloquea temporalmente la IP en el host Frontend.

Terraform crea la infraestructura base; los scripts posteriores instalan las aplicaciones. No se crea nada mientras solo lees o extraes el proyecto. Nunca guardes el secreto JWT ni contraseñas en `terraform.tfvars`, en Git, ni en capturas visibles.

## 1. Requisitos y preparación

### 1.1 Herramientas locales

Instala y verifica las herramientas:

```bash
aws --version
terraform version
node --version
npm --version
openssl version
jq --version
```

Se recomienda AWS CLI v2, Terraform 1.7 o superior, Node.js 22 LTS, OpenSSL y `jq`. Los scripts Bash están pensados para Linux, macOS o WSL en Windows. En PowerShell nativo, ejecuta los scripts mediante WSL o adapta los comandos manualmente.

### 1.2 Credenciales AWS

Configura credenciales con el mecanismo permitido por tu institución. AWS IAM Identity Center/SSO es preferible a crear claves permanentes:

```bash
aws configure sso
aws sso login --profile nombre-del-perfil
export AWS_PROFILE=nombre-del-perfil
aws sts get-caller-identity
```

La última orden debe mostrar el ID de cuenta esperado. No compartas ni captures claves de acceso.

Los permisos necesarios son amplios a nivel de laboratorio porque Terraform crea VPC, rutas, peering, NAT Gateway, EC2, IAM roles/instance profiles, Security Groups, EIP y S3. Se necesita `iam:PassRole` para asociar los roles EC2, más permisos de Systems Manager y escritura de paquetes S3. Utiliza una cuenta/sandbox de práctica y no añadas permisos de administrador a la aplicación.

### 1.3 Presupuesto y recursos con costo

Antes de continuar, configura en AWS Billing un presupuesto y alertas. EC2, EBS, IPv4 pública, NAT Gateway, transferencia de datos y DNS pueden generar cargos. El NAT Gateway es especialmente importante: es un servicio horario que cuesta dinero aunque no despliegues tráfico real. Los tipos `t3.micro` son solo valores de laboratorio y no garantizan gratuidad.

## 2. Revisar la configuración Terraform

Desde la carpeta raíz del proyecto:

```bash
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
```

Abre `infra/terraform/terraform.tfvars` y define, como mínimo:

```hcl
aws_region             = "us-east-1"
project_name           = "zt-lab"
frontend_instance_type = "t3.micro"
backend_instance_type  = "t3.micro"
domain_name            = "app.tu-dominio.com"
admin_email            = "tu-correo@example.com"
```

Cambia dominio y correo por valores tuyos. No escribas el protocolo (`https://`) ni una ruta en `domain_name`. Si el dominio usa Route 53, puedes definir `route53_zone_id` con el ID de la zona hospedada pública; Terraform crea un registro A. Si el DNS se administra en otro proveedor, deja vacío ese valor y configura su registro A manualmente más adelante.

Los rangos predeterminados son:

| Elemento | Rango/IP |
|---|---|
| VPC Frontend | `10.10.0.0/16` |
| Subred pública Frontend | `10.10.1.0/24` |
| EC2 Frontend | `10.10.1.10` |
| VPC Backend | `10.20.0.0/16` |
| Subred pública técnica (NAT) | `10.20.1.0/24` |
| Subred privada Backend | `10.20.2.0/24` |
| EC2 Backend | `10.20.2.10` |

Los CIDR de ambas VPC no deben solaparse entre sí ni con redes conectadas por VPN/peering. Si cambias la IP privada del Backend, genera después el certificado interno usando la IP devuelta por Terraform. Si cambias la IP del Frontend, la regla `/32` de Security Group y la IP de proxy de Uvicorn también deben ajustarse; lo más simple para esta práctica es conservar los valores predeterminados.

## 3. Crear infraestructura

```bash
cd infra/terraform
terraform fmt -recursive
terraform init
terraform validate
terraform plan -out=tfplan
```

Inspecciona el plan: debe mostrar **dos VPC**, la conexión VPC Peering, tres subredes, dos instancias EC2, un NAT Gateway, Internet Gateways, EIP, IAM roles, Security Groups y un bucket S3 privado. Si el plan muestra recursos en otra región/cuenta, detente y corrige `AWS_PROFILE`/`aws_region`.

Aplica únicamente cuando entiendas el plan:

```bash
terraform apply tfplan
```

Guarda los valores de salida:

```bash
terraform output
terraform output -raw frontend_public_ip
terraform output -raw frontend_instance_id
terraform output -raw backend_instance_id
terraform output -raw backend_private_ip
terraform output -raw artifact_bucket
terraform output -raw vpc_peering_id
```

La instancia Backend no debe tener IPv4 pública. Solo la EC2 Frontend tendrá una EIP expuesta para tráfico web. El Backend recibe tráfico de API por TCP/8443 desde la IP `10.10.1.10/32`, a través del peering. No se abre puerto 22; administra los dos servidores con SSM.

### 3.1 Verificaciones de red en la consola

En **VPC → Your VPCs**, toma nota de los IDs de ambas VPC. En **Peering connections**, verifica que el peering esté `Active`. En **Route tables**, comprueba:

- Frontend: ruta local `10.10.0.0/16`, default `0.0.0.0/0` a Internet Gateway y `10.20.0.0/16` al peering.
- Backend privada: ruta local `10.20.0.0/16`, `10.10.0.0/16` al peering y `0.0.0.0/0` al NAT Gateway.
- Backend pública técnica: ruta `0.0.0.0/0` al Internet Gateway; aquí reside el NAT, no la aplicación.

El peering solo conecta las redes; las rutas en ambos lados y las reglas de seguridad son igualmente necesarias. La ruta más específica al peering prevalece para tráfico Frontend/Backend, no se manda esa comunicación por el NAT.

## 4. Confirmar que SSM funciona

Espera a que finalice el User Data de ambas instancias. En Systems Manager → Fleet Manager / Managed nodes deben aparecer las EC2 como `Online`. También puedes ejecutar:

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$(terraform -chdir=infra/terraform output -raw frontend_instance_id),$(terraform -chdir=infra/terraform output -raw backend_instance_id)" \
  --query 'InstanceInformationList[*].[InstanceId,PingStatus,PlatformName]' --output table
```

Si no aparecen `Online`, revisa EC2 → Instance → System log, los eventos de User Data, las rutas de salida, IAM instance profile y conectividad HTTPS de la instancia con Systems Manager. No abras el puerto 22 como atajo.

## 5. Generar certificado TLS interno

El navegador tendrá un certificado público de Let's Encrypt. Nginx necesita además confiar en una CA interna para comprobar el certificado de la API privada. En la raíz del proyecto ejecuta:

```bash
./scripts/generate-internal-certs.sh "$(terraform -chdir=infra/terraform output -raw backend_private_ip)"
```

Se generan archivos en `certs/generated/`:

- `ca.key`: clave privada de la CA. **No se distribuye, no se copia a AWS y no se incluye en el paquete**. Consérvala protegida en el equipo que la generó.
- `ca.crt`: certificado público de CA, se instala únicamente como raíz de confianza en el proxy Frontend.
- `backend.key` y `backend.crt`: clave privada y certificado de servidor de la API privada. La clave solo se instala en el Backend.

Comprueba el certificado:

```bash
openssl x509 -in certs/generated/backend.crt -noout -subject -issuer -dates -ext subjectAltName
```

El SAN debe incluir `DNS:backend.internal` y la IP privada real del Backend. El certificado se firma con la CA interna recién creada.

## 6. DNS público y Certbot

Obtén la EIP pública:

```bash
terraform -chdir=infra/terraform output -raw frontend_public_ip
```

Crea un registro DNS A para `app.tu-dominio.com` que apunte a esa IP. Si usaste Route 53 con `route53_zone_id`, el registro lo habrá creado Terraform. Si DNS es externo, créalo manualmente. Comprueba resolución:

```bash
dig +short app.tu-dominio.com
```

El resultado debe incluir la EIP del Frontend. Espera la propagación antes de pedir el certificado. Certbot necesita resolver el dominio correctamente y recibir el desafío HTTP en TCP/80. No es suficiente usar una IP literal ni un nombre ficticio.

## 7. Construir y empaquetar la aplicación

Desde la raíz del proyecto:

```bash
./scripts/build-deployments.sh
```

El script instala las dependencias Node del Frontend y crea el build estático, después genera dos paquetes:

- `dist/frontend-deploy.tar.gz`: React compilado, Nginx, la CA pública y Fail2Ban.
- `dist/backend-deploy.tar.gz`: código FastAPI, dependencias, service unit, certificado interno y llave privada de ese certificado.

Los paquetes son temporales de despliegue. El script no incluye la llave privada de la CA (`ca.key`). El instalador usa dos prefijos S3 y dos roles de instancia, por lo que el rol Frontend solo puede leer `frontend/*` y no tiene permiso de descarga sobre `backend/*`. Durante el despliegue el archivo Backend se almacena temporalmente en el bucket S3 privado con cifrado del lado del servidor; al completar ambas instalaciones correctamente, el script borra los dos objetos. No publiques los paquetes ni subas `dist/` a Git.

## 8. Desplegar mediante Systems Manager

Antes de desplegar, asegúrate de que:

1. Ambas instancias aparecen `Online` en SSM.
2. El dominio ya apunta a la EIP Frontend.
3. El puerto TCP/80 del Frontend es accesible para el desafío ACME.
4. Generaste la CA/certificado y construiste los paquetes.
5. Tu identidad local puede subir objetos al bucket privado y ejecutar `ssm:SendCommand`/consultar invocaciones.

Ejecuta:

```bash
./scripts/deploy-via-ssm.sh app.tu-dominio.com tu-correo@example.com
```

El script sube los archivos al bucket, instala primero el Backend y luego el Frontend. El instalador Backend prepara un entorno virtual Python, instala FastAPI/SQLAlchemy/PyJWT/pwdlib, configura `/etc/zero-trust-api.env`, instala el certificado interno y arranca `zero-trust-api.service`. El secreto de firma JWT se genera con OpenSSL en la instancia; no se muestra en la salida.

El instalador Frontend configura Nginx, publica el build React, solicita el certificado público a Let's Encrypt, valida el certificado interno del Backend antes de hacer proxy y activa Fail2Ban. Si Certbot falla por DNS, detente, corrige el registro y ejecuta de nuevo el proceso Frontend desde SSM después de revisar el estado; no deshabilites la verificación TLS interna para “hacer que funcione”.

Si necesitas inspeccionar el comando remoto, ve a **Systems Manager → Run Command → Command history → Command ID**; revisa `StandardOutputContent` y `StandardErrorContent`. No pegues secretos en notas/capturas.

## 9. Crear el usuario administrador

El usuario no se crea por defecto y no existe una contraseña genérica. Inicia una sesión interactiva sobre la instancia Backend:

```bash
BACKEND_ID="$(terraform -chdir=infra/terraform output -raw backend_instance_id)"
aws ssm start-session --target "$BACKEND_ID"
```

En la sesión remota, ejecuta:

```bash
sudo -u ztapi -H bash
set -a
source /etc/zero-trust-api.env
set +a
cd /opt/zero-trust/backend
/opt/zero-trust/venv/bin/python -m app.create_user --username admin --role admin
```

El proceso pide la contraseña interactivamente y exige 12 caracteres como mínimo. Evita escribirla dentro de una orden o pegarla en una captura. Puedes crear usuarios con `--role user` de la misma forma.

El administrador tendrá acceso al Dashboard y podrá ver todos los recursos de prueba. Un usuario normal solo ve/elimina sus propios recursos; esto se comprueba en el Backend y no depende de que React oculte botones.

## 10. Pruebas de funcionamiento

### 10.1 Frontend y HTTPS público

Desde tu equipo:

```bash
curl -I https://app.tu-dominio.com
curl -sS https://app.tu-dominio.com/api/healthz
```

El primer comando debería mostrar `HTTP/2 200` o `HTTP/1.1 200` y encabezados como `strict-transport-security`, `content-security-policy`, `x-content-type-options`, `x-frame-options` y `referrer-policy`. El segundo debe devolver `{"status":"ok"}`. La ruta pública `/api/healthz` no expone versiones ni configuración.

### 10.2 JWT y autorización

Sin token, una ruta protegida debe devolver 401:

```bash
curl -i https://app.tu-dominio.com/api/dashboard
```

Inicia sesión a través de la UI y confirma que se abre el Dashboard. Comprueba en las herramientas de desarrollador del navegador que la API responde a `/api/auth/me`, `/api/dashboard` y `/api/tasks`. No guardes el token en un reporte público. El token expira a los 15 minutos y el Frontend lo conserva en memoria, por lo que una recarga cierra la sesión.

Prueba un usuario normal, crea un recurso, abre sesión con otro usuario normal y confirma que el recurso anterior no aparece. Prueba el rol `admin` y confirma que sí puede verlo. La comprobación del propietario se hace dentro de la API.

### 10.3 Verificar TLS privado desde Frontend

Inicia una sesión SSM en Frontend y ejecuta:

```bash
curl --fail --show-error \
  --cacert /etc/ssl/certs/zero-trust-internal-ca.pem \
  --resolve backend.internal:8443:10.20.2.10 \
  https://backend.internal:8443/api/healthz
```

Sustituye la IP si cambió. Debe funcionar sin `-k` ni `--insecure`. Esto demuestra que el Frontend confía en la CA interna y valida identidad de servicio. Después, comprueba que el Backend no tiene IPv4 pública y que su SG solo acepta TCP/8443 desde la IP privada `/32` de Frontend.

### 10.4 Fail2Ban

En una sesión SSM de Frontend:

```bash
sudo nginx -t
sudo fail2ban-client status
sudo fail2ban-client status zero-trust-auth
sudo fail2ban-regex /var/log/nginx/zero_trust_auth.log /etc/fail2ban/filter.d/zero-trust-auth.conf
```

Desde una segunda conexión pública que no sea tu IP administrativa, ejecuta más de cinco intentos de login con contraseña incorrecta dentro de diez minutos. Revisa `sudo fail2ban-client status zero-trust-auth`: el contador y la IP deben figurar en `Banned IP list`. Para desbloquear una IP de prueba:

```bash
sudo fail2ban-client set zero-trust-auth unbanip DIRECCION_IP
```

No hagas esta prueba desde tu propia IP si dependes de ella para administrar el sistema; el bloqueo inicial es de 15 minutos. La regla se aplica en el Frontend, que ve la IP de origen real. No se basa en un encabezado X-Forwarded-For proporcionado por el cliente; Nginx sobrescribe ese encabezado.

### 10.5 Certificado público y renovación

```bash
sudo certbot certificates
sudo certbot renew --dry-run
```

La prueba de renovación debe finalizar correctamente. El hook configurado recarga Nginx después de renovar. Escanea también el dominio público en `https://securityheaders.com/` y captura el resultado; esa herramienta requiere que el sitio sea accesible por Internet.

### 10.6 Tests del código Backend

En tu equipo, desde la carpeta `backend/`:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
ENVIRONMENT=test JWT_SECRET_KEY='test-only-secret-key-change-before-deployment-0123456789' pytest -q
```

Los tests comprueban health check, encabezados, protección de rutas, login correcto/incorrecto y operaciones básicas de recursos. No sustituyen pruebas de carga o auditoría profesional.

## 11. Solución de problemas

**SSM no muestra la instancia Online.** Espera el User Data, revisa el IAM instance profile y confirma salida HTTPS a los endpoints de Systems Manager a través de Internet Gateway/NAT. Revisa el estado de SSM Agent.

**Certbot devuelve timeout o unauthorized.** Confirma que el DNS A devuelve la EIP actual, que TCP/80 está abierto y que `/.well-known/acme-challenge/` se sirve por HTTP. No solicites certificados repetidamente; respeta los límites de Let's Encrypt.

**Nginx responde 502 Bad Gateway.** En Frontend revisa `sudo tail -n 100 /var/log/nginx/error.log`; en Backend revisa `sudo systemctl status zero-trust-api` y `sudo journalctl -u zero-trust-api -n 100 --no-pager`. Comprueba rutas de peering, reglas de SG TCP/8443, que el servicio esté `active` y que la IP SAN/CA coincida. No desactives `proxy_ssl_verify`.

**TLS interno falla con certificado no confiable.** Confirma que el certificado y llave se generaron con la IP correcta, que Nginx instaló el mismo `ca.crt` y que `proxy_ssl_name backend.internal` coincide con el SAN DNS del certificado.

**502/timeout al instalar paquetes en Backend.** Comprueba que la subred privada tiene ruta `0.0.0.0/0` al NAT, que NAT está en la subred pública con ruta al IGW y que el egress permite 80/443.

**Fail2Ban no detecta intentos.** Ejecuta `fail2ban-regex`, confirma que el log existe, que `nginx -t` pasa y que la petición fallida realmente devuelve 401 en `/api/auth/login`. Un login con éxito no debe contar como fallo.

## 12. Destruir recursos al terminar

Primero conserva las capturas y el reporte; no contienen secretos. Luego, desde `infra/terraform/`:

```bash
terraform plan -destroy
terraform destroy
```

Revisa el plan de destrucción antes de aceptar. El bucket de artefactos está configurado como recurso de laboratorio que Terraform puede vaciar al destruirlo; no copies esa configuración tal cual para datos de producción. Confirma en EC2, VPC, Elastic IPs, NAT Gateways y S3 que los recursos se eliminaron. Si dejaste algún recurso fuera de Terraform (por ejemplo, una zona DNS), bórralo manualmente solo si ya no lo necesitas.
