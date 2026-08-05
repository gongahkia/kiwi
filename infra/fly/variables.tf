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

variable "slack_app_name" {
  description = "Optional Fly.io app name for the Slack HTTP runtime. Set with slack_image to deploy Slack."
  type        = string
  default     = null
}

variable "slack_image" {
  description = "Optional prebuilt OCI image for apps/slack."
  type        = string
  default     = null
}

variable "slack_bot_token" {
  description = "Optional Slack bot token for runtime health and future command handling."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_signing_secret" {
  description = "Slack signing secret for HTTP event verification."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_state_secret" {
  description = "Secret used to sign Slack OAuth state."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_token_encryption_key" {
  description = "Secret used to encrypt Slack OAuth install tokens."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_metrics_token" {
  description = "Bearer token for the Slack runtime metrics endpoint."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_redirect_uri" {
  description = "Optional Slack OAuth redirect URI. Defaults to https://<slack_app_name>.fly.dev/slack/oauth/callback."
  type        = string
  default     = null
}

variable "slack_wat_api_key" {
  description = "Team-scoped wat API key used by the Slack runtime."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_wat_team_id" {
  description = "Optional fallback wat team id for single-team Slack installs."
  type        = string
  default     = ""
}

variable "wat_slack_team_map" {
  description = "Optional comma-separated Slack workspace to wat team mapping, for example T123:team_123."
  type        = string
  default     = ""
}

variable "slack_machine_cpus" {
  description = "Shared CPU count for the Slack machine."
  type        = number
  default     = 1
}

variable "slack_machine_memory_mb" {
  description = "Memory size for the Slack machine."
  type        = number
  default     = 256
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
