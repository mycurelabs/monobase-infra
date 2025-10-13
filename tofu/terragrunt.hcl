# Root Terragrunt Configuration
# DRY configuration for all cluster deployments

# Configure Terragrunt to automatically store tfstate files in S3
remote_state {
  backend = "s3"
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  
  config = {
    bucket         = "lfh-terraform-state-${get_aws_account_id()}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "lfh-terraform-locks"
    
    # S3 bucket tags
    s3_bucket_tags = {
      ManagedBy = "terragrunt"
      Purpose   = "terraform-state"
      Project   = "lfh-infrastructure"
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
      Project     = "lfh-infrastructure"
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
