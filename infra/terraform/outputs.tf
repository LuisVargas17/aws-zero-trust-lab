output "frontend_public_ip" {
  description = "Dirección IPv4 pública del Frontend."
  value       = aws_eip.frontend.public_ip
}

output "frontend_instance_id" {
  value       = aws_instance.frontend.id
  description = "ID de EC2 Frontend, para administrarlo con SSM."
}

output "backend_instance_id" {
  value       = aws_instance.backend.id
  description = "ID de EC2 Backend privado, para administrarlo con SSM."
}

output "backend_private_ip" {
  value       = aws_instance.backend.private_ip
  description = "IP privada de la API; no es accesible directamente desde Internet."
}

output "artifact_bucket" {
  value       = aws_s3_bucket.artifacts.bucket
  description = "Bucket privado para paquetes de despliegue."
}

output "vpc_peering_id" {
  value       = aws_vpc_peering_connection.frontend_backend.id
  description = "ID de la conexión privada de peering."
}

output "frontend_vpc_id" {
  value       = aws_vpc.frontend.id
  description = "ID de la VPC Frontend."
}

output "backend_vpc_id" {
  value       = aws_vpc.backend.id
  description = "ID de la VPC Backend."
}
