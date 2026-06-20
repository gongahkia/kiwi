# Fly.io Terraform module

This module provisions a single-region wat web app on Fly.io. It expects an already-built image for `apps/web` and an external Postgres DSN.

## Build and push image

```sh
fly apps create wat-web
fly deploy --dockerfile apps/web/Dockerfile --build-only --push -a wat-web
```

Use the pushed image as `web_image`, for example `registry.fly.io/wat-web:deployment-...`.

## Apply

```sh
cd infra/fly
terraform init
terraform apply \
  -var app_name=wat-web \
  -var web_image=registry.fly.io/wat-web:latest \
  -var database_url="$DATABASE_URL" \
  -var auth_secret="$AUTH_SECRET"
```

## Notes

- DNS/TLS for `*.fly.dev` is handled by Fly.io.
- Custom domains still need `fly certs add <domain>` and DNS records.
- Run `pnpm db:migrate` against the same `DATABASE_URL` before promoting traffic.
