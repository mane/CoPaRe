# CoPaRe website

Static pages for `https://copare.it`. The production site is served by Apache at
`/var/www/copare.it/public` on the configured SSH host. Publish the contents of
this directory as the web root; preserve the server configuration and take a
backup before deployment.

The site uses no JavaScript, external fonts, analytics, cookies, or network
requests to third-party assets. Native disclosure elements provide the FAQ
interaction. All styling is in `styles.css`, compatible with the production
Content Security Policy (`script-src 'none'; style-src 'self'`).

The actual app icon is copied to `assets/app-icon.png`. Existing product
screenshots in `assets/optimized/` are responsive WebP images showing example
content; the website does not fabricate new app UI. The original App Store
screenshots are not published from this directory.

The homepage describes version 1.5 and explicitly distinguishes the GitHub
release from App Store availability, which depends on Apple's review. Keep
these statements current when preparing future releases.

## Local preview

Run `python3 -m http.server 8765 --directory site`, then open
`http://127.0.0.1:8765/`. Check the homepage, support, and privacy pages at both
desktop and mobile widths. No build step or package installation is required.

## App Store Connect URLs

- Marketing URL: `https://copare.it/`
- Support URL: `https://copare.it/support/`
- Privacy Policy URL: `https://copare.it/privacy/`
- User Privacy Choices URL: `https://copare.it/privacy/#privacy-choices`
