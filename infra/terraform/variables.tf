variable "aws_region" {
  description = "Región AWS para todos los recursos."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo corto, minúsculas y guiones, para identificar recursos."
  type        = string
  default     = "zt-lab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.project_name))
    error_message = "project_name debe tener de 3 a 16 caracteres: minúsculas, números y guiones; comenzar con letra."
  }
}

variable "frontend_instance_type" {
  description = "Tipo de instancia EC2 para Nginx/Frontend."
  type        = string
  default     = "t3.micro"
}

variable "backend_instance_type" {
  description = "Tipo de instancia EC2 para FastAPI/Backend."
  type        = string
  default     = "t3.micro"
}

variable "frontend_vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "backend_vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "frontend_public_subnet_cidr" {
  type    = string
  default = "10.10.1.0/24"
}

variable "backend_nat_public_subnet_cidr" {
  description = "Subred pública que aloja únicamente el NAT Gateway del Backend."
  type        = string
  default     = "10.20.1.0/24"
}

variable "backend_private_subnet_cidr" {
  type    = string
  default = "10.20.2.0/24"
}

variable "frontend_private_ip" {
  type    = string
  default = "10.10.1.10"
}

variable "backend_private_ip" {
  type    = string
  default = "10.20.2.10"
}

variable "domain_name" {
  description = "Dominio público que apunta al Frontend (sin https://). Déjalo vacío para preparar la infraestructura sin emitir certificado."
  type        = string
  default     = ""
}

variable "admin_email" {
  description = "Correo para notificaciones de Let's Encrypt/Certbot."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "ID opcional de una zona hospedada pública de Route 53. Si se deja vacío, DNS se configura fuera de Terraform."
  type        = string
  default     = ""
}

variable "root_volume_size_gb" {
  description = "Tamaño del volumen raíz cifrado de cada instancia EC2."
  type        = number
  default     = 12
  validation {
    condition     = var.root_volume_size_gb >= 8 && var.root_volume_size_gb <= 100
    error_message = "El volumen raíz debe ser de 8 a 100 GB."
  }
}
