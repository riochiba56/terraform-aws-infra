# -------------------------------------------------------
# Terraform設定
# -------------------------------------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.41.0"
    }
  }

  cloud{
    organization = "terraform-chapter5"

    workspaces{
        name="aws-infra"
    }
  }
}

# -------------------------------------------------------
# AWSプロバイダー設定
# -------------------------------------------------------
provider "aws" {
  region = "ap-northeast-1"
}

# -------------------------------------------------------
# VPC (CIDR: 10.0.0.0/16)
# -------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "Main"
  }
}

# -------------------------------------------------------
# パブリックサブネット
# -------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags = {
    Name = "Public"
  }
}

# -------------------------------------------------------
# プライベートサブネット
# -------------------------------------------------------
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"
  tags = {
    Name = "Private-A"
  }
}

resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-northeast-1c"
  tags = {
    Name = "Private-C"
  }
}

# -------------------------------------------------------
# インターネットゲートウェイ
# -------------------------------------------------------
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "Main"
  }
}

# -------------------------------------------------------
# ルートテーブル
# -------------------------------------------------------
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "Main"
  }
}
resource "aws_main_route_table_association" "main" {
  vpc_id         = aws_vpc.main.id
  route_table_id = aws_route_table.main.id
}

# -------------------------------------------------------
# セキュリティグループ
# -------------------------------------------------------
resource "aws_security_group" "web" {
  name        = "web"
  description = "Allow Web traffic"
  vpc_id      = aws_vpc.main.id

  # HTTP アクセスを全インターネットから許可
  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS アクセスを全インターネットから許可
  ingress {
    description = "TLS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # アウトバウンドは全トラフィック許可
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "web"
  }
}

resource "aws_security_group" "db" {
  vpc_id = aws_vpc.main.id

  # MySQL ポートをVPC内サブネットからのみ許可
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public.cidr_block, aws_subnet.private_a.cidr_block, aws_subnet.private_c.cidr_block]
  }

  # アウトバウンドは全トラフィック許可
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "sg_rds"
  }
}

# -------------------------------------------------------
# RDS インスタンス（WordPress用 MySQL データベース）
# -------------------------------------------------------
resource "aws_db_instance" "wordpress" {
  allocated_storage       = 20
  storage_type            = "gp2"
  engine                  = "mysql"
  engine_version          = "5.7"
  instance_class          = "db.t3.micro"
  db_name                 = "wpdb"
  username                = "dba"
  password                = random_password.wordpress.result
  parameter_group_name    = "default.mysql5.7"
  multi_az                = false
  db_subnet_group_name    = aws_db_subnet_group.db.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  backup_retention_period = "7"
  backup_window           = "01:00-02:00"
  skip_final_snapshot     = true
  max_allocated_storage   = 200
  identifier              = "wordpress"
  tags = {
    Name = "WordPress DB"
  }
}

resource "aws_db_subnet_group" "db" {
  name       = "wordpress"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_c.id]
  tags = {
    Name = "DB subnet group"
  }
}

resource "random_password" "wordpress" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# -------------------------------------------------------
# EC2 インスタンス（WordPress Webサーバー）
# -------------------------------------------------------
resource "aws_instance" "web" {
  ami           = "ami-0eba6c58b7918d3a1"
  instance_type = "t3.micro"
  network_interface {
    network_interface_id = aws_network_interface.web.id
    device_index         = 0
  }
  user_data = file("wordpress.sh")
  tags = {
    Name = "web"
  }
}

resource "aws_network_interface" "web" {
  subnet_id       = aws_subnet.public.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.web.id]
}

resource "aws_eip" "wordpress" {
  network_interface = aws_network_interface.web.id
  domain            = "vpc"
}