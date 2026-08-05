# Upstream strategy — Emoji support (CJK + color + shaping) in CImGui.jl

This document summarizes the local work that made exotic characters (CJK,
color emoji, ZWJ ligatures / regional-indicator flags) render correctly in
the TUI cell-grid renderer of ManyUICImGui, and the strategy for pushing
the changes upstream so they ship in standard CImGui.jl builds (without a
local override).

## 1. Context

`ManyUICImGui` rasterizes ManyUI's TUI buffer into a Dear ImGui window via
`ImDrawList::AddText`, one cell at a time. The `unicode.jl` demo exercises
every edge case: CJK (漢字 か ｆ), combining marks (e + U+0301),
single-codepoint emoji (😀 ❤️ ☝️), ZWJ ligatures (👨‍👩‍👧‍👦) and
regional-indicator flags (🇫🇷).

Before this work **nothing rendered correctly** (□ everywhere), for several
nested reasons that were discovered and fixed one at a time.

## 2. Root causes identified

| # | Cause | Layer | Symptom |
|---|---|---|---|
| R1 | Atlas fallback-font retrieval was broken (`getproperty(fonts,:Size)` on `Ptr{ImFontAtlas}` + `struct + int` → `try/catch` swallowed the error → `cjk_font` always `C_NULL`) | **ManyUICImGui** | CJK → □ |
| R2 | No CJK / combining-mark glyphs baked into the atlas (`AddFontFromFileTTF(..., C_NULL)` → default ASCII+Latin-1 range only) | **ManyUICImGui** | CJK / combining → blank |
| R3 | `libcimgui` (CImGuiPack_jll) built with the **stb_truetype** rasterizer and `ImWchar = ImWchar16` (16-bit) → **no codepoint > U+FFFF can be baked** (😀, 👨‍👩‍👧‍👦, 🇫🇷) | **cimgui-pack / Yggdrasil** | SMP emoji → impossible |
| R4 | `imgui_freetype.cpp` renders color glyphs with `FT_Render_Glyph(slot, FT_RENDER_MODE_NORMAL)` → for **COLR** glyphs (pure color, no outline) the bitmap is **empty** | **ocornut/imgui** | color emoji (Twemoji COLRv0) → blank |
| R5 | ImGui's `RenderText` is **codepoint-by-codepoint**, no GSUB shaping → ligatures (ZWJ families, regional-indicator flags) render as **components** | **ocornut/imgui** | 👨‍👩‍👧‍👦 → 4 people, 🇫🇷 → "FR" |
| R6 | Apple Color Emoji is a **bitmap-only (sbix) font with fixed sizes** → `FT_Set_Char_Size` fails; `HarfBuzz.HbFont` cannot load it | **system fonts** | Apple emoji → blank/garbage |
| R7 | Noto Color Emoji **COLRv1** is not auto-rasterized by FreeType 2.13 (the paint graph must be walked by the app) | **FreeType** | Noto COLRv1 → blank |

## 3. Changes made (local validation)

### 3.1 ManyUICImGui (local commit, shippable)

- **Fix R1**: correct retrieval of the atlas `ImVector<ImFont*>`
  (`fv.Size` + `fv.Data` + offset indexing by `sizeof(Ptr{Cvoid})`).
- **Fix R2**: explicit glyph ranges (cross-platform), as `UInt32`:
  `_MONO_GLYPH_RANGES` (Latin Extended, combining diacriticals, Greek,
  Cyrillic, punctuation, box-drawing, geometric shapes □),
  `_CJK_GLYPH_RANGES` (Hiragana/Katakana/CJK unified ideographs/fullwidth/VS),
  `_EMOJI_GLYPH_RANGES` (SMP: Emoticons, Regional Indicators, Misc Symbols,
  Transport, Supplemental, etc. + VS16 + ZWJ).
- **Portable font discovery**: macOS + Linux + Windows path lists (plus
  `~/Library/Fonts`, `~/.fonts` via `expanduser`); no hardcoded user path.
  Twemoji COLRv0 preferred for color emoji.
