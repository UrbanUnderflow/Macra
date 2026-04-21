# Macra App Store Screenshot Harness

This harness renders Macra's iPhone App Store screenshot set with Playwright at
`1242 x 2688`, one of the accepted iPhone 6.5-inch portrait sizes.

Run from the project root:

```sh
npx --yes playwright@1.59.1 install chromium
node scripts/app-store-screenshots/render.mjs
```

Outputs are written to:

```text
artifacts/app-store-screenshots/
```

The HTML uses dummy nutrition data, the current Macra app icon, the existing
Macra vegetable background asset, and locally cached food imagery.
