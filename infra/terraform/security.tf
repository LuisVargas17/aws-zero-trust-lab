resource "aws_security_group" "frontend" {
  name        = "${var.project_name}-frontend-sg"
  description = "Acceso público web; administración solo mediante Systems Manager."
  vpc_id      = aws_vpc.frontend.id

  ingress {
    description = "Redirección HTTP y desafío ACME de Certbot"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS público"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description     = "Proxy hacia la API privada"
    from_port       = 8443
    to_port         = 8443
    protocol        = "tcp"
    cidr_blocks     = ["${var.backend_private_ip}/32"]
  }
  egress {
    description = "HTTPS para SSM, S3, paquetes y ACME"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "HTTP para repositorios que aún redirigen a HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-frontend-sg" }
}

resource "aws_security_group" "backend" {
  name        = "${var.project_name}-backend-sg"
  description = "API privada accesible únicamente desde la IP privada fija del Frontend (/32)."
  vpc_id      = aws_vpc.backend.id

  ingress {
    description     = "FastAPI con TLS solo desde el Frontend"
    from_port       = 8443
    to_port         = 8443
    protocol        = "tcp"
    cidr_blocks     = ["${var.frontend_private_ip}/32"]
  }
  egress {
    description = "Salida por NAT para parches, SSM, S3 y dependencias"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Repositorios del sistema operativo"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-backend-sg" }
}

resource "aws_iam_role" "frontend_ec2" {
  name = "${var.project_name}-frontend-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role" "backend_ec2" {
  name = "${var.project_name}-backend-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "frontend_ssm" {
  role       = aws_iam_role.frontend_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "backend_ssm" {
  role       = aws_iam_role.backend_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "frontend" {
  name = "${var.project_name}-frontend-profile"
  role = aws_iam_role.frontend_ec2.name
}
resource "aws_iam_instance_profile" "backend" {
  name = "${var.project_name}-backend-profile"
  role = aws_iam_role.backend_ec2.name
}

resource "random_id" "artifact_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.project_name}-artifacts-${random_id.artifact_suffix.hex}"
  force_destroy = true
  tags          = { Name = "${var.project_name}-private-artifacts" }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_iam_role_policy" "frontend_artifact_read" {
  name = "${var.project_name}-frontend-artifact-read"
  role = aws_iam_role.frontend_ec2.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.artifacts.arn}/frontend/*" }
    ]
  })
}

resource "aws_iam_role_policy" "backend_artifact_read" {
  name = "${var.project_name}-backend-artifact-read"
  role = aws_iam_role.backend_ec2.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.artifacts.arn}/backend/*" }
    ]
  })
}
