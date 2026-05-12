# LocalStack PostgreSQL Provisioning Guide: Zero-to-Hero

This guide provides a comprehensive, start-to-finish walkthrough for installing LocalStack on macOS and using it to provision a PostgreSQL database named `just_put_it`.

## 1. Prerequisites & Installation (macOS)

Ensure you have Homebrew installed. Then, run the following commands to install the necessary tools: Docker, LocalStack CLI, AWS CLI, and Terraform.

```bash
# Install Docker (if not already installed)
brew install --cask docker

# Install LocalStack CLI
brew install localstack/tap/localstack-cli

# Install AWS CLI
brew install awscli

# Install Terraform
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

Ensure the Docker Desktop application is open and running before proceeding.

## 2. LocalStack Initialization

Start LocalStack using Docker. We will expose the necessary ports and enable the RDS service.

```bash
docker run --rm -d -p 4566:4566 -p 4510-4559:4510-4559 \
  -e SERVICES=rds \
  -e DOCKER_HOST="unix:///var/run/docker.sock" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --name localstack \
  localstack/localstack
```

Verify that the LocalStack container is running:
```bash
docker ps | grep localstack
```

## 3. AWS CLI Profile Setup

Configure a local AWS profile named `localstack` so that the AWS CLI interacts with your local environment instead of real AWS.

```bash
aws configure --profile localstack
```

When prompted, input the following dummy credentials:
- **AWS Access Key ID**: `test`
- **AWS Secret Access Key**: `test`
- **Default region name**: `us-east-1`
- **Default output format**: `json`

## 4. Terraform Infrastructure Provisioning

Create a file named `main.tf` and populate it with the following configuration to define the PostgreSQL database:

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

Initialize the Terraform working directory and apply the configuration:

```bash
terraform init
terraform apply -auto-approve
```

## 5. Final Validation

Finally, verify that the RDS instance has been successfully provisioned and is available by querying LocalStack with the AWS CLI:

```bash
aws --profile localstack --endpoint-url=http://localhost:4566 rds describe-db-instances
```

Look for the `"DBInstanceStatus"` field in the JSON output. It should be `"available"`.
