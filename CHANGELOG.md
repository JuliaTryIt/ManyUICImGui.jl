# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `request_close!()`: ask the ImGui window currently rendering to close,
  reporting whether there was one. The native `launch_manyui` path
  projects widgets with no `App` behind them, so a callback that means
  "this window is done" -- the ManyUI hub's Launch button -- had nothing
  to `quit!` and no way to say so. Returns `false`, never throws, when
  the extension is asleep or no window is rendering, so a caller that
  runs every backend from one code path can call it unconditionally.

### Fixed

- Shape ligature clusters in the NATIVE widget path. `TextUnformatted`
  and `Selectable` draw codepoint by codepoint with no GSUB, so
  👨‍👩‍👧‍👦 came out as four separate faces and 🇫🇷 as the letters `F R`
  (and, on an atlas missing those codepoints, as the missing-glyph
  box). Each ligature cluster now goes through `RenderShapedText`
  while the rest of the line stays on the plain call.

  Two things had to be true for this to work. `RenderShapedText`
  renders NOTHING through a font whose fallbacks were MERGED in, so
  `_load_fonts!` now also keeps the emoji font as a separate, unmerged
  atlas entry used only for shaping. And a `Selectable` draws its own
  label, so a shaped one gets an empty visible label -- same id, same
  hit box -- with the text painted over it through the draw list,
  never by moving the ImGui cursor (which makes ImGui report
  "Code uses SetCursorPos() to extend window/parent boundaries" once
  per row and raise its error panel).

  Verified against framebuffer dumps of `demos/unicode.jl` in both
  modes rather than by eye.
- Close the window when the `App` stops. `launch_tui`'s draw callback
  always returned `nothing`, and the CImGui render loop ends only on
  `:imgui_exit_loop` or the OS close button -- so `quit!` (a Quit
  button, a demo's exit key, the hub's Launch button, which quits the
  hub so the demo can take the screen) stopped the App while the window
  stayed up painting a dead one. Every such click looked inert. The new
  `_tui_exit_signal` makes the decision, in `src` so it is testable
  without a GPU, and the callback returns it.
- Draw `Label` and `Static` again in the native widget path. Their
  `text[]` holds a `RichText`, which went straight to
  `CImGui.TextUnformatted` and raised
  `MethodError: no method matching unsafe_convert(::Type{Ptr{Int8}}, ::RichText)`
  on the first frame -- so every `cimgui` demo died the moment it drew
  its first label. The runs are now drawn one `TextUnformatted` each,
  `SameLine(0, 0)` between them, which keeps the per-run colour instead
  of flattening it away.
- Flatten `RichText` at the remaining C-string sites -- `List` and
  `TreeView` items, `Table` and `DataTable` cells, `TabStrip` captions.
  They used `string(...)`, and `RichText` defines no `show`, so a cell
  captioned "Ada" reached the window as
  `RichText(TextRun[TextRun("Ada", Style(...))])`.
- Render CJK and emoji in the native widget path. `_load_fonts!` added
  the fallbacks as separate atlas fonts, which suits the TUI painter
  (it picks one per grapheme) but left them unreachable to
  `TextUnformatted`, so 漢字 drew as tofu. `launch_manyui` now asks for
  `merge_fallbacks`, merging them into the primary as Dear ImGui
  intends.
- Render the `Spinner`. Its default frames are Braille (⠋⠙⠹…), a range
  no monospace candidate carries and the atlas did not request, so the
  one glyph on screen meant to be animating was a tofu box. A symbol
  fallback (Apple Symbols / DejaVu Sans / Segoe UI Symbol) is now
  merged into the primary, covering U+2800..U+28FF in both the native
  and the TUI path.
- Stop throwing inside the render loop on a libcimgui without FreeType.
  The shaping guard tested `isdefined(CImGui, :HasShaping)`, which asks
  about the Julia binding -- always defined by the generated wrapper --
  so `HasShaping()` was reached and failed to resolve its C symbol. The
  guard is now `_has_freetype()`, which probes the symbol itself, and
  the absent FreeType loader is reported once with `@warn` rather than
  left to be inferred from tofu. Colour emoji remain unavailable on
  such a build; see `upstream-bugs.md`.

- Fix atlas fallback-font retrieval so CJK / emoji cells route to the
  right font. The previous code read `ImVector<ImFont*>` with
  `getproperty(fonts, :Size)` on `Ptr{ImFontAtlas}` (no such field) and
  `struct + int` (a Julia struct is not a pointer), which threw and was
  swallowed by the surrounding `try/catch` -- so `cjk_font` stayed
  `C_NULL` and every exotic cluster fell through to the `□` placeholder.
  The vector is now read correctly (`fv.Size` + `fv.Data` + offset
  indexing), and the primary / CJK / emoji fonts are recovered by atlas
  index.
- Bake proper glyph ranges into the ImGui font atlas so non-ASCII
  cells actually rasterize. Previously `_load_fonts!` passed `C_NULL`
  for `glyph_ranges`, so the atlas baked only the default ASCII +
  Latin-1 set and `AddText` rendered nothing for CJK ideographs
  (漢字), kana (か), fullwidth Latin (ｆ) and combining-mark clusters
  (e + U+0301). The primary monospace font now bakes Latin Extended,
  combining diacriticals, Greek, Cyrillic, general punctuation, box
  drawing and geometric shapes; the CJK fallback bakes CJK symbols,
  Hiragana, Katakana, CJK unified ideographs (incl. Extension A),
  fullwidth forms and BMP symbol/dingbat bases (❤, ☝). The emoji
  fallback bakes the SMP emoji ranges (Emoticons, Regional Indicators,
  Misc/Transport/Supplemental Symbols, VS16, ZWJ) as `UInt32`.
- Strip variation selectors (U+FE00..U+FE0F) before both the HarfBuzz
  coverage check and `AddText`. Without this, `_hb_full_coverage("❤️")`
  returned false (the emoji font has no VS16 glyph) and the whole
  cluster routed to `□`; VS16 also forced the emoji font over the
  primary monospace one so ❤️/☝️ render in color, not Menlo's
  monochrome outline (Menlo carries U+2764).

### Added

- Portable font discovery: macOS / Linux / Windows candidate paths
  (plus `~/Library/Fonts`, `~/.fonts` via `expanduser`); no hardcoded
  user paths. Twemoji Mozilla COLRv0 is the preferred color-emoji
  font (FreeType auto-rasterizes COLRv0 to BGRA at any pixel size,
  unlike COLRv1 / Noto Color Emoji).
- Color-emoji rendering for single-codepoint clusters (😀 ❤️ ☝️).
  Requires a `libcimgui` built with `IMGUI_ENABLE_FREETYPE` +
  `IMGUI_USE_WCHAR32` (32-bit `ImWchar` for SMP) -- see
  `docs/src/upstream-emoji-shaping.md` for the upstream build
  strategy. With the stock `CImGui.jl` (stb, `ImWchar16`) SMP emoji
  still render as the `□` placeholder.
- Shaping seam for GSUB ligatures (ZWJ families 👨‍👩‍👧‍👦,
  regional-indicator flags 🇫🇷): ligature clusters call
  `CImGui.RenderShapedText` when `CImGui.HasShaping()` (a
  `libcimgui` built with `IMGUI_ENABLE_HARFBUZZ_SHAPING`), otherwise
  fall back to `AddText` (components). `HarfBuzz` is now a weakdep.
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
