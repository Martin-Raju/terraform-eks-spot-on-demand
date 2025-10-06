terraform {
  backend "s3" {
    bucket  = "my-tfstate-bucket-0123456"
    key     = "Eks/Dev/terraform.tfstate"
    region  = "us-east-2"
    encrypt = true
  }
}