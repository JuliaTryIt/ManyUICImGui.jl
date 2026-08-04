# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Bake proper glyph ranges into the ImGui font atlas so non-ASCII
  cells actually rasterize. Previously `_load_fonts!` passed `C_NULL`
  for `glyph_ranges`, so the atlas baked only the default ASCII +
  Latin-1 set and `AddText` rendered nothing for CJK ideographs
  (漢字), kana (か), fullwidth Latin (ｆ) and combining-mark clusters
  (e + U+0301). The primary monospace font now bakes Latin Extended,
  combining diacriticals, Greek, Cyrillic, general punctuation, box
  drawing and geometric shapes; the CJK fallback bakes CJK symbols,
  Hiragana, Katakana, CJK unified ideographs (incl. Extension A),
  fullwidth forms and BMP symbol/dingbat bases (❤, ☝). Color emoji
  above U+FFFF (😀, 👨‍👩‍👧‍👦, 🇫🇷) cannot be baked because `ImWchar`
  is 16-bit; those clusters render as the `□` placeholder.

### Added

- HarfBuzz text shaping is now used for per-cell font fallback in the
  `ImGuiTUIBackend` cell-grid renderer. A `Cell`'s whole `content`
  (a grapheme cluster, possibly a base codepoint plus combining marks
  or a ligature sequence such as a regional indicator pair) is shaped
  via `HarfBuzz.shape`, and a font is selected only when every shaped
  glyph is present (non-zero glyph ID). This supersedes the previous
  single-codepoint `has_glyph` check, which incorrectly accepted a
  font that had the base codepoint but lacked a combining mark, and
  ignored GSUB ligature formation. `has_glyph` / `IsGlyphInFont` remain
  as a fallback when HarfBuzz fonts are not loaded.
- Initial package scaffold for a future Dear ImGui backend for ManyUI.
- Headless `ImGuiBackend`/`ImGuiDriver` lifecycle, viewport, resize and event
  seam conforming to the ManyUITUI driver contract.
- Optional CImGui/GLFW/OpenGL3 extension exposing the native window render-loop
  seam without making graphical dependencies mandatory for headless CI.
- Initial native projection for `Container`, `Label`, `Static` and `Button`.
- Actionable optional-dependency detection through `native_available()`.
- `ImGuiTUIBackend` / `ImGuiTUIDriver`: a TUI-in-ImGui backend that runs the
  SAME `App` pipeline a terminal runs (`frame!` paints `app.back`, a `Buffer`
  of `Cell`s) and renders the cell grid with `ImDrawList` at a fixed monospace
  cell pitch. This fixes every terminal-style demo at once: DataTable header
  sorting, Unicode grapheme widths (CJK/emoji = 2 cells, combining marks = 0),
  and ASCII-art capabilities tables.
- `ManyUICImGui.launch_tui(factory; ...)`: launch a ManyUI widget factory
  inside a Dear ImGui window using the TUI cell-grid renderer.
- `ManyUICImGui.launch_tui_app!(app; on_tick, tick_interval)`: run an
  already-built `App` (constructed with an `ImGuiTUIDriver`) inside ImGui, for
  animated demos that tick from a timer.
- ImGui mouse / keyboard event translation: `ImGuiMouseButton_*` ->
  `ManyUI.MouseEvent`, `ImGuiKey_*` -> `ManyUI.KeyEvent`, `InputQueueCharacters`
  (UTF-16 surrogate pairs decoded) -> `ManyUI.Key.CHAR`, wheel deltas ->
  `ManyUI.MouseButton.WHEEL_*`.
- ManyUIDemos Hub: `--backend` flag to launch the hub itself with any backend
  (`tui`, `web`, `webtui`, `cimgui`, `cimguitui`); explicit "flux utilisateur"
  messages telling the user where interaction continues (browser, console,
  CImGui window).
