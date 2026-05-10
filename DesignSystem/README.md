# Streamly Design System

Streamly Brand Book is the visual source of truth for all UI work in this project.

Use the files in `DesignSystem/Brand` before changing screens, components, motion, color, typography, spacing, logo usage, or visual tone. Product UI must stay dark-first unless a separate task explicitly requests a light interface.

## Structure

- `Brand/streamly-brandbook.md` - complete brand direction and usage rules.
- `Brand/streamly-design-tokens.json` - canonical color, gradient, radius, spacing, and typography tokens.
- `Brand/streamly-ui-principles.md` - practical UI rules for Streamly screens and components.
- `Brand/streamly-logo-usage.md` - logo lockups, clear space, sizing, and misuse rules.
- `Assets/Logo/` - approved logo assets.
- `References/` - exported visual reference pages from the approved brand book.

## Implementation Rule

When implementation tokens in `Sources/CineFlowDesignSystem` differ from `DesignSystem/Brand/streamly-design-tokens.json`, the JSON brand tokens win for new UI tasks. Existing Swift module names may remain `CineFlowDesignSystem`; the visual language should follow Streamly.
