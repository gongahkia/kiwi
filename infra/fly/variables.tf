variable "app_name" {
  description = "Fly.io app name for the wat web service."
  type        = string
}

variable "org" {
  description = "Fly.io organization slug."
  type        = string
  default     = "personal"
}

variable "region" {
  description = "Primary Fly.io region."
  type        = string
  default     = "sjc"
}

variable "web_image" {
  description = "Prebuilt OCI image for apps/web. Push this before terraform apply."
  type        = string
}

variable "database_url" {
  description = "Postgres DSN, for example a Fly Postgres or Neon URL."
  type        = string
  sensitive   = true
}

variable "auth_secret" {
  description = "NextAuth/Auth.js secret."
  type        = string
  sensitive   = true
}

variable "next_public_site_url" {
  description = "Public wat web URL. Defaults to https://<app_name>.fly.dev."
  type        = string
  default     = null
}

variable "machine_cpus" {
  description = "Shared CPU count for the web machine."
  type        = number
  default     = 1
}

variable "machine_memory_mb" {
  description = "Memory size for the web machine."
  type        = number
  default     = 512
}

variable "slack_client_id" {
  description = "Optional Slack OAuth client ID for hosted auth."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_client_secret" {
  description = "Optional Slack OAuth client secret for hosted auth."
  type        = string
  default     = ""
  sensitive   = true
}

variable "google_client_id" {
  description = "Optional Google OAuth client ID for hosted auth."
  type        = string
  default     = ""
  sensitive   = true
}

variable "google_client_secret" {
  description = "Optional Google OAuth client secret for hosted auth."
  type        = string
  default     = ""
  sensitive   = true
}
