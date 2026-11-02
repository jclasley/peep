---
name: sprite-preview
description: Preview a new Peep skin before writing Swift. Renders 3 animated style variants of the requested sprite in an inline widget so the user can pick one. Use when the user asks for a new buddy, skin or sprite, asks to "preview" one, or asks for tweaks to a skin still in preview.
---

# Sprite preview

Design in a widget first, write Swift only after the user picks. Read "Adding a skin" in `CLAUDE.md` and the existing skins in `Sources/Peep/Sprites.swift` for the style.

## Steps

1. Read `harness.js` (next to this file). Paste it unchanged into the widget's `<script>`. It ports `Px`, `face`, `outlined()` and the self-check edge rule, so the preview matches the app.
2. Write 3 variants that differ in style, not just color (for example: classic shape, chubby/rounded with lights, snowy with an overlay). Each is `{ name, draw(a, t, bl), overlay?(a, t) }`, using the same calls as Swift (`a.r`, `a.e`, `a.p`, `a.face`, `a.empty`). Then call `run(skins)`.
3. Show them with `show_widget` using the layout below. Ask which one with `AskUserQuestion` (one option per variant).
4. When the user asks for tweaks, show the preview again with just the chosen variant. Repeat until they approve it.
5. Port the chosen variant to Swift in `skins`, then run `swift format --in-place --recursive Sources` and `swift run Peep --check` (outside the sandbox: SwiftPM's own sandbox fails inside it). It must print `ok`.

## Layout

```html
<h2 class="sr-only">Three animated previews of ...</h2>
<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:16px;padding:1rem 0">
  <!-- repeat for i = 0..2 -->
  <div><canvas id="c0" width="192" height="192" style="image-rendering:pixelated;background:var(--surface-1);border-radius:12px;width:100%;max-width:192px"></canvas>
    <p style="margin:6px 0 0;font-size:14px;font-weight:500">A · Name</p>
    <p style="margin:0;font-size:13px;color:var(--text-secondary)">Two-word summary</p>
    <p id="w0" style="margin:0;font-size:13px;color:var(--text-danger)"></p></div>
</div>
<div style="display:flex;gap:16px;align-items:flex-end">
  <canvas id="s0" width="64" height="64" style="image-rendering:pixelated;background:var(--surface-1);border-radius:8px"></canvas>
  <!-- s1, s2 -->
  <span style="font-size:13px;color:var(--text-secondary)">Near real size</span>
</div>
```

## Lessons from earlier previews

- **Edge rule:** the outline adds 2 rings, so body pixels must stay in rows/columns 3–28. Ellipses include their boundary pixel, so `cy - ry` must be more than 2.5 (a pompom at `e(25.5, 5.5, 3, 3)` failed; `cy = 6` passed). The `w<i>` line shows a warning when a variant breaks this rule.
- **Avoid scattered pixels:** single-pixel shading, small highlight specks and tiny multi-color details (such as holly on a brim) read as noise at 32×32. Use solid areas.
- **Separate overlapping white shapes:** when a white shape sits on the body (such as a pompom on a hat), draw a dark ring where they overlap. Draw a `Col.k` ellipse 0.8 px larger first, draw the shape on top, then clear the ring pixels outside the body so the outline pass draws them there.
- **Cute style:** use rounded shapes (`sqrt` widening for cones), taller eyes (`eh: 4`), rosy cheeks, one small motion (bobbing, blinking baubles) and maybe a twinkle in `overlay`.
- **Center:** the center line is between columns 15 and 16. Draw symmetric rows with `a.r(16 - hw, y, 2 * hw, 1, c)`.
- **Swift port:** the code maps 1:1. `Math.round` becomes `.rounded()`, and `t >> 3` must be wrapped in brackets in additions (`i + (t >> 3)`).
