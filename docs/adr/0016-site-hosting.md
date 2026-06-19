# ADR 0016: Site hosting

## Status

Accepted.

## Context

Phase 4 needs a default host for `kumeyuri.dev`, including the landing page,
playground, comparison page, metrics page, and static player. The site is static
HTML/CSS/JS with WASM assets and no server-side compute requirement.

Inputs reviewed on 2026-06-19:

* Cloudflare Pages advertises a free tier with 500 builds/month, 100 custom
  domains per project, unlimited sites, unlimited static requests, and unlimited
  bandwidth: <https://pages.cloudflare.com/>.
* Cloudflare Pages custom apex domains must be a zone on the same Cloudflare
  account as the Pages project; subdomains can use a CNAME:
  <https://developers.cloudflare.com/pages/configuration/custom-domains/>.
* GitHub Pages supports custom domains and HTTPS:
  <https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site>
  and
  <https://docs.github.com/en/pages/getting-started-with-github-pages/securing-your-github-pages-site-with-https>.
* Vercel has a free Hobby plan and Pro starts at $20/month, with usage-based
  infrastructure pricing for managed resources:
  <https://vercel.com/pricing> and <https://vercel.com/docs/pricing>.

## Decision

Use Cloudflare Pages for `kumeyuri.dev`.

Keep GitHub Pages for `docs.kumeyuri.dev` while the existing mdBook workflow is
already configured, but do not use GitHub Pages as the primary public site host.

Do not use Vercel for the primary static site unless the project later needs
Vercel-specific preview, framework, or serverless features.

## Consequences

* The apex domain should be registered or moved into the same Cloudflare account
  as the Pages project.
* The static site deploy path can stay simple: build/copy `site/` artifacts and
  publish through Cloudflare Pages.
* Heavy launch traffic and asset-heavy pages fit Cloudflare Pages' static asset
  model better than a host with tighter or less predictable static bandwidth
  economics.
* GitHub Pages remains useful for docs because the current workflow already
  writes a `CNAME` for `docs.kumeyuri.dev`.
* If the project later needs edge compute, the decision should be revisited with
  Cloudflare Workers pricing and operational constraints included.

## Rejected

* GitHub Pages for the primary site: simplest GitHub-native deployment, but less
  flexible for apex DNS/CDN control and already assigned to docs.
* Vercel: strong preview and frontend workflow, but unnecessary for a static
  site and less attractive when cost predictability is a launch constraint.
