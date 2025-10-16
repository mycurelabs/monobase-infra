# Root Terragrunt Configuration
# DRY configuration for all cluster deployments
#
# OPTIONAL: This configuration enables S3 backend for remote state.
# If you don't want to use S3, simply don't use terragrunt - use terraform/tofu directly.
#
# S3 Backend Setup (one-time, before using terragrunt):
# 1. Create S3 bucket:
#    aws s3api create-bucket --bucket monobase-terraform-state-$(aws sts get-caller-identity --query Account --output text) --region us-east-1
# 2. Enable versioning:
#    aws s3api put-bucket-versioning --bucket monobase-terraform-state-$(aws sts get-caller-identity --query Account --output text) --versioning-configuration Status=Enabled
# 3. Create DynamoDB table for locking:
#    aws dynamodb create-table --table-name monobase-terraform-locks --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region us-east-1
#
# Alternative: Use local state by working directly with terraform/tofu (skip terragrunt)

# Configure Terragrunt to automatically store tfstate files in S3
remote_state {
  backend = "s3"
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  
  config = {
    bucket         = "monobase-terraform-state-${get_aws_account_id()}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "monobase-terraform-locks"
    
    # S3 bucket tags
    s3_bucket_tags = {
      ManagedBy = "terragrunt"
      Purpose   = "terraform-state"
      Project   = "monobase-infrastructure"
    }
  }
}

# Generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  
  contents = <<EOF
terraform {
  required_version = ">= 1.6"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
  
  default_tags {
    tags = {
      ManagedBy   = "opentofu"
      Project     = "monobase-infrastructure"
      Terragrunt  = "true"
    }
  }
}
EOF
}

# Configure common inputs
inputs = {
  # These can be overridden in cluster-specific terragrunt.hcl
}
