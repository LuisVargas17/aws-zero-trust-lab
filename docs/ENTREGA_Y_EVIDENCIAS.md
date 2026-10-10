# Entrega académica y evidencias

Usa nombres de archivo consistentes; cada captura debe mostrar qué se probó y, en el reporte, una explicación breve de la configuración y del resultado. Oculta account IDs, correos personales, tokens, contraseñas, claves y nombres sensibles.

## Evidencias recomendadas

| ID | Captura/archivo | Qué debe demostrar |
|---|---|---|
| E01 | `E01_vpcs.png` | VPC Frontend y Backend con CIDR no solapados. |
| E02 | `E02_subnets_routes.png` | Subred pública Frontend, subred pública técnica NAT, subred privada Backend y rutas. |
| E03 | `E03_vpc_peering.png` | Peering en estado Active. |
| E04 | `E04_security_groups.png` | Frontend expone 80/443; Backend solo permite 8443 desde `10.10.1.10/32`; no hay 22 público. |
| E05 | `E05_ec2_private_backend.png` | Frontend tiene EIP y Backend no tiene IP pública. |
| E06 | `E06_ssm_online.png` | Ambas EC2 administrables por Systems Manager. |
| E07 | `E07_tls_internal.png` | Salida de `curl --cacert ... --resolve ...` exitosa desde Frontend, sin `-k`. |
| E08 | `E08_https_headers.png` | Salida de `curl -I https://dominio` con HSTS, CSP, X-Content-Type-Options y Referrer-Policy. |
| E09 | `E09_securityheaders.png` | Resultado del escaneo en SecurityHeaders.com, con dominio visible y sin información personal. |
| E10 | `E10_login_dashboard.png` | Login con usuario válido y Dashboard visible. No mostrar contraseña ni token. |
| E11 | `E11_jwt_401.png` | Acceso a `/api/dashboard` sin token devuelve 401. |
| E12 | `E12_authorization_scope.png` | Usuario normal solo ve sus recursos; admin puede ver todos. |
| E13 | `E13_fail2ban.png` | `fail2ban-client status zero-trust-auth` muestra un bloqueo de prueba. Oculta la IP real. |
| E14 | `E14_backend_tests.png` | `pytest -q` finaliza con todas las pruebas correctas. |
| E15 | `E15_certbot.png` | `certbot certificates` y `certbot renew --dry-run` correctos. |
| E16 | `E16_git_links.png` | URL del repositorio Git con código Frontend y Backend, sin archivos secretos. |
| E17 | `E17_architecture.png` | Diagrama final con VPC, subredes, EC2, EIP/DNS, NAT, peering, rutas, SGs, TLS/JWT y persistencia. |

## Checklist de demostración

- [ ] Las dos VPC existen y los CIDR no se solapan.
- [ ] Peering activo y rutas en ambas direcciones.
- [ ] El Frontend responde por HTTPS con certificado público válido.
- [ ] La API tiene TLS interno y el Frontend verifica la CA interna.
- [ ] La instancia Backend no posee IP pública.
- [ ] Security Group Backend no acepta tráfico de API desde Internet; solo desde la IP privada permitida del Frontend.
- [ ] No hay SSH público; el acceso administrativo se hace con Systems Manager.
- [ ] Sin JWT, los endpoints protegidos devuelven 401.
- [ ] Token incorrecto o expirado rechazado.
- [ ] Los permisos por usuario/rol son efectivos en Backend.
- [ ] El Dashboard utiliza datos de la API y la capa de persistencia.
- [ ] Los encabezados de seguridad están configurados y se verificó SecurityHeaders.com.
- [ ] Fail2Ban registra y bloquea temporalmente una IP de prueba.
- [ ] Tests automatizados correctos.
- [ ] El diagrama y el reporte coinciden con los recursos reales desplegados.

## Plantilla mínima para el reporte técnico

1. **Objetivo y alcance:** qué funcionalidades se desplegaron y qué queda fuera (por ejemplo, SQLite solo para laboratorio).
2. **Arquitectura de software:** React componentes; Nginx como servidor estático y reverse proxy; FastAPI routers/dependencias; SQLAlchemy/repo de persistencia; JWT; modelo de usuarios/recursos.
3. **Infraestructura:** diagrama, CIDR, subredes, tablas de rutas, peering, IGW, NAT, EC2, EIP, perfiles IAM y Security Groups.
4. **Decisiones de seguridad:** Zero Trust, privilegio mínimo, autenticación, autorización por objeto, TLS público/interno, gestión de secretos, encabezados, registro de login fallido y Fail2Ban.
5. **Pruebas ejecutadas:** pasos, resultado esperado, resultado obtenido, captura asociada y cualquier diferencia.
6. **Riesgos/limitaciones:** NAT costoso, SQLite no HA, instancia única sin autoscaling, ausencia de WAF/RDS/monitorización central en este laboratorio y plan de mejora.
7. **Limpieza y costos:** cuándo se ejecutó `terraform destroy` y cómo se verificó la eliminación de recursos facturables.

## Git sin filtrar secretos

Antes de publicar los repositorios, verifica:

```bash
git status --short
git check-ignore certs/generated/ca.key dist/backend-deploy.tar.gz infra/terraform/terraform.tfstate
```

No hagas `git add -f` a llaves, estados Terraform, variables locales, paquetes de despliegue o credenciales. Publica solo los directorios de fuente, infraestructura de ejemplo y documentación.
