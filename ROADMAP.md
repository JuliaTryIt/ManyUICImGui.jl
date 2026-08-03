# ManyUICImGui.jl — Roadmap

ManyUICImGui is the Dear ImGui projection of ManyUI. Its goal is to run the
same widget tree, model, actions and reactive state as `ManyUITUI`,
`ManyUIWeb` WebTUI and WebNative, while using Dear ImGui for desktop rendering
and input. Dear ImGui is an implementation detail, not a second widget API.

## Definition of parity

An example reaches parity when, for the same model and viewport:

- the same widget tree and reactive values are used;
- the same canonical events are emitted: `on_click`, `on_change`, `on_submit`,
  `on_focus` and `on_blur`;
- keyboard, mouse, focus, resize and close behavior are equivalent;
- layout regions, clipping, overlays, modals and z-order are equivalent;
- colors, typography, transparency, themes and animations have equivalent
  semantic results (renderer-specific pixels may differ);
- the example can be tested through a deterministic headless driver.

The acceptance suite compares state transitions and normalized snapshots across
TUI, WebTUI, WebNative and ImGui. Screenshots are diagnostics, not the only
compatibility criterion.

## Phase 0 — Contracts and skeleton

- [x] Create the package, CI, TestItemRunner, Aqua, CompatHelper and TagBot.
- [ ] Add `ManyUIImGui`/`ImGuiBackend` implementing the public
  `ManyUITUI.Backend` contract (`make_driver`, `launch`, `isopen`, `close`,
  `wait`, `display_size`, `capabilities`).
- [ ] Choose and document the Dear ImGui Julia binding and supported window/
  renderer backends (GLFW/OpenGL first; SDL/Metal later if needed).
- [ ] Keep Dear ImGui imports optional at package load and provide a clear
  installation error when the selected renderer is unavailable.
- [ ] Define reversible conversion between ManyUI integer-cell regions and
  ImGui logical pixels for layout and hit testing.

## Phase 1 — Application lifecycle and viewport

- [ ] Open/destroy the native window and ImGui context safely on close,
  exceptions and `Ctrl-C`.
- [ ] Support `wait=false`, `isopen`, `close` and `wait` consistently with
  `ManyUIWeb.WebNativeServer` and `ManyUITUI.launch`.
- [ ] Handle HiDPI scale, framebuffer size, resize and minimize/restore.
- [ ] Provide a headless ImGui driver for CI and deterministic widget tests.
- [ ] Add a bounded frame scheduler and explicit invalidation for reactive
  changes and animations.

## Phase 2 — Layout, painting and widgets

- [ ] Project rows/columns, grow/shrink, padding, borders, clipping, scroll
  regions, z-order and minimum-size fallback.
- [ ] Implement labels, rich/static text, containers, separators,
  progress/spinner widgets and disabled states.
- [ ] Implement buttons, checkboxes, toggles, radio groups, dropdowns and
  sliders with hover/active/focused states.
- [ ] Implement text inputs and text areas, including selection, clipboard,
  password mode, multiline editing and IME-safe input.
- [ ] Implement lists, tables/data tables, tree views, tabs and scroll panes.
- [ ] Preserve Unicode graphemes, wide characters, emoji and font fallback.

## Phase 3 — Canonical events and focus

- [ ] Route pointer, keyboard, text-input and wheel events through the ManyUI
  dispatcher rather than widget-specific ImGui callbacks.
- [ ] Use `on_click` for buttons and `on_submit` for activation/confirmation.
- [ ] Emit automatic `on_change` for selections, toggles, sliders, tables,
  trees and text inputs when their value changes.
- [ ] Add root-level `on_focus` and `on_blur` for every `WidgetNode`.
- [ ] Match tab/shift-tab traversal, default focus, modal focus trapping,
  escape dismissal and click-outside behavior.
- [ ] Test keyboard-only and mouse-only interaction paths.

## Phase 4 — Themes, palettes and effects

- [ ] Introduce a backend-neutral theme/palette model with semantic roles
  (background, surface, text, accent, focus, disabled and error), typography
  and spacing tokens.
- [ ] Map that palette to TUI ANSI colors, WebNative CSS, WebTUI xterm colors
  and ImGui style colors.
- [ ] Support runtime theme switching, including the `Ctrl+T` modal.
- [ ] Implement alpha compositing and transparent modal/widget surfaces so the
  animated background remains visible.
- [ ] Add a shared animation clock/registry and the `Ctrl+B` animation modal,
  including deterministic pause/resume.
- [ ] Define integration points for TryIt, PhotoEffects.jl and
  PhotoDynamics.jl. Effects must work in every backend with documented GPU
  fallbacks.
- [ ] Verify pulse, rain, life and other animated demos against the Tachikoma
  reference for speed, phase, palette and resize behavior.

## Phase 5 — Overlays, dialogs and desktop UX

- [ ] Implement centered, transparent popups/modals with dimming, focus trap,
  escape and outside-click dismissal.
- [ ] Port About, Help, Theme and Animation as real modal windows.
- [ ] Match tooltips, context menus, notifications and nested popups.
- [ ] Add native clipboard, cursor shapes, drag-and-drop and file-dialog
  escape hatches without leaking platform APIs into ManyUI widgets.

## Phase 6 — Demos and verification

- [ ] Run `dashboard.jl`, `gallery.jl`, `datatable.jl`, `scrollpane.jl`,
  `unicode.jl`, `life.jl`, `rain.jl` and `snake.jl` unchanged through ImGui.
- [ ] Add a ManyUIDemos Hub entry and ImGui backend selector.
- [ ] Capture reference states at fixed viewport sizes and animation times.
- [ ] Add interaction scripts for click/change/submit, focus/blur, traversal,
  resize, modals and theme/animation switching.
- [ ] Run the same scenarios on TUI, WebTUI, WebNative and ImGui, reporting
  event/state/layout differences separately from renderer pixel differences.

## Phase 7 — Performance, packaging and release

- [ ] Benchmark a static screen, a large table and an animated background.
- [ ] Ensure a dirty widget redraw does not rebuild unrelated ImGui state.
- [ ] Document supported operating systems, GPU/window dependencies and
  headless CI setup.
- [ ] Add troubleshooting for HiDPI, fonts, clipboard and missing graphics
  libraries.
- [ ] Publish the first usable `0.1.x` release only after core widgets,
  canonical events, modals, themes and demo smoke tests meet the checklist.

## Non-goals for the first release

- Replacing ManyUI's retained widget/model API with an ImGui-only immediate API.
- Requiring every backend to expose Dear ImGui-specific flags or draw calls.
- Promising pixel-identical output between terminal cells, browser pixels and
  native desktop pixels.
- Adding docking, multi-viewport or custom GPU shaders before single-window
  parity is stable.
