# Streamly UI Principles

Streamly UI must stay dark-first, cinematic, and content-led. The product should combine Netflix-like browsing density with Apple TV-like polish, spacing, motion, and premium restraint.

## Source of Truth

Use `streamly-design-tokens.json` for color, gradient, radius, spacing, and typography decisions. Use `streamly-brandbook.md` for product-level visual direction.

## Layout

- Start primary browse screens with a cinematic hero area.
- Prioritize media artwork over chrome.
- Use horizontal content shelves for discovery, continue-watching, trending, and collections.
- Keep navigation minimal but visible.
- Use strong hierarchy: hero title, primary action, metadata, shelves, secondary controls.
- Avoid dashboard grids, admin panels, and generic equal-card layouts unless a specific workflow requires them.

## Surfaces

- Use obsidian, carbon, midnight navy, and deep indigo as the base environment.
- Use glassy overlays for hero controls, player controls, metadata panels, and hovered media cards.
- Use thin borders only when they clarify separation.
- Avoid heavy shadows. Depth should come from tone, blur, transparency, scale, and artwork.

## Media Cards

- Poster radius should use the `poster` token.
- Cards should keep stable dimensions.
- Hover and focus states may add subtle scale, border strength, and accent glow.
- Text on cards should be minimal: title, metadata, quality, progress, or one key action.
- Do not cover artwork with large blocks of text unless the card is an intentional editorial tile.

## Interaction

- Focus states must be visible on dark surfaces.
- Hover should feel smooth and restrained.
- Primary actions may use the Streamly gradient.
- Secondary actions should use glassy or outline treatment.
- Motion should be responsive, cinematic, and purposeful.

## Accessibility

- Body text on dark surfaces should meet WCAG 2.1 AA where practical.
- Preserve a minimum 4.5:1 contrast ratio for body text and 3:1 for large text.
- Do not use accent colors for long-form text.
- Do not rely on glow alone to communicate state.

## Do Not Use

- Light mode by default.
- White dashboard shells.
- Generic SaaS sidebars and boxed KPI panels.
- Neon backgrounds.
- Heavy shadows and thick borders.
- Overcrowded toolbars.
- Decorative gradients that do not support content hierarchy.
