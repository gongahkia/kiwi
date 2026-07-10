output "app_name" {
  description = "Fly.io app name."
  value       = fly_app.web.name
}

output "web_url" {
  description = "Public web URL."
  value       = local.site_url
}

output "ipv4" {
  description = "Allocated IPv4 address."
  value       = fly_ip.web_v4.address
}

output "ipv6" {
  description = "Allocated IPv6 address."
  value       = fly_ip.web_v6.address
}

output "slack_url" {
  description = "Public Slack runtime URL when slack_app_name and slack_image are set."
  value       = local.slack_url
}
