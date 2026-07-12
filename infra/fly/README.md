# Fly.io Terraform module

This module provisions a single-region wat web app on Fly.io. It can also provision the Slack HTTP runtime when `slack_app_name` and `slack_image` are set. It expects already-built images and an external Postgres DSN.

## Build and push image

```sh
fly apps create wat-web
fly deploy --dockerfile apps/web/Dockerfile --build-only --push -a wat-web
fly apps create wat-slack
fly deploy --dockerfile apps/slack/Dockerfile --build-only --push -a wat-slack
```

Use the pushed images as `web_image` and `slack_image`, for example `registry.fly.io/wat-web:deployment-...` and `registry.fly.io/wat-slack:deployment-...`.

## Apply

`terraform apply` uses `flyctl secrets set` for runtime secrets because the Fly Terraform provider does not manage secrets. Install `flyctl` and export `FLY_API_TOKEN` before applying.

```sh
cd infra/fly
terraform init
terraform apply \
  -var app_name=wat-web \
  -var web_image=registry.fly.io/wat-web:latest \
  -var database_url="$DATABASE_URL" \
  -var auth_secret="$AUTH_SECRET"
```

To include Slack HTTP events/OAuth/metrics:

```sh
terraform apply \
  -var app_name=wat-web \
  -var web_image=registry.fly.io/wat-web:latest \
  -var slack_app_name=wat-slack \
  -var slack_image=registry.fly.io/wat-slack:latest \
  -var database_url="$DATABASE_URL" \
  -var auth_secret="$AUTH_SECRET" \
  -var slack_client_id="$SLACK_CLIENT_ID" \
  -var slack_client_secret="$SLACK_CLIENT_SECRET" \
  -var slack_signing_secret="$SLACK_SIGNING_SECRET" \
  -var slack_state_secret="$SLACK_STATE_SECRET" \
  -var slack_token_encryption_key="$SLACK_TOKEN_ENCRYPTION_KEY" \
  -var slack_metrics_token="$SLACK_METRICS_TOKEN" \
  -var slack_wat_api_key="$WAT_API_KEY"
```

## Smoke test

After apply, verify readiness and a seeded public search:

```sh
pnpm smoke:deployment -- --url "$(terraform output -raw web_url)"
curl -f "$(terraform output -raw slack_url)/healthz"
```

## Rollback

To roll back a bad web/API deploy without changing data, set `web_image` to the last known-good pushed image and re-run `terraform apply`. Keep `database_url` unchanged, then run the smoke test above. For migration or data rollback, follow `docs/migration-runbook.md`.

## Notes

- DNS/TLS for `*.fly.dev` is handled by Fly.io.
- Custom domains still need `fly certs add <domain>` and DNS records.
- Run `pnpm db:migrate` against the same `DATABASE_URL` before promoting traffic.