- **Per-cell routing** in `_paint_buffer!`:
  - HarfBuzz coverage (`_hb_full_coverage` = `HarfBuzz.shape` + all
    `glyph_id != 0`) on primary/cjk/emoji, `IsGlyphInFont` fallback.
  - **VS16 stripped** before both the coverage check and rendering
    (otherwise `_hb_full_coverage("❤️")` returns false because VS16 is
    missing → □).
  - **VS16 forces the emoji font** (`want_emoji_presentation`) — otherwise
    ❤ routes to Menlo (which has the codepoint as a monochrome outline)
    instead of the color Twemoji.
  - **ligatures** (ZWJ / regional-indicator pair) →
    `CImGui.RenderShapedText` when `CImGui.HasShaping()`, else `AddText`
    fallback (components).
- `Project.toml`: `HarfBuzz` added to weakdeps/extensions.

### 3.2 cimgui-pack (local patch, to upstream)

- `CMakeLists.txt`: `CIMGUI_ENABLE_FREETYPE` option that adds
  `imgui_freetype.cpp` + defines `IMGUI_ENABLE_FREETYPE`,
  `IMGUI_ENABLE_STB_TRUETYPE` (the cimgui wrapper references the stb
  loader), `IMGUI_USE_WCHAR32` (ImWchar 32-bit → SMP). Links FreeType.
- Optional **HarfBuzz** linkage + `IMGUI_ENABLE_HARFBUZZ_SHAPING` when
  HarfBuzz is found.

### 3.3 imgui_freetype.cpp (local patch, upstream imgui PR)

- **Fix R4**: when `LoadColor` is set, add `FT_LOAD_RENDER` to the
  `LoadFlags` (auto-render the color bitmap during `FT_Load_Glyph`), and
  skip `FT_Render_Glyph(NORMAL)` when `slot->format ==
  FT_GLYPH_FORMAT_BITMAP`. Otherwise COLR glyphs render blank.
- **Fix R5**: `ImGui_ImplFreeType_BakeGlyphByID` (bake a glyph by its **FT
  glyph index**, with a `ShapedGlyphs` + `ShapedGlyphsByGlyphID` cache in
  `FontSrcBakedData`) + `ImGuiFreeType::RenderShapedText` (HarfBuzz
  `hb_shape` → glyph IDs + advances → on-demand bake-by-ID → quad render +
  texture-change retry like `RenderText`). An `hb_font_t*` per face
  (`hb_ft_font_create` in `InitFont`, destroyed in `CloseFont`). All guarded
  by `#if defined(IMGUI_ENABLE_HARFBUZZ_SHAPING)`.

### 3.4 cimgui.cpp/h (local patch)

- C wrappers: `ImGuiFreeType_RenderShapedText`, `ImGuiFreeType_HasShaping`.

### 3.5 CImGui.jl (local override)

- `const ImWchar = Cuint` (32-bit, in `lib/aarch64-apple-darwin20.jl`).
- Wrapper regenerated via `gen/generator.jl` with
  `-DIMGUI_ENABLE_FREETYPE -DIMGUI_USE_WCHAR32` (32-bit struct offsets).
- Manual Julia wrappers: `RenderShapedText`, `HasShaping`.

### 3.6 Local validation (macOS arm64)

- cimgui rebuilt with FreeType + IMGUI_USE_WCHAR32 + HarfBuzz (HarfBuzz_jll
  8.5.1; rpaths baked for glib/intl/pcre2/bz2/png/graphite2/freetype/glfw).
- `CImGuiPack_jll` override via the `override/` folder (JLLWrappers) +
  ad-hoc re-sign (`codesign --force --sign -`).
- Emoji font: **Twemoji Mozilla COLRv0** (`~/Library/Fonts/TwemojiCOLR.ttf`).
- **`unicode.jl` demo result**: `a é é 漢字か ｆ` + `❤️ ☝️ 😀` (color) +
  `👨‍👩‍👧‍👦` (one family ligature) + `🇫🇷` (one flag ligature) →
  **everything renders correctly**.

## 4. Upstream strategy

The goal is for standard CImGui.jl builds to support all this without a
local override. PRs are ordered bottom-up by dependency.

### Step 1 — `ocornut/imgui`: `imgui_freetype.cpp`

**PR A1 — BGRA color rendering** (fix R4):
- Add `FT_LOAD_RENDER` to `LoadFlags` when `LoadColor`, skip
  `FT_Render_Glyph` if already a bitmap.
- Minimal impact, no change for monochrome fonts.
- Rationale: COLR/sbix color glyphs are otherwise blank.

