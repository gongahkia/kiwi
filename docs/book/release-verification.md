# Release Verification

Official release artifacts are expected to have GitHub provenance attestations
and keyless Sigstore bundles when the repository is public.

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
