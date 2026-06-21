# JsSIP Browser Bundle

- Package: `jssip@3.13.8`
- Source: `https://registry.npmjs.org/jssip/-/jssip-3.13.8.tgz`
- npm integrity: `sha512-ErxEdy13vXR5izGo42fpXOU64UmC2VF7Shg4oYG7R2NzZF0FTPeYikffkIIQa9w+/11YvTlgezG1nSaycWYXPA==`
- License: MIT; see `JSSIP-LICENSE.md`
- Bundle SHA-256: `90472feec1f5577f6af386880cb7e95b908939993fe9cc9510b93c0530dd8bdc`

The browser bundle is generated from the pinned npm package with its declared
`esbuild` build dependency:

```bash
esbuild lib/JsSIP.js --bundle --global-name=JsSIP --format=iife \
  --minify --legal-comments=inline --outfile=jssip-3.13.8.min.js
```
