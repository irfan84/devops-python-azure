# backend.tf
terraform {
  # We moved the 'required_providers' to providers.tf, 
  # so we only keep the backend socket here.
  backend "azurerm" {}
}