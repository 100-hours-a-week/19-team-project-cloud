# -----------------------------------------------------
# Terraform Backend Configuration
# -----------------------------------------------------

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
