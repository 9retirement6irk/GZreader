# Third-party code used by the sync page

## libheif-1.23.5.js

Decodes HEIC/HEIF pictures (iPhone photos) for the sleep screen pictures, as
most browsers can't open them. The sync page loads it only when such a
picture is added, in a Web Worker (`Heic` in `../gzsync.js`). The picture
never leaves the browser.

- What: `libheif-wasm/libheif-bundle.js` from the npm package
  [`libheif-js`](https://github.com/catdad-experiments/libheif-js) 1.23.5
  (an Emscripten build of [libheif](https://github.com/strukturag/libheif)
  with [libde265](https://github.com/strukturag/libde265), the WebAssembly
  inside the file), unchanged.
- Licence: GNU LGPL 3.0 (`libheif-LICENSE.txt`, as shipped in the package).
- npm tarball integrity: `sha512-umXZPthnWZtF3iG/5mQG+AZ2V6i0UeYpo3z2CkggTEgL8dKmIIwJT6TDuAMuabXa1yTW8uJ1ZAgR+CxNTklYYw==`;
  this file's SHA-256: `074b2b55ef3de477ba9f794ca381f3f0324c1cba8c91b4af07395f39c22d54cc`.
- To update: `npm pack libheif-js@<version>`, copy `libheif-wasm/libheif-bundle.js`
  here as `libheif-<version>.js` (a new name, so browsers holding the old file
  for GitHub Pages' 10 minutes don't mix them), update `Heic.LIB` in
  `gzsync.js` (and its `?v=` in `index.html`), this README and the licence.
