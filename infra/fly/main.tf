locals {
  site_url      = coalesce(var.next_public_site_url, "https://${var.app_name}.fly.dev")
  slack_enabled = var.slack_app_name != null && var.slack_image != null
  slack_url     = local.slack_enabled ? "https://${var.slack_app_name}.fly.dev" : null
}

resource "fly_app" "web" {
  name = var.app_name
  org  = var.org
}

resource "fly_ip" "web_v4" {
  app        = fly_app.web.name
  type       = "v4"
  depends_on = [fly_app.web]
}

resource "fly_ip" "web_v6" {
  app        = fly_app.web.name
  type       = "v6"
  depends_on = [fly_app.web]
}

resource "fly_secrets" "web" {
  app = fly_app.web.name

  secrets = {
    AUTH_SECRET          = var.auth_secret
    DATABASE_URL         = var.database_url
    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    NEXTAUTH_SECRET      = var.auth_secret
    NEXTAUTH_URL         = local.site_url
    NEXT_PUBLIC_SITE_URL = local.site_url
    SLACK_CLIENT_ID      = var.slack_client_id
    SLACK_CLIENT_SECRET  = var.slack_client_secret
  }
}

resource "fly_machine" "web" {
  app    = fly_app.web.name
  name   = "web"
  image  = var.web_image
  region = var.region

  cpus     = var.machine_cpus
  memorymb = var.machine_memory_mb

  env = {
    HOSTNAME                 = "0.0.0.0"
    NODE_ENV                 = "production"
    PORT                     = "3000"
    NEXT_PUBLIC_SITE_URL     = local.site_url
    WAT_RATE_LIMIT_WINDOW_MS = "60000"
  }

  services = [
    {
      internal_port = 3000
      protocol      = "tcp"

      ports = [
        {
          port     = 80
          handlers = ["http"]
        },
        {
          port     = 443
          handlers = ["tls", "http"]
        }
      ]

      checks = [
        {
          type     = "http"
          port     = 3000
          method   = "GET"
          path     = "/readyz"
          interval = "10s"
          timeout  = "2s"
        }
      ]
    }
  ]

  depends_on = [fly_secrets.web]
}

resource "fly_app" "slack" {
  count = local.slack_enabled ? 1 : 0
  name  = var.slack_app_name
  org   = var.org
}

resource "fly_ip" "slack_v4" {
  count      = local.slack_enabled ? 1 : 0
  app        = fly_app.slack[0].name
  type       = "v4"
  depends_on = [fly_app.slack]
}

resource "fly_ip" "slack_v6" {
  count      = local.slack_enabled ? 1 : 0
  app        = fly_app.slack[0].name
  type       = "v6"
  depends_on = [fly_app.slack]
}

resource "fly_secrets" "slack" {
  count = local.slack_enabled ? 1 : 0
  app   = fly_app.slack[0].name

  secrets = {
    DATABASE_URL               = var.database_url
    SLACK_BOT_TOKEN            = var.slack_bot_token
    SLACK_CLIENT_ID            = var.slack_client_id
    SLACK_CLIENT_SECRET        = var.slack_client_secret
    SLACK_DATABASE_URL         = var.database_url
    SLACK_INSTALL_STORE        = "postgres"
    SLACK_METRICS_TOKEN        = var.slack_metrics_token
    SLACK_REDIRECT_URI         = coalesce(var.slack_redirect_uri, "${local.slack_url}/slack/oauth/callback")
    SLACK_SIGNING_SECRET       = var.slack_signing_secret
    SLACK_STATE_SECRET         = var.slack_state_secret
    SLACK_TOKEN_ENCRYPTION_KEY = var.slack_token_encryption_key
    WAT_API_BASE_URL           = local.site_url
    WAT_API_KEY                = var.slack_wat_api_key
    WAT_SLACK_TEAM_MAP         = var.wat_slack_team_map
    WAT_TEAM_ID                = var.slack_wat_team_id
  }
}

resource "fly_machine" "slack" {
  count  = local.slack_enabled ? 1 : 0
  app    = fly_app.slack[0].name
  name   = "slack"
  image  = var.slack_image
  region = var.region

  cpus     = var.slack_machine_cpus
  memorymb = var.slack_machine_memory_mb

  env = {
    NODE_ENV          = "production"
    PORT              = "3001"
    SLACK_HTTP_MODE   = "true"
    SLACK_SOCKET_MODE = "false"
  }

  services = [
    {
      internal_port = 3001
      protocol      = "tcp"

      ports = [
        {
          port     = 80
          handlers = ["http"]
        },
        {
          port     = 443
          handlers = ["tls", "http"]
        }
      ]

      checks = [
        {
          type     = "http"
          port     = 3001
          method   = "GET"
          path     = "/healthz"
          interval = "10s"
          timeout  = "2s"
        }
      ]
    }
  ]

  depends_on = [fly_secrets.slack]
}
