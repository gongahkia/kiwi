locals {
  site_url = coalesce(var.next_public_site_url, "https://${var.app_name}.fly.dev")
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
    HOSTNAME                = "0.0.0.0"
    NODE_ENV                = "production"
    PORT                    = "3000"
    NEXT_PUBLIC_SITE_URL    = local.site_url
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
