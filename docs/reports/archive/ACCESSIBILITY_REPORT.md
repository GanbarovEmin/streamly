# Accessibility And Keyboard UX Report

## Scope
- Reviewed sidebar, global search, carousels, tabs, settings, detail release rails and player controls.
- Changes stay presentation-only except for respecting the existing persisted Reduce Motion setting.
- Local-first behavior is unchanged: no telemetry, no remote accessibility service, no source credentials in UI code.

## Keyboard Navigation
- Sidebar supports arrow-key movement and keeps visible focus on rows.
- Global search can be focused through `Cmd+L`; Search screen remains reachable through `Cmd+F`.
- Settings remain reachable through `Cmd+,`.
- Player controls keep keyboard shortcuts for Space, Esc, arrows, `A`, `S`, and `F`.
- Cards, release rows, tabs, dock actions and icon buttons expose visible focus rings.

## Focus States
- Shared `cfFocusRing` now uses a stronger two-layer outline so keyboard focus is visible on dark graphite surfaces.
- Primary, secondary and icon buttons retain hover/pressed feedback while disabling scale motion when Reduce Motion is enabled.
- Sidebar rows, tabs, poster cards, landscape cards and release rows expose focus states through shared tokens.

## Accessibility Labels
- Buttons expose labels and tooltips from their visible title or localized control name.
- Poster and landscape cards combine title, metadata and badge into one accessibility label.
- Release rows expose title, provider, quality, size and seeders.
- Player controls are localized and labeled: rewind, play/pause, forward, mute, volume, audio, subtitles, speed, PiP, fullscreen and exit.
- Settings toggles expose title and subtitle as label/hint.

## Reduce Motion
- Added `cfReduceMotion` environment support in the design system.
- The app combines macOS `accessibilityReduceMotion` with Streamly Settings -> Appearance -> Reduce motion.
- Route transitions, button/card scale, hover glow and image transition animations are reduced when enabled.

## Tooltips
- Existing tooltips for ranking, seeders, cache, diagnostics and Sparkle updates are preserved.
- Added help text to buttons, media cards, sidebar rows, search field, settings toggles and player menus.

## QA Checklist
- Navigate the sidebar with keyboard focus and up/down arrows.
- Press `Cmd+L`, type a query, press Return, then tab through Search filters and results.
- Tab through Home carousels and verify poster card focus is visible.
- Tab through Movie/Series detail tabs, dock actions and release rails.
- Use Player shortcuts: Space, left/right arrows, up arrow, `A`, `S`, `F`, Esc.
- Enable macOS Reduce Motion and Streamly Reduce motion; verify route/card/button animations are calmer.
- Run VoiceOver spot checks on poster cards, release rows, settings toggles and playback controls.
