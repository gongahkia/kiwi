# Release Verification

Official release artifacts are expected to have GitHub provenance attestations
and keyless Sigstore bundles when the repository is public.

npm workspaces are expected to publish through GitHub OIDC trusted publishing,
with `publishConfig.provenance=true`, no `NPM_TOKEN`/`NODE_AUTH_TOKEN`, and an
uploaded npm SBOM artifact from the publish workflow.

Download a release:

```bash
tag=v1.0.0
mkdir -p dist
gh release download "$tag" --repo gongahkia/kumeyuri --dir dist
```

Verify GitHub artifact attestations:

```bash
for artifact in dist/*; do
  case "$artifact" in
    *.sigstore.json) continue ;;
  esac
  gh attestation verify "$artifact" --repo gongahkia/kumeyuri
done
```

Verify each Sigstore bundle:

```bash
for artifact in dist/*; do
  case "$artifact" in
    *.sigstore.json) continue ;;
  esac
  cosign verify-blob "$artifact" \
    --bundle "$artifact.sigstore.json" \
    --certificate-identity-regexp 'https://github.com/gongahkia/kumeyuri/.github/workflows/release.yml@refs/tags/.*' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
done
```

If an artifact has no matching `.sigstore.json` bundle or GitHub attestation,
treat the release as unverifiable.

Verify repository release-trust metadata:

```bash
npm run release:trust
```

Verify npm package provenance and SBOM after publish:

```bash
npm view kumeyuri dist.integrity repository version
npm sbom --json > npm-sbom.cdx.json
```
