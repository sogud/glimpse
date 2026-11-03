# Glimpse website

Dependency-free static product website. Open index.html locally or serve this directory with an existing static server. No external fonts, analytics, forms or photo/browser data access.

Intended future domain: glimpse.sogud.me. Not configured or claimed live. No CNAME/canonical added before deployment verification. Social SVG is local artwork; platform-specific sharing image support remains to verify.

Deployment: existing .github/workflows/product-website-pages.yml is manual-only workflow_dispatch. It uploads only website/. Repository Pages must be configured for GitHub Actions by the owner before running. No push, deployment, domain or DNS changes were performed. Verify public visibility, licensing, HTTPS and domain ownership before publishing.

Concept visuals are not app screenshots. Keep prototype and release limits visible. Respect reduced motion and system light/dark preferences. Local fallback typeface is used when Manrope is not installed.

2026-11-01 local revision: reduced the homepage to product purpose, a labeled visual or command example, and current status. No release or deployment was performed.
Browser evidence: workspace tmp/website-rework-glimpse-desktop.jpg and tmp/website-rework-glimpse-mobile.jpg. Light/dark and keyboard focus checked; no native application, physical device or hosted-site acceptance is implied.

Asset: sample-photos.png, generated with the built-in image_gen tool. No personal photo library was read. The original tool output remains in workspace generated_images/; the website uses its own copy.

Generation prompt: "Use case: photorealistic-natural. Asset type: three sample photos for an unreleased iOS photo album website, will be explicitly labeled AI-generated examples. Create one landscape 3:2 contact sheet consisting of exactly THREE equally sized vertical photographic panels side by side, edge to edge, no gaps, no borders. Left panel: sunlit Mediterranean sea seen through a dark pine branch, horizon, quiet soft blue sea, cream rocks below, candid holiday photograph. Center panel: green mountain meadow in early summer with white wildflowers and distant mountains, analogue photograph. Right panel: still life of a clear glass of water on a sunlit wooden cafe table beside an orange curtain, warm everyday snapshot. All three natural and understated, finely textured, no overly dramatic travel advertisement look. No people, text, letters, logos, frames, rounded corners, interface or watermarks. Photographs only. Equal panels with sharp vertical boundaries at exactly one-third and two-thirds of the image width."


## 2026-11-01 photo editing desk direction

The website demonstrates a single photo organization action rather than a generic marketing page. One large Glimpse wordmark leads into a photographic editing desk: pending thumbnails, a paper photo, and one destination album. Colors: cool page #E9EDF0, desk #DBE1E6, photo paper #F8F9FA, ink #202A34, secondary #5B6570, action #274E71. Display uses Helvetica Neue; interface uses Avenir Next with system fallbacks. Large type establishes identity; the single framed photo is the main visual. No marketing section stack, decorative gradients, counters, testimonials or release claims.

The design-system search returned generic marketing and motion-heavy recommendations; these were reviewed and rejected where they conflict with the user's unreleased, low-copy brief. Keep only contrast, focus, responsive and reduced-motion guidance. The desk is explicitly a web demonstration with generated example images, not a screenshot or access to Photos. Skip, place, undo and restart affect in-memory demonstration state only. Desktop shows queue/photo/album horizontally; narrow screens put queue above the photo and compress the destination to one row. Privacy and terms pages remain supported.

Verification: existing Chrome in a disposable profile rendered 1440px desktop, exact 390px viewport and dark appearance. Evidence: workspace tmp/glimpse-desk-desktop.png, glimpse-desk-mobile.png, glimpse-desk-dark.png. Live browser clicks verified save count, skip, undo, completion focus and restart. No personal browser profile or Photos data used. Preview remains on loopback port 8814. Native app and hosted deployment are not certified.
