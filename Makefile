.PHONY: help test frontend-build certs deploy-packages tf-fmt tf-validate
help:
	@echo 'make test            - Ejecutar tests Backend'
	@echo 'make frontend-build  - Construir React'
	@echo 'make certs           - Crear certificados internos para la IP privada por defecto'
	@echo 'make deploy-packages - Construir los dos paquetes tar.gz (requiere certs y Node/npm)'
	@echo 'make tf-fmt          - Aplicar terraform fmt'
	@echo 'make tf-validate     - Validar Terraform (requiere terraform init)'

test:
	cd backend && ENVIRONMENT=test JWT_SECRET_KEY='test-only-secret-key-change-before-deployment-0123456789' pytest -q

frontend-build:
	cd frontend && npm install && npm run build

certs:
	./scripts/generate-internal-certs.sh 10.20.2.10

deploy-packages:
	./scripts/build-deployments.sh

tf-fmt:
	terraform -chdir=infra/terraform fmt -recursive

tf-validate:
	terraform -chdir=infra/terraform validate
