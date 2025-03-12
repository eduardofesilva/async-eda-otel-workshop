# Look up the VPC by name
data "aws_vpc" "otel_eda_vpc" {
  filter {
    name   = "tag:Name"
    values = ["otel-eda-vpc"]
  }
}

# Create security group for Pulsar traffic
resource "aws_security_group" "pulsar_security_group" {
  name        = "pulsar-security-group"
  description = "Security group for Pulsar cluster"
  vpc_id      = data.aws_vpc.otel_eda_vpc.id

  # Pulsar binary protocol (non-TLS)
  ingress {
    from_port   = 6650
    to_port     = 6650
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Pulsar binary protocol (non-TLS)"
  }

  # Pulsar binary protocol (TLS)
  ingress {
    from_port   = 6651
    to_port     = 6651
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Pulsar binary protocol (TLS)"
  }

  # HTTP web service
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP web service"
  }

  # HTTP admin console
  ingress {
    from_port   = 9527
    to_port     = 9527
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP admin console"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
  from_port   = 8443
  to_port     = 8443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "HTTPS admin API"
}

  tags = {
    Name = "pulsar-security-group"
  }
}