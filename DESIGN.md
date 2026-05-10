# Streamly Design System

Streamly Brand Book is the visual source of truth for all UI tasks in this project.

Primary files:

- `DesignSystem/Brand/streamly-brandbook.md`
- `DesignSystem/Brand/streamly-design-tokens.json`
- `DesignSystem/Brand/streamly-ui-principles.md`
- `DesignSystem/Brand/streamly-logo-usage.md`

The application is an online cinema / media center in the style of Netflix plus Apple TV. It must stay dark-first unless a separate task explicitly asks for a light interface.

## Visual Direction

Streamly combines Netflix-like content browsing density with Apple TV-like polish, spacing, motion, and premium minimalism.

Required UI traits:

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

## Token Boundary

Use `DesignSystem/Brand/streamly-design-tokens.json` as the canonical token source for colors, gradient, radius, spacing, and typography.

Swift implementation may continue to live in `Sources/CineFlowDesignSystem`, but new UI work should align those implementation tokens with the Streamly JSON tokens instead of extending the older CineFlow palette.

## Do Not Use

- Light dashboard-style interfaces.
- Overloaded panels.
- Bright acidic accents on large text blocks.
- Heavy shadows.
- Unnecessary lines.
- Neon as the main background.
- Generic SaaS dashboard layouts.
