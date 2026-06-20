terraform {
  required_version = ">= 1.6.0"

  required_providers {
    fly = {
      source  = "fly-apps/fly"
      version = "~> 0.0.24"
    }
  }
}
