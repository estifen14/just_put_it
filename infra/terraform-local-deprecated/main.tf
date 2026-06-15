terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  
  endpoints {
    rds = "http://localhost:4566"
  }
}

resource "aws_db_instance" "just_put_it_db" {
  identifier           = "just-put-it-db"
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "15.4"
  instance_class       = "db.t3.micro"
  username             = "postgres"
  password             = "postgres"
  db_name              = "just_put_it"
  skip_final_snapshot  = true
}