**PR A2 — HarfBuzz shaping** (fix R5):
- `ImGuiFreeType::RenderShapedText` + `BakeGlyphByID` + cache, guarded by
  `IMGUI_ENABLE_HARFBUZZ_SHAPING`.
- Opt-in API (does not modify the existing `RenderText`) → low risk, a base
  for shaping in custom renderers.
- Open a discussion on the imgui side (text shaping has been requested for
  years; this PR brings an opt-in API without touching the hot path).

### Step 2 — `JuliaImGui/cimgui-pack`: `CMakeLists.txt`

**PR B**: `CIMGUI_ENABLE_FREETYPE` option (+ `IMGUI_USE_WCHAR32` +
`IMGUI_ENABLE_STB_TRUETYPE`) + optional HarfBuzz linkage +
`IMGUI_ENABLE_HARFBUZZ_SHAPING`. cimgui wrappers
(`ImGuiFreeType_RenderShapedText`, `HasShaping`).

### Step 3 — `JuliaPackaging/Yggdrasil`: `C/CImGuiPack/build_tarballs.jl`

**PR C**: add `Dependency("FreeType2_jll")` +
`Dependency("HarfBuzz_jll")`, pass `-DCIMGUI_ENABLE_FREETYPE=ON`, bump
`CImGuiPack_jll` version. BinaryBuilder CI produces a new artifact with
FreeType + ImWchar32 + HarfBuzz (LIBPATH handled by JLLWrappers, artifacts
pinned — no more graphite2/GC issues).

> ⚠️ The current `HarfBuzz_jll` depends on glib+graphite2; it works via the
> JLL LIBPATHs but bloats the dependency tree. Alternative: produce a
> `HarfBuzzMinimal_jll` (HarfBuzz built `-DHB_HAVE_GLIB=OFF
> -DHB_HAVE_GRAPHITE2=OFF`, depending only on FreeType). To evaluate on
> the Yggdrasil side.

### Step 4 — `JuliaImGui/CImGui.jl`: wrapper

**PR D**: regenerate the wrapper (`gen/generator.jl` with
`-DIMGUI_ENABLE_FREETYPE -DIMGUI_USE_WCHAR32`), bump `CImGuiPack_jll`
compat, manual wrappers `RenderShapedText` + `HasShaping` (or automatic
regeneration if the generator JSON includes them).

### Step 5 — `ManyUI` / `ManyUICImGui` (our repos)

**Commit E** (locally ready): atlas retrieval fix (R1), glyph ranges,
portable font discovery, HarfBuzz/VS16/shaping routing, `HarfBuzz` as a
weakdep. Shippable once CImGui.jl has steps C+D; in the meantime, `AddText`
fallback (components) via `HasShaping()`.

## 5. Recommendations

- Start with **PR A1** (color rendering) — simple, independent, big win
  (single-codepoint color emoji).
- **PR A2** (shaping) in parallel on the imgui side: the discussion will
  be long (shaping is a historical topic). The opt-in `RenderShapedText`
  API is an acceptable compromise that does not commit the `RenderText` hot
  path.
- **PR C** (Yggdrasil) can land with A1 alone (FreeType+ImWchar32) to
  unblock CJK+SMP color emoji, without waiting for A2.
- Document the **Noto COLRv1** limitation (FreeType 2.13 does not
  auto-rasterize COLRv1) → recommend **Twemoji COLRv0** as the portable
  color emoji font for ImGui.

## 6. Known residual limitations

- **Noto Color Emoji COLRv1**: renders blank (FreeType does not
  auto-rasterize COLRv1). Use Twemoji COLRv0 (COLRv0) or a COLRv0 outline
  color emoji font.
- **Bitmap-only emoji** (Apple Color Emoji sbix, Noto Color Emoji CBDT):
  `FT_Set_Char_Size` fails; rendering via ImGui is partial/unpredictable.
  Prefer Twemoji COLRv0.
- **`graphite2` / `glib`**: the standard HarfBuzz_jll pulls glib+graphite2.
  A HarfBuzzMinimal_jll (built without glib/graphite2) would slim the tree.
- The current shaping is **opt-in** (`RenderShapedText`), not integrated
  into ImGui's standard `RenderText` → only benefits renderers that call
  it explicitly (ours). Integrating it into the hot path is a future
  upstream evolution.