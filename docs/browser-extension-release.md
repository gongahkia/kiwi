# Browser extension release checklist

## Automated checks

```sh
pnpm --filter @wat/ext test
pnpm test:e2e:extension
pnpm --filter @wat/ext build:stores
```

`build:stores` creates Chrome MV3 and Firefox builds/zips. Use the Chrome zip for Chrome Web Store, Edge Add-ons, and Brave manual testing. Use the Firefox zip for AMO.

## Manual parity matrix

Verify the same build behavior on:

- Chrome: hover tooltip, side panel lookup, options persistence
- Edge: hover tooltip, side panel lookup, options persistence
- Brave: hover tooltip, side panel lookup, options persistence
- Firefox: hover tooltip, lookup UI, options persistence

## Store assets still needed

- 1280x800 promo screenshot
- 440x280 tile, if requested by store
- icons at store-required sizes
- short and long descriptions
- privacy statement matching `extensions/browser/README.md`
- demo GIF at `docs/assets/ext-hover.gif`
