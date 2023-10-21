terraform {
  backend "s3" {
    bucket         = "sum-s3-demo"
    key            = "sum/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}