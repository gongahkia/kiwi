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

resource "terraform_data" "web_secrets" {
  input = {
    app         = fly_app.web.name
    fingerprint = sha256(join("|", [var.auth_secret, var.database_url, var.google_client_id, var.google_client_secret, local.site_url, var.slack_client_id, var.slack_client_secret]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      flyctl secrets set --app "$FLY_APP" \
        AUTH_SECRET="$AUTH_SECRET" \
        DATABASE_URL="$DATABASE_URL" \
        GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
        GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
        NEXTAUTH_SECRET="$AUTH_SECRET" \
        NEXTAUTH_URL="$SITE_URL" \
        NEXT_PUBLIC_SITE_URL="$SITE_URL" \
        SLACK_CLIENT_ID="$SLACK_CLIENT_ID" \
        SLACK_CLIENT_SECRET="$SLACK_CLIENT_SECRET"
    EOT

    environment = {
      AUTH_SECRET          = var.auth_secret
      DATABASE_URL         = var.database_url
      FLY_APP              = fly_app.web.name
      GOOGLE_CLIENT_ID     = var.google_client_id
      GOOGLE_CLIENT_SECRET = var.google_client_secret
      SITE_URL             = local.site_url
      SLACK_CLIENT_ID      = var.slack_client_id
      SLACK_CLIENT_SECRET  = var.slack_client_secret
    }
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

  depends_on = [terraform_data.web_secrets]
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

resource "terraform_data" "slack_secrets" {
  count = local.slack_enabled ? 1 : 0

  input = {
    app         = fly_app.slack[0].name
    fingerprint = sha256(join("|", [var.database_url, var.slack_bot_token, var.slack_client_id, var.slack_client_secret, var.slack_metrics_token, coalesce(var.slack_redirect_uri, "${local.slack_url}/slack/oauth/callback"), var.slack_signing_secret, var.slack_state_secret, var.slack_token_encryption_key, local.site_url, var.slack_wat_api_key, var.wat_slack_team_map, var.slack_wat_team_id]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      flyctl secrets set --app "$FLY_APP" \
        DATABASE_URL="$DATABASE_URL" \
        SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
        SLACK_CLIENT_ID="$SLACK_CLIENT_ID" \
        SLACK_CLIENT_SECRET="$SLACK_CLIENT_SECRET" \
        SLACK_DATABASE_URL="$DATABASE_URL" \
        SLACK_INSTALL_STORE="postgres" \
        SLACK_METRICS_TOKEN="$SLACK_METRICS_TOKEN" \
        SLACK_REDIRECT_URI="$SLACK_REDIRECT_URI" \
        SLACK_SIGNING_SECRET="$SLACK_SIGNING_SECRET" \
        SLACK_STATE_SECRET="$SLACK_STATE_SECRET" \
        SLACK_TOKEN_ENCRYPTION_KEY="$SLACK_TOKEN_ENCRYPTION_KEY" \
        WAT_API_BASE_URL="$WAT_API_BASE_URL" \
        WAT_API_KEY="$WAT_API_KEY" \
        WAT_SLACK_TEAM_MAP="$WAT_SLACK_TEAM_MAP" \
        WAT_TEAM_ID="$WAT_TEAM_ID"
    EOT

    environment = {
      DATABASE_URL               = var.database_url
      FLY_APP                    = fly_app.slack[0].name
      SLACK_BOT_TOKEN            = var.slack_bot_token
      SLACK_CLIENT_ID            = var.slack_client_id
      SLACK_CLIENT_SECRET        = var.slack_client_secret
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

  depends_on = [terraform_data.slack_secrets]
}
