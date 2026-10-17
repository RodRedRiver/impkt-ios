# Light Liquid Glass Train Screen

## Goal
Rebuild only the main Train screen as an Apple-inspired, all-white experience while keeping every existing action and saved preference working.

## Visual direction
- Replace the dark background with a luminous white-to-pearl surface and subtle cool-white moving light.
- Replace the dark fist artwork with a coordinated silver-white illuminated boxing visual so the centerpiece belongs in the light composition.
- Use layered translucent white glass, strong blur, fine highlights, soft inner light, and restrained grey shadows for the connection status, action rows, dialogs, and primary action.
- Keep text highly legible in graphite and soft grey; reserve a tiny crimson status accent rather than letting color dominate.
- Restyle the oversized TRAIN title with crisp metallic silver-white depth and generous, non-negative character spacing.
- Make the bottom tab bar on this screen a floating white glass control with clear active state.

## Interaction preserved
- Bluetooth pairing, disconnect, and demo-mode fallback.
- Settings popup, body mass, glove weight, and device management.
- Workout picker and persisted workout choice.
- Goal editor and persisted targets.
- Last-session review and link to the full summary.
- Start Session popup with Rounds and Open Session choices.
- All four bottom tabs and their active states.

## Accessibility and quality
- Preserve larger-text settings and both system/manual reduced-motion behavior.
- Keep touch targets comfortable, dialogs dismissible, labels clear, and focus states visible.
- Verify the Train screen at mobile and desktop sizes, exercise every popup, and check for overlap or browser errors.

## Technical details
- Update the Train route styling and its local dialog/field presentation without changing its data or pairing logic.
- Add semantic light-glass tokens/utilities to the global design system rather than scattering hardcoded colors through the screen.
- Apply a Train-only light treatment to the shared bottom navigation so other screens keep their current themes.
