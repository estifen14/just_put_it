# LocalStack PostgreSQL Provisioning Guide

This guide provides comprehensive instructions on how to install LocalStack locally and use it to provision a PostgreSQL database named `just_put_it`.

## Prerequisites

1. **Docker**: Required to run LocalStack.
2. **AWS CLI**: Required to interact with LocalStack's emulated AWS API.
3. **Terraform**: Required to provision the infrastructure as code.

## 1. Start LocalStack via Docker

Start LocalStack with the RDS service enabled. This command runs LocalStack in the background.

```bash
docker run --rm -d -p 4566:4566 -p 4510-4559:4510-4559 \
  -e SERVICES=rds \
  -e DOCKER_HOST="unix:///var/run/docker.sock" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --name localstack \
  localstack/localstack
```

Verify the container is running:
```bash
docker ps | grep localstack
```

## 2. Configure AWS CLI for LocalStack

Configure a local AWS profile that points to LocalStack instead of real AWS.

```bash
aws configure --profile localstack
```

When prompted, enter the following dummy values:
- **AWS Access Key ID**: `test`
- **AWS Secret Access Key**: `test`
- **Default region name**: `us-east-1`
- **Default output format**: `json`

## 3. Provision PostgreSQL via Terraform

Create a file named `main.tf` and add the following configuration:

```hcl
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
```

Initialize Terraform and apply the configuration:

```bash
terraform init
terraform apply -auto-approve
```

## 4. Verify the Database is Running

Use the AWS CLI configured for LocalStack to verify the RDS instance exists and is available:

```bash
aws --profile localstack --endpoint-url=http://localhost:4566 rds describe-db-instances
```

You should see `just-put-it-db` in the output with a `"DBInstanceStatus"` of `"available"`.
