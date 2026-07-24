# Promo Visual Audit — 2026-07-24

## The point (from the user)

SuperDimmer is **not** a general screen dimmer. The unique proof is:

> Dark mode desktop + a white PDF/document you **cannot** restyle → only that bright content is dimmed. Everything else (dark IDE, chrome, wallpaper) stays untouched.

If a visual looks like f.lux / Night Shift / whole-screen opacity, it fails.

## Landing page assets

| Asset | Was | Verdict | Action |
|-------|-----|---------|--------|
| Hero compare (`index.html` interactive) | Mail + global tint / sepia | FAIL — read as generic dimmer | **FIXED** — white PDF in Preview, only page dims |
| `web-superdimmer-hero-1.png` | Same failure as hero | FAIL | **FIXED** — isolation screenshot |
| `og-superdimmer-share-card.png` | Logo + tagline only | FAIL — no product proof | **FIXED** — before/after PDF isolation card |
| `web-superdimmer-features-overview.png` | Abstract AI glow collage; wrong Kelvin story | FAIL | **FIXED** — four real product tiles, isolation first |
| `web-superspaces-*.png` | Super Spaces HUD UI | PASS for Spaces feature (different feature) | Keep; not the isolation USP |
| `logo-icon.png` | Checkerboard baked in | FAIL (link previews) | Fixed earlier same day |
| `web-superdimmer-social-promo.png` | AI MacBook collage | FAIL — generic / Spaces-heavy | Replace next (use OG isolation card for shares) |

## Full promo folder (source AI set, Jan 2026)

| Asset | Verdict | Notes |
|-------|---------|-------|
| `superdimmer-hero-1.png` | FAIL | Old MacBook sun-glare; superseded |
| `superdimmer-features-overview.png` | FAIL | Abstract; superseded by web- version |
| `superdimmer-feature-detection.png` | PARTIAL | Mentions regions but not white-PDF-in-dark-mode |
| `superdimmer-before-after-grid.png` | PARTIAL | Use-cases exist but not isolation-clear |
| `superdimmer-color-temperature.png` | OK for temp feature | Must never be used as *the* product hero |
| `superdimmer-window-dimming.png` | OK for inactive-window feature | Secondary |
| `superdimmer-auto-hide.png` | OK for auto-hide | Secondary |
| `superdimmer-menu-bar.png` | OK for UI chrome | Secondary |
| `superdimmer-super-spaces-hud.png` | OK for Spaces | Secondary |
| `superdimmer-social-promo.png` | FAIL | Same MacBook generic energy |
| `superdimmer-icon-branding.png` | WEAK | Icon badges, no isolation proof |
| `superdimmer-technical-diagram.png` | OK for docs | Not marketing hero |

## Blog heroes

Most `blog-hero-*.png` files are AI lifestyle art. They do not prove isolation.

Priority replacements (wave 2):

1. `blog-hero-dark-mode-not-enough.png` — must show white content breaking dark mode
2. `blog-hero-flux-alternatives.png` — must contrast whole-screen tint vs region isolation
3. `blog-hero-programmers-screen-dimming.png` — dark IDE + white docs
4. `blog-hero-zone-dimming-analysis.png` — grid on bright tiles only

Until replaced, do not use blog heroes as homepage/social primary images.

## Rules for future promo

1. **Same dark chrome on both sides** of any before/after.
2. **Only the unrestylable bright content** changes (PDF page, white email body, bright web article).
3. Never globally sepia / darken wallpaper to sell “after.”
4. Caption must say isolation in plain language: “Only the PDF dimmed.”
5. OG/social cards must show the product proof, not just the logo.
