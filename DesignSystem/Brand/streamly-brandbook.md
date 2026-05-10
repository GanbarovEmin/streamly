# Streamly Brand Book

Streamly is a dark-first online cinema and media center. It combines Netflix-like content browsing density with Apple TV-like polish, spacing, motion, and premium minimalism.

This brand book is the visual source of truth for Streamly UI, marketing surfaces, logo usage, design tokens, and future product screens. Use it before introducing new colors, components, layout patterns, or interaction styles.

## 1. Brand Essence

Streamly is cinematic, premium, modern, and content-first. The product should feel like a calm media environment where artwork, playback, and discovery are the focus.

Brand attributes:

- Immersive, not decorative.
- Premium, not flashy.
- Dense enough for discovery, not crowded.
- Dark-first by default.
- Apple-like in spacing, transitions, restraint, and visual finish.
- Netflix-like in browsing rhythm, content shelves, hero banners, and media hierarchy.

The interface should create a sense of forward motion, discovery, and uninterrupted viewing.

## 2. Logo System

The approved Streamly logo uses a ribbon-style play mark and forward motion symbol with a blue to violet to magenta gradient. The mark can appear as:

- Primary vertical logo: symbol above wordmark.
- Horizontal lockup: symbol beside wordmark.
- Symbol-only mark for app icons, compact nav, splash screens, and small surfaces.
- Monochrome mark only when a gradient mark is technically impossible or contrast demands it.

Logo behavior:

- Use the approved gradient as the primary brand expression.
- Keep the symbol and wordmark proportions intact.
- Maintain clear space around the logo equal to at least the height of the capital `S` in Streamly.
- Minimum horizontal lockup width: 120 px.
- Minimum app icon mark size: 48 px.
- Place the logo on dark or subtle gradient backgrounds by default.

## 3. Color System

Streamly uses deep cinematic backgrounds, restrained glassy surfaces, high-contrast typography, and focused blue/violet/magenta accents.

Core dark backgrounds:

- Obsidian: `#0A0B0F`
- Carbon: `#111318`
- Midnight Navy: `#0E1626`
- Deep Indigo: `#1B1E3F`

Signature accents:

- Electric Blue: `#2563FF`
- Neon Violet: `#7B3DFF`
- Accent Magenta: `#FF2DB2`

Text and support:

- Primary text: `#F2F4F8`
- Secondary text: `#A7ADB8`
- Muted text: `rgba(242, 244, 248, 0.56)`

Primary gradient:

```css
linear-gradient(135deg, #2563FF 0%, #7B3DFF 48%, #FF2DB2 100%)
```

Usage ratio for dark UI:

- 55% dark surfaces.
- 20% elevated surfaces.
- 15% typography.
- 10% accent glow, highlights, focus, and key visual moments.

Do not use neon as the main background. Accent color should guide attention, not overpower reading.

## 4. Typography

Streamly typography is clean, modern, highly legible, and built for dark cinematic interfaces.

Primary font stack:

```css
SF Pro Display, SF Pro Text, -apple-system, BlinkMacSystemFont, system-ui, sans-serif
```

Type scale:

- Hero: 64 / 72, weight 700, letter spacing `-0.5%`.
- H1: 48 / 56, weight 700.
- H2: 32 / 40, weight 600.
- Body: 17 / 26, weight 400.
- Caption: 13 / 18, weight 400.

Rules:

- Use large type for hero content and media titles.
- Keep metadata compact, quiet, and readable.
- Use high contrast on dark backgrounds.
- Avoid decorative display fonts, generic marketing typography, and oversized text inside compact controls.

## 5. Iconography

The icon system is soft, geometric, and instantly recognizable. It should feel aligned with the ribbon play mark: rounded, forward-moving, and clear at small sizes.

Icon rules:

- Use simple outline icons for navigation and secondary actions.
- Use filled or gradient icons sparingly for primary actions and brand moments.
- Prefer rounded rectangles, circular buttons, glassy overlays, and directional forms.
- Keep stroke weights consistent within each surface.
- Icons should never compete with poster artwork or hero imagery.

Core icons include play, search, home, library, watchlist, subtitles, cast, profile, settings, and download.

## 6. UI Direction

Streamly UI is immersive, content-first, and elegantly minimal.

Required direction:

- Dark mode by default.
- Cinematic hero banner.
- Large media artwork.
- Horizontal content shelves.
- Restrained chrome.
- Soft glassy overlays.
- Subtle blue/violet/magenta glow.
- High contrast text.
- Rounded cards.
- Smooth focus and hover states.
- Minimal but visible navigation.
- Strong content hierarchy.

Product surfaces should feel like a premium media center, not an admin dashboard. Navigation should be visible but quiet. Content artwork should carry the emotional weight of each screen.

## 7. Brand Applications

Apply Streamly consistently across:

- TV home screen.
- Desktop app shell.
- Mobile home screen.
- Content detail pages.
- Splash screen.
- App icon.
- Social promo tiles.
- Player overlays.
- Search and browse surfaces.
- Watchlist and continue-watching shelves.

Every application should keep the same hierarchy: brand presence, content artwork, clear playback action, secondary details, then supporting controls.

## 8. Usage Rules

Do:

- Maintain clear space.
- Use the logo on dark or subtle gradient backgrounds.
- Preserve proportions.
- Use the approved brand gradient.
- Ensure adequate contrast.
- Use restrained glow.
- Keep UI dark-first and content-first.

Do not:

- Use a light dashboard-style interface.
- Add overloaded panels.
- Use bright acidic accents on large text blocks.
- Add heavy shadows.
- Add unnecessary lines.
- Use neon as the primary background.
- Create a generic SaaS dashboard look.
- Stretch, rotate, recolor, or distort the logo.
- Place the logo on busy artwork without a dark overlay.
- Break apart the logo lockup.
- Use low-contrast placements.
