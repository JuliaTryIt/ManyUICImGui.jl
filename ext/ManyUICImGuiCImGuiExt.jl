module ManyUICImGuiCImGuiExt

using ManyUICImGui
import CImGui
import GLFW
import ModernGL
import ManyUI
import ManyUITUI
import HarfBuzz

function __init__()
    ManyUICImGui._NATIVE_AVAILABLE[] = true
    ManyUICImGui._TUI_NATIVE_AVAILABLE[] = true
    ManyUICImGui._CLOSE_REQUESTER[] = _request_close!
end

"""
True when the loaded `libcimgui` was built with `IMGUI_ENABLE_FREETYPE`.

Everything colour or bitmap in a font depends on this, and it is NOT a
given: CImGuiPack_jll 0.12.2 ships a plain stb_truetype build, whose
rasteriser cannot see COLR layers or sbix/CBDT bitmap strikes. On that
binary colour emoji are unreachable no matter which font is installed.

Detected by SYMBOL rather than by jll version, since a later jll may
flip either way: `ImGuiFreeType_GetFontLoader` is bound in CImGui.jl's
generated wrapper but exported only by a FreeType build, so the `ccall`
fails to resolve on a stb one. Resolved ONCE and cached -- the answer
cannot change while the library is loaded.
"""
const _HAS_FREETYPE = Ref{Union{Nothing,Bool}}(nothing)

function _has_freetype()::Bool
    v = _HAS_FREETYPE[]
    v === nothing || return v
    ok = try
        CImGui.lib.ImGuiFreeType_GetFontLoader() != C_NULL
    catch
        # "could not load symbol" on a build without FreeType.
        false
    end
    _HAS_FREETYPE[] = ok
    return ok
end

"""
    ManyUICImGui.launch_imgui(ui; width=1280, height=720, title="ManyUI")

Run a native GLFW/OpenGL3 Dear ImGui render function. This is the native
window seam only; widget projection is layered on top in the next phase.
With `wait=false`, return the CImGui render task instead of blocking.
"""
function ManyUICImGui.launch_imgui(ui::Function;
                                   width::Integer=1280,
                                   height::Integer=720,
                                   title::AbstractString="ManyUI",
                                   wait::Bool=true,
                                   merge_fallbacks::Bool=false)
    width > 0 || throw(ArgumentError("width must be positive"))
    height > 0 || throw(ArgumentError("height must be positive"))
    CImGui.set_backend(:GlfwOpenGL3)
    ctx = CImGui.CreateContext()

    # Load fonts: a monospace primary (Menlo) for ASCII/box-drawing, and
    # a CJK fallback (Hiragino Sans GB) for 漢字か. `merge_fallbacks`
    # says whether the caller selects a font per glyph itself (the TUI
    # path, `_paint_buffer!`) or needs one font that covers everything
    # (the native widget path). See `_load_fonts!`.
    _fonts = _load_fonts!(ctx; merge_fallbacks = merge_fallbacks)

    spawn = wait ? false : 1
    CImGui.render(ui, ctx; window_size=(Int(width), Int(height)),
                  window_title=String(title), spawn=spawn, wait=wait)
end

# Candidate monospace TTF/TTC paths, in priority order. The first that
# exists wins. TTC (TrueType Collection) files are handled by ImGui's
# font loader as of the FreeType backend.
mutable struct _FontPair
    primary::Ptr{CImGui.lib.ImFont}    # Menlo: monospace, box-drawing, symbols
    cjk::Ptr{CImGui.lib.ImFont}        # Hiragino: CJK ideographs, kana
    emoji::Ptr{CImGui.lib.ImFont}      # Apple Color Emoji: color emoji >U+FFFF
end

# Cross-platform font discovery. We try well-known absolute font paths
# covering macOS, Linux and Windows. The lists are ordered by preference;
# the first file that exists and loads wins. No path is specific to a
# single user's machine -- every entry is a system font location on at
# least one OS, so this is portable across the three platforms.

const _MONO_FONT_CANDIDATES = String[
    # macOS
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/Monaco.ttf",
    "/System/Library/Fonts/Courier.ttc",
    # Linux
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
    "/usr/share/fonts/noto/NotoSansMono-Regular.ttf",
    "/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf",
    # Windows
    "C:/Windows/Fonts/consola.ttf",
    "C:/Windows/Fonts/cour.ttf",
]

# Monochrome SYMBOL coverage: the parts of the BMP a monospace face
# tends not to carry. Braille Patterns above all -- `Spinner`'s default
# frames are ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏ and Menlo has no Braille, so the one glyph on
# screen that is supposed to be animating was a tofu box.
#
# These are ordinary outline glyphs, so they bake through the plain
# stb_truetype loader; unlike the emoji list below, this one does not
# depend on a FreeType-enabled libcimgui.
const _SYMBOL_FONT_CANDIDATES = String[
    # macOS
    "/System/Library/Fonts/Apple Symbols.ttf",
    # Linux -- DejaVu Sans and Noto Symbols2 both carry U+2800..U+28FF.
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf",
    "/usr/share/fonts/noto/NotoSansSymbols2-Regular.ttf",
    # Windows -- Segoe UI Symbol.
    "C:/Windows/Fonts/seguisym.ttf",
]

const _CJK_FONT_CANDIDATES = String[
    # macOS
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
    "/System/Library/Fonts/PingFang.ttc",
    # Linux
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/droid/DroidSansFallback.ttf",
    # Windows
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/simsun.ttc",
]

# COLOR EMOJI NEEDS A FREETYPE-ENABLED libcimgui, AND CImGuiPack_jll
# 0.12.2 IS NOT ONE. Every path below assumes the FreeType loader; on a
# stb_truetype build none of them can produce a glyph, because the art
# in a COLR font lives in layers stb cannot see and the art in an sbix /
# CBDT font is a bitmap stb cannot read. The shipped binary answers
# plainly when asked -- it carries ImGui's own
#
#     "Requires #define IMGUI_ENABLE_FREETYPE + imgui_freetype.cpp."
#
# and exports no FreeType symbol at all. `native_emoji_available()`
# below is the runtime form of that check.
#
# So on the current binary emoji draw as tofu boxes and no font choice
# changes it. The list is kept in preference order for the build that
# does have FreeType. See upstream-bugs.md.
const _EMOJI_FONT_CANDIDATES = String[
    # COLRv0 outline color emoji (preferred) -- FreeType auto-rasterizes
    # COLRv0 to a BGRA bitmap at any pixel size, so ImGui bakes it at 18px
    # and HarfBuzz.jl can load it (FT_Set_Char_Size succeeds) for ligature
    # shaping. Twemoji Mozilla (COLRv0) is the reliable cross-platform
    # choice. Install TwemojiMozillaCOLR.ttf in /Library/Fonts (macOS),
    # /usr/share/fonts/truetype/twemoji (Linux) or %WINDIR%\Fonts (Windows).
    "/Library/Fonts/TwemojiMozillaCOLR.ttf",
    "/Library/Fonts/Twemoji.Mozilla.ttf",
    "~/Library/Fonts/TwemojiMozillaCOLR.ttf",
    "~/Library/Fonts/Twemoji.Mozilla.ttf",
    "~/Library/Fonts/TwemojiCOLR.ttf",
    "/usr/share/fonts/truetype/twemoji/TwemojiMozillaCOLR.ttf",
    "/usr/share/fonts/twemoji/TwemojiMozillaCOLR.ttf",
    "~/.local/share/fonts/TwemojiMozillaCOLR.ttf",
    "~/.fonts/TwemojiMozillaCOLR.ttf",
    "C:/Windows/Fonts/TwemojiMozillaCOLR.ttf",
    # Bitmap-only color emoji (last resort): FT_Set_Pixel_Sizes fails for
    # bitmap-only fonts and SMP codepoints render empty through ImGui's
    # FreeType loader, so single-codepoint BMP emoji may render but
    # 😀/👨‍👩‍👧‍👦/🇫🇷 will not.
    "/System/Library/Fonts/Apple Color Emoji.ttc",
    "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
    "C:/Windows/Fonts/seguisym.ttf",
]

# Return the first existing path from `paths` (after `expanduser`), or
# `nothing`. Used to resolve a HarfBuzz `Font` from the same candidate list
# the atlas `_add_first_font` walks, so the HarfBuzz coverage font matches
# the atlas font (HarfBuzz.jl dropped family-name resolution).
function _first_existing_path(paths::AbstractVector{String})::Union{Nothing,String}
    for path in paths
        p = expanduser(path)
        isfile(p) && return p
    end
    return nothing
end

# Add the first existing/loading font from `paths` to `fonts` with the
# given glyph `ranges`. Returns the ImFont* or C_NULL.
function _add_first_font(fonts::Ptr{CImGui.lib.ImFontAtlas},
                         paths::AbstractVector{String},
                         ranges::Vector{UInt32})::Ptr{CImGui.lib.ImFont}
    for path in paths
        p = expanduser(path)
        isfile(p) || continue
        try
            font = CImGui.AddFontFromFileTTF(fonts, p, 18.0f0, C_NULL,
                                             pointer(ranges))
            if font != C_NULL
                return font
            end
        catch e
            @warn "AddFontFromFileTTF failed" p exception=(e, catch_backtrace())
        end
    end
    return C_NULL
end

# Same walk as `_add_first_font`, but MERGES the winner into the font
# added just before it instead of adding a separate one.
#
# The two callers need opposite things from the atlas, which is why
# both exist. The TUI painter draws one grapheme at a time and CHOOSES
# a font per cell (`use_font` in `_paint_buffer!`), so it needs the
# three fonts kept apart and reachable as `atlas->Fonts[0..2]`. The
# native widget path has no such loop: it hands whole strings to
# `TextUnformatted` / `InputTextMultiline`, which render in ONE font
# and, finding no glyph, drew 漢字 and 👨‍👩‍👧‍👦 as tofu boxes even though
# the atlas held a CJK and an emoji font all along. Merging is how Dear
# ImGui does fallback for that case: one ImFont, several sources, its
# own lookup picking the source that has the glyph.
function _merge_first_font(fonts::Ptr{CImGui.lib.ImFontAtlas},
                           paths::AbstractVector{String},
                           ranges::Vector{UInt32})::Bool
    for path in paths
        p = expanduser(path)
        isfile(p) || continue
        # ImGui copies the config into `atlas->Sources`, so it may be
        # freed as soon as the font is added.
        cfg = CImGui.lib.ImFontConfig()
        cfg == C_NULL && continue
        try
            unsafe_store!(getproperty(cfg, :MergeMode), true)
            if CImGui.AddFontFromFileTTF(fonts, p, 18.0f0, cfg,
                                         pointer(ranges)) != C_NULL
                return true
            end
        catch e
            @warn "AddFontFromFileTTF (merge) failed" p exception=(e, catch_backtrace())
        finally
            CImGui.lib.ImFontConfig_destroy(cfg)
        end
    end
    return false
end

# ImGuiFreeTypeLoaderFlags: LoadColor (1<<8, color-layered glyphs) | Bitmap
# (1<<9, allow bitmap strikes and FT_SIZE_REQUEST_TYPE_NOMINAL). Apple Color
# Emoji is a bitmap-only (sbix) font with fixed pixel sizes, so it requires
# the Bitmap flag or FT_Request_Size/FT_Load_Glyph fail and no emoji bakes.
const _FT_LOAD_COLOR_FLAG = UInt32((1 << 8) | (1 << 9))

# Glyph ranges for the atlas. With the FreeType-enabled libcimgui these are
# `ImWchar` (= `UInt32`) arrays, terminated by 0, kept as `const` so they
# outlive the atlas (ImGui does not copy the pointer). This is what unlocks
# code points above U+FFFF: the stb/ImWchar16 build could not represent them
# at all, so 😀 (U+1F600), the ZWJ family 👨‍👩‍👧‍👦 and regional indicators 🇫🇷
# were unbakeable; with ImWchar32 + the FreeType loader + LoadColor they are
# rasterized in color from Apple Color Emoji / Noto Color Emoji.

const _MONO_GLYPH_RANGES = UInt32[
    0x0020, 0x00FF,  # Basic Latin + Latin-1 Supplement (the default)
    0x0100, 0x024F,  # Latin Extended-A/B
    0x0300, 0x036F,  # Combining Diacritical Marks (e + U+0301)
    0x0370, 0x03FF,  # Greek and Coptic
    0x0400, 0x04FF,  # Cyrillic
    0x2010, 0x205E,  # General Punctuation
    0x2190, 0x21FF,  # Arrows
    0x2500, 0x257F,  # Box Drawing
    0x2580, 0x259F,  # Block Elements
    0x25A0, 0x25FF,  # Geometric Shapes (□ placeholder)
    0x2600, 0x26FF,  # Miscellaneous Symbols
    # Braille Patterns. Not decoration: `Spinner`'s DEFAULT frames are
    # ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏, so leaving this range out drew a tofu box wherever a
    # demo showed a spinner -- the one glyph on screen that is supposed
    # to be moving.
    0x2800, 0x28FF,
    0,
]

# What the symbol fallback is asked to supply -- only what a monospace
# face is actually likely to be missing, so it never displaces the
# primary for text.
const _SYMBOL_GLYPH_RANGES = UInt32[
    0x2800, 0x28FF,  # Braille Patterns (Spinner)
    0x2190, 0x21FF,  # Arrows
    0x2500, 0x25FF,  # Box Drawing + Block Elements + Geometric Shapes
    0,
]

const _CJK_GLYPH_RANGES = UInt32[
    0x3000, 0x303F,  # CJK Symbols and Punctuation
    0x3040, 0x309F,  # Hiragana (か)
    0x30A0, 0x30FF,  # Katakana
    0x3400, 0x4DBF,  # CJK Unified Ideographs Extension A
    0x4E00, 0x9FFF,  # CJK Unified Ideographs (漢字)
    0xF900, 0xFAFF,  # CJK Compatibility Ideographs
    0xFE00, 0xFE0F,  # Variation Selectors (VS16 in ❤️/☝️)
    0xFF00, 0xFFEF,  # Fullwidth Forms (ｆ)
    0x2600, 0x27BF,  # Miscellaneous Symbols + Dingbats (❤, ☝)
    0,
]

const _EMOJI_GLYPH_RANGES = UInt32[
    0x1F1E6, 0x1F1FF,  # Regional Indicator Symbols (🇫🇷 flag ligatures)
    0x1F300, 0x1F5FF,  # Miscellaneous Symbols and Pictographs
    0x1F600, 0x1F64F,  # Emoticons (😀)
    0x1F680, 0x1F6FF,  # Transport and Map Symbols
    0x1F700, 0x1F77F,  # Alchemical Symbols
    0x1F780, 0x1F7FF,  # Geometric Shapes Extended
    0x1F800, 0x1F8FF,  # Supplemental Arrows-C
    0x1F900, 0x1F9FF,  # Supplemental Symbols and Pictographs
    0x1FA70, 0x1FAFF,  # Symbols and Pictographs Extended-A
    0x1FB00, 0x1FBFF,  # Legacy Computing Symbols
    0x2600, 0x27BF,    # Misc Symbols + Dingbats (❤️, ☝️ color variants)
    0xFE0F, 0xFE0F,    # Variation Selector-16 (emoji presentation)
    0x200D, 0x200D,    # Zero-Width Joiner (👨‍👩‍👧‍👦 sequences)
    0,
]

# Set `atlas->FontLoaderFlags`. ImFontAtlas has no ImWchar-typed field, so its
# layout is identical between the stb/ImWchar16 and FreeType/ImWchar32 builds;
# the offset (720 on this build) is valid for both. We set it directly rather
# than via a wrapper accessor to avoid depending on the generated struct
# reflection. This must run BEFORE the first font is added / the atlas Build.
function _set_atlas_font_loader_flags!(fonts::Ptr{CImGui.lib.ImFontAtlas},
                                       flags::UInt32)
    # ImFontAtlas.FontLoaderFlags is at offset 720 in this CImGui.jl build
    # (see lib/aarch64-apple-darwin20.jl getproperty for Ptr{ImFontAtlas}).
    unsafe_store!(Ptr{Cuint}(Ptr{Cvoid}(fonts) + 720), flags)
    return nothing
end

"""
Build the atlas: a monospace primary, plus a CJK and a color-emoji
fallback.

`merge_fallbacks` picks WHICH SHAPE the fallbacks take, and the two
launch paths want opposite ones:

  * `false` (the TUI path) leaves three separate fonts, in this order,
    reachable as `atlas->Fonts[0..2]`. `_paint_buffer!` reads them back
    by index and chooses one per grapheme.
  * `true` (the native widget path) merges both fallbacks INTO the
    primary, leaving a single font that covers every range. Nothing on
    that path selects a font per glyph -- whole strings go to
    `TextUnformatted` and friends -- so without merging the fallbacks
    sat in the atlas unreachable and CJK and emoji drew as tofu.

Returns the same triple either way; under `merge_fallbacks` all three
elements are the one merged font, which is the honest answer to "which
font covers CJK here".
"""
function _load_fonts!(ctx; merge_fallbacks::Bool = false)::Tuple{Ptr{CImGui.lib.ImFont}, Ptr{CImGui.lib.ImFont}, Ptr{CImGui.lib.ImFont}}
    io = CImGui.GetIO()
    fonts = unsafe_load(getproperty(io, :Fonts))

    # Enable color emoji rasterization for the whole atlas. LoadColor only
    # affects fonts that actually have color layers (COLR/sbix); monochrome
    # fonts render as usual. The Bitmap flag allows bitmap-only strikes
    # (Apple Color Emoji sbix).
    #
    # Both flags are read by the FREETYPE loader and by nothing else, so
    # on a stb_truetype libcimgui setting them is inert -- which is the
    # whole reason emoji come out as tofu there. Say so once, rather
    # than leaving it to be rediscovered from a screenshot.
    _set_atlas_font_loader_flags!(fonts, _FT_LOAD_COLOR_FLAG)
    if !_has_freetype()
        @warn """
              libcimgui has no FreeType loader, so colour emoji cannot be \
              rasterised and will draw as tofu boxes. Latin, box drawing, \
              Braille and CJK are unaffected. This is a property of the \
              CImGuiPack_jll binary (0.12.2 is a stb_truetype build), not \
              of the fonts installed -- see upstream-bugs.md.
              """ maxlog=1
    end

    primary = _add_first_font(fonts, _MONO_FONT_CANDIDATES, _MONO_GLYPH_RANGES)

    # Merged into the primary in BOTH modes, and deliberately so.
    # Merging adds a source to an existing font rather than an entry to
    # `atlas->Fonts`, so the TUI path still finds its three fonts at
    # indices 0..2 -- while its primary now also draws ⠋. A separate
    # fourth font would have needed that indexing changed.
    _merge_first_font(fonts, _SYMBOL_FONT_CANDIDATES, _SYMBOL_GLYPH_RANGES)

    if merge_fallbacks
        # Order matters: each merge folds into the font added before it,
        # so the primary must already be there.
        _merge_first_font(fonts, _CJK_FONT_CANDIDATES, _CJK_GLYPH_RANGES)
        _merge_first_font(fonts, _EMOJI_FONT_CANDIDATES, _EMOJI_GLYPH_RANGES)
        # And the SAME emoji file once more, added rather than merged.
        # Merging folds a source into the primary, and a merged font
        # cannot be shaped: `RenderShapedText` on it draws NOTHING (an
        # empty column, verified against a framebuffer dump), which is
        # why the native path had no way to form a ZWJ ligature and drew
        # 👨‍👩‍👧‍👦 as four faces. A standalone font shapes correctly, so keep
        # one purely for that -- ordinary text still uses the merged
        # primary, and the extra atlas entry costs one more baked font.
        ManyUICImGui._SHAPED_EMOJI_FONT[] =
            _add_first_font(fonts, _EMOJI_FONT_CANDIDATES, _EMOJI_GLYPH_RANGES)
        return (primary, primary, primary)
    end

    cjk = _add_first_font(fonts, _CJK_FONT_CANDIDATES, _CJK_GLYPH_RANGES)
    emoji = _add_first_font(fonts, _EMOJI_FONT_CANDIDATES, _EMOJI_GLYPH_RANGES)
    # The TUI path shapes through this same font in `_paint_buffer!`.
    ManyUICImGui._SHAPED_EMOJI_FONT[] = emoji

    return (primary, cjk, emoji)
end

# A `TextLike` flattened to the String the C API needs.
#
# `string(rt)` is NOT this. `RichText` defines no `show`, so `string`
# falls back to the struct repr and a cell captioned "Ada" reached the
# window as `RichText(TextRun[TextRun("Ada", Style(...))])`. Every
# `w.cell(...)`, `w.format(...)` and tab title below is declared
# `TextLike` in ManyUI and may arrive either spelling, so each goes
# through here.
#
# Used where ImGui wants ONE string -- a Selectable's label, a tab
# caption, a table cell. Where a whole line is ours to draw, prefer
# `_draw_rich`, which keeps the styling this necessarily drops.
_plain(x::ManyUI.RichText)::String = ManyUI.plain(x)
_plain(x::AbstractString)::String = String(x)
_plain(x)::String = string(x)

# `Label.text[]` and `Static.text[]` hold a `RichText`, not a `String`
# -- a sequence of runs whose style varies along the line. Handing one
# straight to `TextUnformatted` threw
#
#     MethodError: no method matching unsafe_convert(::Type{Ptr{Int8}}, ::RichText)
#
# out of the render loop on the first frame, which took down every
# native demo the moment it drew its first label.
#
# `plain(rt)` alone would fix the crash and throw the styling away, so
# draw the runs instead: one `TextUnformatted` each, `SameLine(0, 0)`
# between them so they land on one line with no inserted spacing.
# That is the whole point of a `RichText` -- a status line that colours
# only its level, a caption that colours only its shortcut key.
function _draw_rich(rt::ManyUI.RichText)
    runs = rt.runs
    if isempty(runs)
        # Not `return`: a zero-height gap collapses the line and the
        # widgets below shift up. An empty string still advances a row.
        CImGui.TextUnformatted("")
        return
    end
    text_default = CImGui.GetColorU32(CImGui.ImGuiCol_Text)
    for (i, run) in enumerate(runs)
        i > 1 && CImGui.SameLine(0, 0)
        fg = _im_color(run.style.fg, text_default)
        # Only push when the run actually asks for a colour, so an
        # unstyled run keeps inheriting whatever the surrounding
        # style stack set.
        styled = fg != text_default
        styled && CImGui.PushStyleColor(CImGui.ImGuiCol_Text, fg)
        try
            _draw_run_text(run.text)
        finally
            styled && CImGui.PopStyleColor()
        end
    end
end

# The shaping font, or C_NULL. Kept unmerged by `_load_fonts!` precisely
# so it CAN be shaped -- see the comment there.
_shaping_font()::Ptr{CImGui.lib.ImFont} =
    Ptr{CImGui.lib.ImFont}(ManyUICImGui._SHAPED_EMOJI_FONT[])

# Draw one run's text. `TextUnformatted` renders codepoint by codepoint
# with no GSUB, so a ZWJ family came out as four separate faces and 🇫🇷
# as the letters F R. Hand each ligature CLUSTER to `RenderShapedText`
# instead and leave everything else on the plain path, which is both the
# fast one and the one that gets colour and wrapping right.
#
# Falls back to plain text whenever shaping is unavailable: a
# stb_truetype `libcimgui` (no FreeType, no shaper), or no emoji font
# installed. The result is then exactly what it was before -- wrong for
# ZWJ sequences, but nothing worse.
function _draw_run_text(text::AbstractString)
    font = _shaping_font()
    if font == C_NULL || !_has_freetype() || !CImGui.HasShaping()
        CImGui.TextUnformatted(text)
        return
    end
    pieces = ManyUICImGui._split_ligature_pieces(text)
    # Nothing to shape: one `TextUnformatted`, as before.
    if length(pieces) == 1 && !pieces[1][1]
        CImGui.TextUnformatted(pieces[1][2])
        return
    end
    if isempty(pieces)
        CImGui.TextUnformatted("")
        return
    end
    font_size = CImGui.GetFontSize()
    baked = CImGui.GetFontBaked(font, font_size)
    col = CImGui.GetColorU32(CImGui.ImGuiCol_Text)
    for (i, (is_lig, piece)) in enumerate(pieces)
        i > 1 && CImGui.SameLine(0, 0)
        if !is_lig || baked == C_NULL
            CImGui.TextUnformatted(piece)
            continue
        end
        # `RenderShapedText` draws through the draw list and does not
        # move the ImGui cursor, so advance it by hand with a `Dummy` of
        # the same size -- otherwise the next piece lands on top of this
        # one. The size is one emoji advance: the cluster collapses to a
        # SINGLE glyph, so its first codepoint measures it.
        pos = CImGui.GetCursorScreenPos()
        sz = CImGui.CalcTextSize(string(first(piece)))
        w = Float32(sz.x)
        h = Float32(sz.y)
        clip = CImGui.lib.ImVec4(Float32(pos.x), Float32(pos.y),
                                 Float32(pos.x) + w, Float32(pos.y) + h)
        CImGui.RenderShapedText(CImGui.GetWindowDrawList(), font, baked,
                                font_size,
                                CImGui.lib.ImVec2(Float32(pos.x),
                                                  Float32(pos.y)),
                                col, clip, piece)
        CImGui.Dummy((w, h))
    end
end

# A `Selectable` draws its own label, and draws it unshaped -- so a list
# item or a table cell holding 👨‍👩‍👧‍👦 showed four faces even after
# `_draw_run_text` existed, because the text never went through it.
#
# When the label needs shaping, give the Selectable an EMPTY visible
# label -- it keeps its id, its size and its hit box -- and paint the
# text over it at the position the Selectable started from. The overlay
# is drawn after, so it lands on top of the selection highlight.
# Draw `text` at an absolute screen position through the DRAW LIST,
# shaping the ligature clusters. Nothing here touches the ImGui cursor,
# which is the point: moving the cursor back over an item already drawn
# makes ImGui report
#
#     Code uses SetCursorPos()/SetCursorScreenPos() to extend
#     window/parent boundaries
#
# once per row, and put its red error panel over the window.
function _draw_text_shaped_at(x0::Real, y0::Real, text::AbstractString,
                              col::UInt32)
    dl = CImGui.GetWindowDrawList()
    font = _shaping_font()
    fs = CImGui.GetFontSize()
    baked = font == C_NULL ? C_NULL : CImGui.GetFontBaked(font, fs)
    cur = CImGui.GetFont()
    x = Float32(x0)
    y = Float32(y0)
    for (is_lig, piece) in ManyUICImGui._split_ligature_pieces(text)
        if is_lig && baked != C_NULL
            # The cluster collapses to a SINGLE glyph, so its first
            # codepoint measures the advance -- not the whole string,
            # which measures the components it is replacing.
            w = Float32(CImGui.CalcTextSize(string(first(piece))).x)
            h = Float32(CImGui.CalcTextSize(string(first(piece))).y)
            clip = CImGui.lib.ImVec4(x, y, x + w, y + h)
            CImGui.RenderShapedText(dl, font, baked, fs,
                                    CImGui.lib.ImVec2(x, y), col, clip, piece)
            x += w
        else
            CImGui.AddText(dl, cur, fs, (x, y), col, piece)
            x += Float32(CImGui.CalcTextSize(piece).x)
        end
    end
    return nothing
end

# A `Selectable` draws its own label, and draws it unshaped -- so a list
# item or a table cell holding 👨‍👩‍👧‍👦 showed four faces even after
# `_draw_run_text` existed, because the text never went through it.
#
# When the label needs shaping, give the Selectable an EMPTY visible
# label -- it keeps its id, its size and its hit box -- and paint the
# text over it at the position it started from. The overlay is drawn
# after, so it lands on top of the selection highlight.
#
# `flags` is left untyped on purpose: CImGui.jl passes an
# `ImGuiSelectableFlags_` enum value, not an Integer, and annotating it
# as one turned every table row into a MethodError inside the render
# loop (which then failed the `EndTable()` assert on the way out).
function _selectable_text(label::AbstractString, id::AbstractString,
                          is_selected::Bool, flags = nothing)::Bool
    if !ManyUICImGui._needs_shaping(label)
        return flags === nothing ?
            CImGui.Selectable("$(label)##$(id)", is_selected) :
            CImGui.Selectable("$(label)##$(id)", is_selected, flags)
    end
    start = CImGui.GetCursorScreenPos()
    clicked = flags === nothing ?
        CImGui.Selectable("##$(id)", is_selected) :
        CImGui.Selectable("##$(id)", is_selected, flags)
    _draw_text_shaped_at(start.x, start.y, label,
                         CImGui.GetColorU32(CImGui.ImGuiCol_Text))
    return clicked
end

_draw_widget(w::ManyUI.Label) = _draw_rich(w.text[])

_draw_widget(w::ManyUI.Static) = _draw_rich(w.text[])

function _draw_widget(w::ManyUI.Button)
    disabled = w.disabled[]
    disabled && CImGui.BeginDisabled()
    try
        CImGui.Button(w.label[]) && w.on_click(w)
    finally
        disabled && CImGui.EndDisabled()
    end
end

function _draw_widget(w::ManyUI.Checkbox)
    disabled = w.disabled[]
    disabled && CImGui.BeginDisabled()
    try
        b = Ref(w.state[] == ManyUI.CheckState.CHECKED)
        if CImGui.Checkbox(w.label[], b)
            w.state[] = b[] ? ManyUI.CheckState.CHECKED : ManyUI.CheckState.UNCHECKED
            w.on_change(w)
        end
    finally
        disabled && CImGui.EndDisabled()
    end
end

function _draw_widget(w::ManyUI.ProgressBar)
    CImGui.ProgressBar(Cfloat(w.progress[]), CImGui.ImVec2(-1, 0), "")
end

function _draw_widget(w::ManyUI.Slider)
    disabled = w.disabled[]
    disabled && CImGui.BeginDisabled()
    try
        f = Ref(Cfloat(w.value[]))
        if CImGui.SliderFloat("##$(w.node.id)", f, Cfloat(w.min), Cfloat(w.max))
            w.value[] = Float64(f[])
            w.on_change(w)
        end
    finally
        disabled && CImGui.EndDisabled()
    end
end

function _draw_widget(w::ManyUI.Spinner)
    idx = ((w.tick[] - 1) % length(w.frames)) + 1
    CImGui.TextUnformatted(w.frames[idx])
end

function _draw_widget(w::ManyUI.TextInput)
    disabled = w.disabled[]
    disabled && CImGui.BeginDisabled()
    try
        text_len = length(w.text[])
        buf = Vector{UInt8}(undef, max(256, text_len + 128))
        copyto!(buf, 1, Vector{UInt8}(w.text[]), 1, text_len)
        buf[text_len + 1] = 0

        flags = w.is_password ? CImGui.ImGuiInputTextFlags_Password : 0
        if CImGui.InputTextWithHint("##$(w.node.id)", w.placeholder, buf, length(buf), flags)
            w.text[] = GC.@preserve buf unsafe_string(pointer(buf))
            w.on_change(w)
        end
    finally
        disabled && CImGui.EndDisabled()
    end
end

function _draw_widget(w::ManyUI.RadioGroup)
    for (i, opt) in enumerate(w.options)
        disabled = i in w.disabled[]
        disabled && CImGui.BeginDisabled()
        try
            if CImGui.RadioButton("$(opt)##$(w.node.id)_$i", w.selected[] == i)
                w.selected[] = i
                w.on_change(w)
            end
        finally
            disabled && CImGui.EndDisabled()
        end
    end
end

function _draw_widget(w::ManyUI.DropDown)
    disabled = w.disabled[]
    disabled && CImGui.BeginDisabled()
    try
        items = w.panel.list.items
        preview = w.selected[] == 0 ? w.placeholder : string(w.panel.list.format(items[w.selected[]]))
        
        if CImGui.BeginCombo("##$(w.node.id)", preview)
            for (i, item) in enumerate(items)
                is_selected = w.selected[] == i
                if CImGui.Selectable(string(w.panel.list.format(item)), is_selected)
                    w.selected[] = i
                    w.on_change(w)
                end
                is_selected && CImGui.SetItemDefaultFocus()
            end
            CImGui.EndCombo()
        end
    finally
        disabled && CImGui.EndDisabled()
    end
end

function _draw_widget(w::ManyUI.List)
    disabled = w.disabled[]
    disabled && CImGui.BeginDisabled()
    try
        for (i, item) in enumerate(w.items)
            is_selected = (w.sel.cursor == i) || (i in w.sel.rows)
            label = _plain(w.format(item))
            if _selectable_text(label, "$(w.node.id)_$i", is_selected)
                if w.sel.cursor != i
                    w.sel.cursor = i
                    w.sel.anchor = i
                    w.on_change(w)
                else
                    w.on_submit(w)
                end
                w.version[] = w.version[] + 1
            end
        end
    finally
        disabled && CImGui.EndDisabled()
    end
end

function _draw_widget(w::ManyUI.TreeView)
    disabled = w.disabled[]
    disabled && CImGui.BeginDisabled()
    try
        rows = ManyUI.tree_rows(w)
        for (i, r) in enumerate(rows)
            r.depth > 0 && CImGui.Indent(r.depth * 15.0)
            prefix = r.leaf ? "  " : (r.node.expanded ? "v " : "> ")
            label = prefix * _plain(w.format(r.node.value))
            is_selected = (w.sel.cursor == i) || (i in w.sel.rows)
            if _selectable_text(label, "$(w.node.id)_$i", is_selected)
                w.sel.cursor = i
                w.sel.anchor = i
                if !r.leaf
                    # double-click or enter usually toggles, but selectable toggles on single click here.
                    ManyUI.toggle_node!(w, i)
                end
                w.on_change(w)
                w.version[] = w.version[] + 1
            end
            r.depth > 0 && CImGui.Unindent(r.depth * 15.0)
        end
    finally
        disabled && CImGui.EndDisabled()
    end
end

function _draw_widget(w::ManyUI.Scrollpane)
    flags = 0
    if w.bar_x == ManyUI.ScrollMode.ALWAYS || w.bar_x == ManyUI.ScrollMode.AUTO
        flags |= CImGui.ImGuiWindowFlags_HorizontalScrollbar
    end
    if CImGui.BeginChild("##scroll_$(w.node.id)", CImGui.ImVec2(0, 0), true, flags)
        try
            _draw_widget(w.holder)
        finally
            CImGui.EndChild()
        end
    end
end

function _draw_widget(w::ManyUI.Table)
    disabled = w.disabled[]
    disabled && CImGui.BeginDisabled()
    try
        cols = w.grid.cols
        ncols = length(cols)
        flags = CImGui.ImGuiTableFlags_Borders | CImGui.ImGuiTableFlags_RowBg
        if CImGui.BeginTable("##table_$(w.node.id)", ncols, flags)
            for col in cols
                CImGui.TableSetupColumn(col.header)
            end
            CImGui.TableHeadersRow()

            for (i, row) in enumerate(w.rows)
                CImGui.TableNextRow()
                for j in 1:ncols
                    CImGui.TableSetColumnIndex(j - 1)
                    label = _plain(w.cell(row, j))
                    if j == 1
                        is_selected = (w.sel.cursor == i) || (i in w.sel.rows)
                        if _selectable_text(label, "$(w.node.id)_$(i)_$(j)",
                                            is_selected,
                                            CImGui.ImGuiSelectableFlags_SpanAllColumns)
                            if w.sel.cursor != i
                                w.sel.cursor = i
                                w.sel.anchor = i
                                w.on_change(w)
                            else
                                w.on_submit(w)
                            end
                            w.version[] += 1
                        end
                    else
                        _draw_run_text(label)
                    end
                end
            end
            CImGui.EndTable()
        end
    finally
        disabled && CImGui.EndDisabled()
    end
end

function _draw_widget(w::ManyUI.DataTable)
    disabled = w.disabled[]
    disabled && CImGui.BeginDisabled()
    try
        cols = w.grid.cols
        ncols = length(cols)
        flags = CImGui.ImGuiTableFlags_Borders | CImGui.ImGuiTableFlags_RowBg | CImGui.ImGuiTableFlags_Sortable
        if CImGui.BeginTable("##datatable_$(w.node.id)", ncols, flags)
            for col in cols
                CImGui.TableSetupColumn(col.header)
            end
            CImGui.TableHeadersRow()
            
            # TODO: ImGui sorting callback integration. Currently, we just display the sorted rows.
            for i in 1:length(w.order)
                src_i = w.order[i]
                row = w.rows[src_i]
                CImGui.TableNextRow()
                for j in 1:ncols
                    CImGui.TableSetColumnIndex(j - 1)
                    label = _plain(w.cell(row, j))
                    if j == 1
                        is_selected = (w.sel.cursor == src_i) || (src_i in w.sel.rows)
                        if _selectable_text(label, "$(w.node.id)_$(src_i)_$(j)",
                                            is_selected,
                                            CImGui.ImGuiSelectableFlags_SpanAllColumns)
                            if w.sel.cursor != src_i
                                w.sel.cursor = src_i
                                w.sel.anchor = src_i
                                w.on_change(w)
                            else
                                w.on_submit(w)
                            end
                            w.version[] += 1
                        end
                    else
                        _draw_run_text(label)
                    end
                end
            end
            CImGui.EndTable()
        end
    finally
        disabled && CImGui.EndDisabled()
    end
end

function _draw_widget(w::ManyUI.TextArea)
    disabled = w.disabled[]
    disabled && CImGui.BeginDisabled()
    try
        content = join(w.lines, "\n")
        text_len = length(content)
        buf = Vector{UInt8}(undef, max(1024, text_len + 512))
        copyto!(buf, 1, Vector{UInt8}(content), 1, text_len)
        buf[text_len + 1] = 0

        if CImGui.InputTextMultiline("##$(w.node.id)", buf, length(buf), CImGui.ImVec2(-1, 0))
            new_text = GC.@preserve buf unsafe_string(pointer(buf))
            empty!(w.lines)
            append!(w.lines, split(new_text, '\n'))
            if isempty(w.lines)
                push!(w.lines, "")
            end
            w.version[] += 1
            w.on_change(w)
        end
    finally
        disabled && CImGui.EndDisabled()
    end
end

function _draw_widget(w::ManyUI.Tabs)
    for child in ManyUI.children(w)
        ManyUI.node(child).visible || continue
        _draw_widget(child)
    end
end

function _draw_widget(w::ManyUI.TabStrip)
    disabled = w.disabled[]
    disabled && CImGui.BeginDisabled()
    try
        if CImGui.BeginTabBar("##tabstrip_$(w.node.id)")
            for (i, title) in enumerate(w.titles)
                flags = w.selected[] == i ? CImGui.ImGuiTabItemFlags_SetSelected : 0
                is_open = Ref(true)
                if CImGui.BeginTabItem("$(_plain(title))##$(w.node.id)_$i", is_open, flags)
                    if w.selected[] != i
                        w.selected[] = i
                    end
                    CImGui.EndTabItem()
                end
            end
            CImGui.EndTabBar()
        end
    finally
        disabled && CImGui.EndDisabled()
    end
end

function _draw_widget(w::ManyUI.Container)
    for child in ManyUI.children(w)
        ManyUI.node(child).visible || continue
        _draw_widget(child)
    end
end

# Close the window the render loop is currently driving. `false` when
# there is none -- between loops, or under a non-ImGui backend, both of
# which are ordinary for a caller like the hub that runs every backend
# from the same code. Installed into `ManyUICImGui._CLOSE_REQUESTER` by
# `__init__`; see the Ref's docstring for why it is not a method.
function _request_close!()::Bool
    win = try
        CImGui.current_window()
    catch
        nothing
    end
    (win === nothing || win == C_NULL) && return false
    try
        GLFW.SetWindowShouldClose(win, true)
    catch
        return false
    end
    return true
end

"""
    ManyUICImGui.launch_manyui(factory; kwargs...)

Project the currently supported ManyUI primitives into an ImGui window. The
factory is evaluated once so reactive values and button callbacks survive
across frames. Unsupported widget types fail explicitly instead of silently
rendering a partial screen.
"""
function ManyUICImGui.launch_manyui(factory::Function; kwargs...)
    root = factory()
    root isa ManyUI.Widget ||
        throw(ArgumentError("ManyUI factory must return a Widget"))
    draw = () -> begin
        CImGui.Begin("ManyUI")
        try
            _draw_widget(root)
        finally
            CImGui.End()
        end
        nothing
    end
    # This path renders whole strings through ImGui's own text calls,
    # so it needs ONE font covering Latin, CJK and emoji rather than
    # the three separate ones the TUI painter picks between. Still a
    # default: an explicit `merge_fallbacks` in `kwargs` wins.
    ManyUICImGui.launch_imgui(draw; merge_fallbacks = true, kwargs...)
end

# =====================================================================
# cimguitui -- TUI cell-grid renderer inside an ImGui window.
#
# The native widget-by-widget projection above cannot express the ManyUI
# cell-width model (CJK / emoji = 2 cells, combining marks = 0), the
# DataTable header-sort path, or an ASCII-art table built from `Label`s
# under a proportional font. This block takes the other door: it runs
# the SAME `App` pipeline a terminal runs -- `frame!` paints `app.back`,
# a `Buffer` of `Cell`s -- and the ImGui draw callback rasterizes that
# buffer with ImDrawList at a fixed cell pitch.
#
# The result is that EVERY terminal-style demo (ManyUI's and Tachikoma's)
# runs unchanged inside an ImGui window: sorting, graphemes, capabilities
# tables, the lot.
# =====================================================================

# ImGui packs RGBA into a UInt32 as 0xABGR (little-endian: R is the low
# byte). Build that from three UInt8 channels.
_im_pack_rgb(r::UInt8, g::UInt8, b::UInt8, a::UInt8 = 0xff) =
    (UInt32(a) << 24) | (UInt32(b) << 16) | (UInt32(g) << 8) | UInt32(r)

# Resolve a ManyUI `Color` to an ImGui-packed RGBA. `COLOR_UNSET` and
# `COLOR_DEFAULT` fall back to a caller-supplied default so unset styles
# inherit the window background / a sensible text color instead of black.
function _im_color(c::ManyUI.Color, fallback::UInt32)::UInt32
    ManyUI.is_unset(c) && return fallback
    if c.kind === ManyUI.ColorKind.DEFAULT
        return fallback
    end
    rgb = ManyUI.to_rgb(c)
    return _im_pack_rgb(rgb.r, rgb.g, rgb.b)
end

# Map a ManyUI `Style` to a (fg, bg) pair of ImGui-packed colors, given
# the window's text and background defaults to inherit from.
function _im_style_colors(s::ManyUI.Style, text_default::UInt32,
                          bg_default::UInt32)::Tuple{UInt32,UInt32}
    fg = _im_color(s.fg, text_default)
    bg = _im_color(s.bg, bg_default)
    return (fg, bg)
end

# ManyUI `Attr.T` bits we care about for rendering. BOLD / ITALIC are
# hints; ImGui's default monospace font usually lacks an italic face, so
# we treat BOLD as the only attribute that changes the font push.
function _im_is_bold(s::ManyUI.Style)::Bool
    return ManyUI.has(s, ManyUI.Attr.BOLD)
end

# The per-frame state the TUI renderer needs from the App: the back
# buffer (already painted by `frame!`), the viewport size in cells, and
# the driver (to push events into). Held in a mutable so the draw
# callback can mutate `last_mouse_cell` for drag detection.
mutable struct _TuiRenderState
    app::ManyUITUI.App
    driver::ManyUICImGui.ImGuiTUIDriver
    cell_w::Float32
    cell_h::Float32
    origin_x::Float32
    origin_y::Float32
    last_mouse_cell::Union{Nothing,Tuple{Int,Int}}
    font::Ptr{CImGui.lib.ImFont}       # primary (monospace)
    cjk_font::Ptr{CImGui.lib.ImFont}   # CJK fallback (Hiragino)
    emoji_font::Ptr{CImGui.lib.ImFont} # color emoji fallback (Apple Color Emoji)
    # HarfBuzz fonts for text-shaping-based coverage checks. Shaping
    # the whole grapheme cluster (via _hb_full_coverage) is more
    # correct than single-codepoint has_glyph / IsGlyphInFont: it
    # catches missing combining marks and honors GSUB ligatures.
    hb_primary::Union{Nothing,HarfBuzz.Font}
    hb_cjk::Union{Nothing,HarfBuzz.Font}
    hb_emoji::Union{Nothing,HarfBuzz.Font}
end

# Convert ImGui mouse coordinates (screen-space) to a 1-based ManyUI
# cell coordinate. Returns `nothing` when the cursor is outside the
# cell grid.
function _mouse_to_cell(st::_TuiRenderState,
                        mx::Float32, my::Float32)::Union{Nothing,Tuple{Int,Int}}
    x = mx - st.origin_x
    y = my - st.origin_y
    (x < 0 || y < 0) && return nothing
    st.cell_w <= 0 && return nothing
    st.cell_h <= 0 && return nothing
    cx = floor(Int, x / st.cell_w) + 1
    cy = floor(Int, y / st.cell_h) + 1
    vp = st.app.viewport
    (1 <= cx <= vp.width && 1 <= cy <= vp.height) || return nothing
    return (cx, cy)
end

# Pump ImGui's input into the ManyUI event channel. Called once per
# frame, BEFORE `frame!`, so the App loop sees the events and repaints
# in the SAME frame.
function _pump_input!(st::_TuiRenderState)::Nothing
    d = st.driver
    isopen(d.input) || return nothing

    # --- Mouse -----------------------------------------------------------
    mouse_pos = CImGui.GetMousePos()
    mx = Float32(mouse_pos.x)
    my = Float32(mouse_pos.y)
    cell = _mouse_to_cell(st, mx, my)
    mods = _im_mods()

    # Press / release. ImGui only reports left/right/middle here; the
    # wheel is handled below.
    for (btn, mb) in (
        (CImGui.ImGuiMouseButton_Left,   ManyUI.MouseButton.LEFT),
        (CImGui.ImGuiMouseButton_Right,  ManyUI.MouseButton.RIGHT),
        (CImGui.ImGuiMouseButton_Middle, ManyUI.MouseButton.MIDDLE))
        if CImGui.IsMouseClicked(btn, false)
            cell === nothing && continue
            ManyUICImGui.push_event!(d, ManyUI.MouseEvent(
                ManyUI.MouseAction.PRESS, mb, cell[1], cell[2], mods))
            st.last_mouse_cell = cell
        elseif CImGui.IsMouseReleased(btn)
            cell === nothing && continue
            ManyUICImGui.push_event!(d, ManyUI.MouseEvent(
                ManyUI.MouseAction.RELEASE, mb, cell[1], cell[2], mods))
        end
    end

    # Drag: a held left button whose cell changed since last frame.
    if CImGui.IsMouseDown(CImGui.ImGuiMouseButton_Left) &&
       cell !== nothing && st.last_mouse_cell !== nothing &&
       cell != st.last_mouse_cell
        ManyUICImGui.push_event!(d, ManyUI.MouseEvent(
            ManyUI.MouseAction.DRAG, ManyUI.MouseButton.LEFT,
            cell[1], cell[2], mods))
        st.last_mouse_cell = cell
    end

    # Wheel. ImGui reports wheel deltas in units of "one notch"; ManyUI
    # treats the wheel as four pseudo-buttons.
    io = CImGui.GetIO()
    wy = unsafe_load(getproperty(io, :MouseWheel))
    wx = unsafe_load(getproperty(io, :MouseWheelH))
    if wy > 0
        ManyUICImGui.push_event!(d, ManyUI.MouseEvent(
            ManyUI.MouseAction.PRESS, ManyUI.MouseButton.WHEEL_UP,
            cell === nothing ? 1 : cell[1],
            cell === nothing ? 1 : cell[2], mods))
    elseif wy < 0
        ManyUICImGui.push_event!(d, ManyUI.MouseEvent(
            ManyUI.MouseAction.PRESS, ManyUI.MouseButton.WHEEL_DOWN,
            cell === nothing ? 1 : cell[1],
            cell === nothing ? 1 : cell[2], mods))
    end
    if wx > 0
        ManyUICImGui.push_event!(d, ManyUI.MouseEvent(
            ManyUI.MouseAction.PRESS, ManyUI.MouseButton.WHEEL_RIGHT,
            cell === nothing ? 1 : cell[1],
            cell === nothing ? 1 : cell[2], mods))
    elseif wx < 0
        ManyUICImGui.push_event!(d, ManyUI.MouseEvent(
            ManyUI.MouseAction.PRESS, ManyUI.MouseButton.WHEEL_LEFT,
            cell === nothing ? 1 : cell[1],
            cell === nothing ? 1 : cell[2], mods))
    end

    # --- Keyboard --------------------------------------------------------
    _pump_keys!(d, mods, io)
    return nothing
end

# Read ImGui's modifier state into a ManyUI `Modifiers` bitset.
function _im_mods()::ManyUI.Modifiers
    bits = UInt8(0)
    CImGui.IsKeyDown(CImGui.ImGuiKey_LeftCtrl)  && (bits |= UInt8(ManyUI.Modifier.CTRL))
    CImGui.IsKeyDown(CImGui.ImGuiKey_RightCtrl) && (bits |= UInt8(ManyUI.Modifier.CTRL))
    CImGui.IsKeyDown(CImGui.ImGuiKey_LeftShift)  && (bits |= UInt8(ManyUI.Modifier.SHIFT))
    CImGui.IsKeyDown(CImGui.ImGuiKey_RightShift) && (bits |= UInt8(ManyUI.Modifier.SHIFT))
    CImGui.IsKeyDown(CImGui.ImGuiKey_LeftAlt)  && (bits |= UInt8(ManyUI.Modifier.ALT))
    CImGui.IsKeyDown(CImGui.ImGuiKey_RightAlt) && (bits |= UInt8(ManyUI.Modifier.ALT))
    CImGui.IsKeyDown(CImGui.ImGuiKey_LeftSuper)  && (bits |= UInt8(ManyUI.Modifier.SUPER))
    CImGui.IsKeyDown(CImGui.ImGuiKey_RightSuper) && (bits |= UInt8(ManyUI.Modifier.SUPER))
    return ManyUI.Modifiers(bits)
end

# Map ImGui named keys to ManyUI `Key.T`. Anything not in the table is
# either a char (handled via `InputQueueCharacters`) or ignored.
const _IMGUI_KEY_MAP = Dict{CImGui.lib.ImGuiKey, ManyUI.Key.T}(
    CImGui.ImGuiKey_Enter      => ManyUI.Key.ENTER,
    CImGui.ImGuiKey_Backspace  => ManyUI.Key.BACKSPACE,
    CImGui.ImGuiKey_Escape     => ManyUI.Key.ESCAPE,
    CImGui.ImGuiKey_Space      => ManyUI.Key.SPACE,
    CImGui.ImGuiKey_UpArrow    => ManyUI.Key.UP,
    CImGui.ImGuiKey_DownArrow  => ManyUI.Key.DOWN,
    CImGui.ImGuiKey_LeftArrow  => ManyUI.Key.LEFT,
    CImGui.ImGuiKey_RightArrow => ManyUI.Key.RIGHT,
    CImGui.ImGuiKey_Home       => ManyUI.Key.HOME,
    CImGui.ImGuiKey_End        => ManyUI.Key.END,
    CImGui.ImGuiKey_PageUp     => ManyUI.Key.PAGE_UP,
    CImGui.ImGuiKey_PageDown   => ManyUI.Key.PAGE_DOWN,
    CImGui.ImGuiKey_Insert     => ManyUI.Key.INSERT,
    CImGui.ImGuiKey_Delete     => ManyUI.Key.DELETE,
    CImGui.ImGuiKey_F1  => ManyUI.Key.F1,  CImGui.ImGuiKey_F2  => ManyUI.Key.F2,
    CImGui.ImGuiKey_F3  => ManyUI.Key.F3,  CImGui.ImGuiKey_F4  => ManyUI.Key.F4,
    CImGui.ImGuiKey_F5  => ManyUI.Key.F5,  CImGui.ImGuiKey_F6  => ManyUI.Key.F6,
    CImGui.ImGuiKey_F7  => ManyUI.Key.F7,  CImGui.ImGuiKey_F8  => ManyUI.Key.F8,
    CImGui.ImGuiKey_F9  => ManyUI.Key.F9,  CImGui.ImGuiKey_F10 => ManyUI.Key.F10,
    CImGui.ImGuiKey_F11 => ManyUI.Key.F11, CImGui.ImGuiKey_F12 => ManyUI.Key.F12,
)

function _pump_keys!(d::ManyUICImGui.ImGuiTUIDriver,
                     mods::ManyUI.Modifiers,
                     io::Ptr{CImGui.lib.ImGuiIO})::Nothing
    # Named keys: pressed this frame?
    for (ik, mk) in _IMGUI_KEY_MAP
        if CImGui.IsKeyPressed(ik, false)
            ManyUICImGui.push_event!(d, ManyUI.KeyEvent(mk, '\0', mods))
        end
    end
    # Tab / shift-tab. ImGui folds these into the Tab key; ManyUI has
    # separate TAB / BACK_TAB codes.
    if CImGui.IsKeyPressed(CImGui.ImGuiKey_Tab, false)
        code = ManyUI.Modifier.SHIFT in mods ? ManyUI.Key.BACK_TAB :
                                                ManyUI.Key.TAB
        ManyUICImGui.push_event!(d, ManyUI.KeyEvent(code, '\0', mods))
    end
    # Character input: ImGui exposes a UTF-16/UTF-32 ImWchar queue in
    # `IO.InputQueueCharacters` (an ImVector_ImWchar). Each ImWchar is
    # a UInt16 codepoint (BMP) or a UInt32 for supplementary planes; in
    # CImGui's binding it is UInt16, so supplementary-plane emoji are
    # delivered as surrogate pairs. We decode the pair back to a Char.
    chars = unsafe_load(getproperty(io, :InputQueueCharacters))
    n = chars.Size
    data = chars.Data
    if n > 0 && data != C_NULL
        i = 0
        while i < n
            w = unsafe_load(data, i + 1)
            if 0xD800 <= w <= 0xDBFF && i + 1 < n
                # High surrogate; read the low surrogate.
                w2 = unsafe_load(data, i + 2)
                if 0xDC00 <= w2 <= 0xDFFF
                    cp = 0x10000 + ((Int(w) - 0xD800) << 10) +
                         (Int(w2) - 0xDC00)
                    ManyUICImGui.push_event!(d, ManyUI.KeyEvent(
                        ManyUI.Key.CHAR, Char(cp), mods))
                    i += 2
                    continue
                end
            end
            # Skip control characters that ImGui already reported as
            # named keys (Enter, Esc, Tab, Backspace).
            if !(w in (0x0D, 0x0A, 0x09, 0x1B, 0x7F))
                ManyUICImGui.push_event!(d, ManyUI.KeyEvent(
                    ManyUI.Key.CHAR, Char(Int(w)), mods))
            end
            i += 1
        end
    end
    return nothing
end

# Shape `text` with `hb_font` and return true when every shaped glyph
# is present (non-zero glyph ID). This is a proper text-shaping
# coverage check: HarfBuzz consults the font's GSUB/GPOS tables, so
# combining marks, ligatures and ZWJ sequences are evaluated as a
# whole rather than codepoint-by-codepoint.
#
# This matters for the TUI cell grid because a `Cell`'s `content` is a
# whole grapheme cluster. Checking only the first codepoint (as
# `has_glyph` does) answers the wrong question for clusters like
# "e" + U+0301 (combining acute): a font may have "e" but lack the
# combining mark, so `has_glyph(font, 'e')` is true yet the cluster
# cannot be rendered. Shaping produces a `.notdef` (glyph_id 0) for
# the missing mark, and this function returns false, letting the
# renderer fall back to the CJK font or the `□` placeholder.
#
# `HarfBuzz.shape` is a one-shot helper that allocates an `HbBuffer`
# per call; it is only invoked for `cell.width >= 2` cells (CJK /
# emoji), which are a small fraction of a typical TUI frame, so the
# per-frame cost is bounded.
function _hb_full_coverage(hb_font::HarfBuzz.Font,
                           text::AbstractString)::Bool
    isempty(text) && return true
    result = HarfBuzz.shape(hb_font, text)
    isempty(result.infos) && return false
    return all(g.glyph_id != UInt32(0) for g in result.infos)
end

# Remove Unicode variation selectors (U+FE00..U+FE0F) from a string. Used
# before AddText on the emoji font: VS16 selects emoji presentation but is
# not itself drawable, and many emoji fonts lack the codepoint so it would
# render as the fallback box (trailing □ in ❤️ / ☝️).
function _strip_variation_selectors(s::AbstractString)::String
    return String([ch for ch in s if !(0xFE00 <= UInt32(ch) <= 0xFE0F)])
end

# Does this cluster require GSUB shaping to render as a single glyph?
# - ZWJ sequences (U+200D): 👨‍👩‍👧‍👦 family, kiss, etc.
# - Regional-indicator pairs (U+1F1E6..U+1F1FF): 🇫🇷 flags.
# ImGui's codepoint-by-codepoint RenderText renders these as components;
# ImGuiFreeType::RenderShapedText shapes them into the ligature glyph.
# Moved to `ManyUICImGui/src`, next to `_split_ligature_pieces`, so both
# can be tested without a GPU. Aliased here because the paint loop reads
# it once per wide cell.
const _is_ligature_cluster = ManyUICImGui._is_ligature_cluster

# Paint `app.back` (the Buffer the App loop just filled) into the ImGui
# window using ImDrawList. One AddRectFilled per cell with a non-default
# background, one AddText per cell with content.
function _paint_buffer!(st::_TuiRenderState)::Nothing
    app = st.app
    buf = app.back
    w, h = size(buf)
    if w <= 0 || h <= 0
        return nothing
    end

    dl = CImGui.GetWindowDrawList()
    win_bg_ptr = CImGui.GetStyleColorVec4(CImGui.ImGuiCol_WindowBg)
    win_bg = unsafe_load(win_bg_ptr)
    bg_default = _im_pack_rgb(
        UInt8(round(win_bg.x * 255)),
        UInt8(round(win_bg.y * 255)),
        UInt8(round(win_bg.z * 255)),
        UInt8(round(win_bg.w * 255)))
    text_default = _im_pack_rgb(0xff, 0xff, 0xff, 0xff)

    cw, ch = st.cell_w, st.cell_h
    ox, oy = st.origin_x, st.origin_y
    font = st.font
    font_size = CImGui.GetFontSize()

    for y in 1:h
        row_y = oy + (y - 1) * ch
        for x in 1:w
            cell = buf[x, y]
            ManyUITUI.is_continuation(cell) && continue
            px = ox + (x - 1) * cw
            if ManyUI.is_set(cell.style.bg) &&
               cell.style.bg.kind !== ManyUI.ColorKind.DEFAULT
                bg_rgb = ManyUI.to_rgb(cell.style.bg)
                bg_col = _im_pack_rgb(bg_rgb.r, bg_rgb.g, bg_rgb.b)
                CImGui.AddRectFilled(dl,
                    (px, row_y), (px + cw * cell.width, row_y + ch),
                    bg_col)
            end
            content = String(cell.content)
            isempty(content) && continue
            fg_rgb = ManyUI.is_set(cell.style.fg) &&
                     cell.style.fg.kind !== ManyUI.ColorKind.DEFAULT ?
                     ManyUI.to_rgb(cell.style.fg) :
                     ManyUI.to_rgb(ManyUI.color(:bright_white))
            fg_col = _im_pack_rgb(fg_rgb.r, fg_rgb.g, fg_rgb.b)

            # Choose font: shape the WHOLE cell content (a grapheme
            # cluster, possibly with combining marks or a ligature
            # sequence such as a regional indicator pair) via HarfBuzz
            # and require every shaped glyph to be present in the
            # font. This rejects a font that has the base codepoint but
            # lacks a combining mark, and accepts a font whose GSUB
            # table forms a ligature from several codepoints. Falls
            # back to single-codepoint has_glyph / IsGlyphInFont when
            # HarfBuzz fonts are not loaded. Tries the primary mono
            # font, then the CJK fallback, then the color emoji
            # fallback; if none cover the cluster, substitute a visible
            # placeholder.
            use_font = font
            # Variation selectors (U+FE00..U+FE0F) select emoji/text
            # presentation but are not themselves drawable, and most
            # emoji fonts (Twemoji COLRv0) lack the codepoint. Keep them
            # OUT of both the coverage check and the rendered string:
            # otherwise _hb_full_coverage("❤️") returns false (VS16 ->
            # .notdef) and the whole cluster routes to the □ placeholder.
            # Stripping VS16 makes "❤️" route to the emoji font and render
            # as the color heart. (The cell width is already 2 from
            # ManyUI's grapheme_width, so the slot stays 2 cells wide.)
            draw_content = _strip_variation_selectors(content)
            # VS16 (U+FE0F) is the EMOJI PRESENTATION selector: the user
            # explicitly asked for the emoji rendering of the base
            # codepoint (e.g. ❤️ vs ❤). When present, prefer the color
            # emoji font over the primary mono font even if the primary
            # has the base codepoint as a monochrome outline (Menlo has
            # U+2764), otherwise ❤️ renders monochrome instead of color.
            want_emoji_presentation = any(c -> UInt32(c) == 0xFE0F, content)
            if cell.width >= 2
                first_cp = UInt32(first(draw_content))
                in_primary = if st.hb_primary !== nothing
                    _hb_full_coverage(st.hb_primary, draw_content)
                else
                    first_cp <= 0xFFFF &&
                        CImGui.IsGlyphInFont(font, UInt32(first_cp))
                end
                in_cjk = if st.hb_cjk !== nothing && st.cjk_font != C_NULL
                    _hb_full_coverage(st.hb_cjk, draw_content)
                else
                    st.cjk_font != C_NULL && first_cp <= 0xFFFF &&
                        CImGui.IsGlyphInFont(st.cjk_font, UInt32(first_cp))
                end
                # Emoji coverage: prefer HarfBuzz shaping when an emoji
                # HarfBuzz.Font is loaded (the :ot funcs, no FreeType, so
                # even bitmap-only fonts load). Fall back to single-codepoint
                # IsGlyphInFont on the atlas emoji font, which checks the
                # TTF cmap via FreeType and works for bitmap-only fonts.
                # Single-codepoint is sufficient for routing: 👨‍👩‍👧‍👦 and 🇫🇷
                # are ligature sequences whose FIRST codepoint (U+1F468 /
                # U+1F1EB) is present in the emoji font, so the cell routes
                # to the emoji font; AddText then renders the components
                # (ImGui does not GSUB-shape, so ZWJ families render as
                # their parts and regional indicators as two letters --
                # a known limitation, lifted when HasShaping() enables
                # RenderShapedText).
                in_emoji = if st.emoji_font != C_NULL
                    if st.hb_emoji !== nothing
                        _hb_full_coverage(st.hb_emoji, draw_content)
                    else
                        CImGui.IsGlyphInFont(st.emoji_font, first_cp)
                    end
                else
                    false
                end
                if want_emoji_presentation && in_emoji &&
                        st.emoji_font != C_NULL
                    # VS16: force the color emoji font.
                    use_font = st.emoji_font
                elseif !in_primary && in_cjk && st.cjk_font != C_NULL
                    use_font = st.cjk_font
                elseif !in_primary && !in_cjk && in_emoji &&
                        st.emoji_font != C_NULL
                    use_font = st.emoji_font
                elseif !in_primary && !in_cjk && !in_emoji
                    draw_content = "□"
                end
            end

            if cell.width == 2
                span_w = 2 * cw
                # Ligature clusters (ZWJ families 👨‍👩‍👧‍👦, regional-indicator
                # flags 🇫🇷) routed to the color emoji font must be SHAPED
                # with HarfBuzz to form the single ligature glyph; ImGui's
                # AddText is codepoint-by-codepoint and would render the
                # components. ImGuiFreeType::RenderShapedText bakes the
                # ligature glyph by FT index on demand. Falls back to
                # AddText for single-codepoint emoji (😀 ❤ ☝) which AddText
                # already handles.
                #
                # `_has_freetype()` and not `isdefined(CImGui, :HasShaping)`.
                # `isdefined` asks about the JULIA binding, which CImGui.jl's
                # generated wrapper always defines; the C symbol behind it
                # exists only in a FreeType build. So on a stb_truetype
                # libcimgui the old guard passed and `HasShaping()` itself
                # threw "could not load symbol" -- inside the render loop,
                # once per ligature cell.
                if use_font === st.emoji_font && _is_ligature_cluster(draw_content) &&
                        _has_freetype() && CImGui.HasShaping()
                    baked = CImGui.GetFontBaked(st.emoji_font, font_size)
                    if baked != C_NULL
                        clip = CImGui.lib.ImVec4(px, row_y, px + span_w, row_y + ch)
                        pos = CImGui.lib.ImVec2(px, row_y)
                        CImGui.RenderShapedText(dl, st.emoji_font, baked,
                                               font_size, pos, fg_col, clip,
                                               draw_content)
                    else
                        CImGui.AddText(dl, use_font, font_size,
                            (px, row_y), fg_col, draw_content, C_NULL, span_w)
                    end
                else
                    CImGui.AddText(dl, use_font, font_size,
                        (px, row_y), fg_col, draw_content, C_NULL, span_w)
                end
            else
                CImGui.AddText(dl, use_font, font_size,
                    (px, row_y), fg_col, draw_content)
            end
        end
    end
    return nothing
end

# Compute the cell pitch from the monospace font's glyph advance. ImGui
# does not expose advance directly, but `CalcTextSize("M")` on a
# monospace font returns the cell width, and `GetTextLineHeight()` is
# the cell height (ascent + descent + line gap).
function _measure_cell(font::Ptr{CImGui.lib.ImFont},
                       font_size::Float32)::Tuple{Float32,Float32}
    # Push the font so CalcTextSize uses it, then pop.
    CImGui.PushFont(font, font_size)
    try
        sz = CImGui.CalcTextSize("M")
        cw = Float32(sz.x)
        ch = CImGui.GetTextLineHeight()
        # Guard against degenerate values before the font is loaded.
        cw <= 0 && (cw = font_size * 0.6)
        ch <= 0 && (ch = font_size)
        return (cw, ch)
    finally
        CImGui.PopFont()
    end
end

# The per-frame draw callback. Runs the App loop's input pump, calls
# `frame!` to paint `app.back`, then rasterizes the buffer.
function _tui_draw(st::_TuiRenderState)::Nothing
    # Resolve fonts from the current ImGui context. The primary font
    # (index 0) is the monospace; index 1 is the CJK fallback; index 2 is
    # the color emoji fallback. _load_fonts! adds them in that order.
    io = CImGui.GetIO()
    fonts = unsafe_load(getproperty(io, :Fonts))
    st.font = CImGui.GetFont()
    # Retrieve fallback fonts from the atlas's Fonts vector by index.
    # ImFontAtlas.Fonts is an `ImVector<ImFont*>` stored by value at
    # offset 104; we load the vector struct (Size, Capacity, Data) and
    # index into its Data array of `ImFont*` pointers.
    if st.cjk_font == C_NULL || st.emoji_font == C_NULL
        try
            fv = unsafe_load(getproperty(fonts, :Fonts))
            n = fv.Size
            data = fv.Data
            ptrsz = sizeof(Ptr{Cvoid})
            if n >= 2 && st.cjk_font == C_NULL
                st.cjk_font = unsafe_load(data + ptrsz)
            end
            if n >= 3 && st.emoji_font == C_NULL
                st.emoji_font = unsafe_load(data + 2 * ptrsz)
            end
        catch
        end
    end
    fs = CImGui.GetFontSize()

    # Initialize HarfBuzz fonts for text-shaping-based coverage checks.
    # Done lazily on the first frame when st.hb_primary is nothing.
    # These fonts feed `_hb_full_coverage`, which shapes a cell's
    # whole grapheme cluster to decide whether the primary or CJK
    # font fully covers it.
    #
    # HarfBuzz.jl dropped family-name resolution, so we resolve a font
    # FILE PATH (the first existing candidate -- the same list the atlas
    # `_add_first_font` walks, so the HarfBuzz font matches the atlas
    # font). `HarfBuzz.Font(path; size)` uses the :ot funcs (no FreeType),
    # so bitmap-only fonts (Apple Color Emoji) load too.
    if st.hb_primary === nothing
        p = _first_existing_path(_MONO_FONT_CANDIDATES)
        if p !== nothing
            try; st.hb_primary = HarfBuzz.Font(p; size = 18); catch; end
        end
    end
    if st.hb_cjk === nothing
        p = _first_existing_path(_CJK_FONT_CANDIDATES)
        if p !== nothing
            try; st.hb_cjk = HarfBuzz.Font(p; size = 18); catch; end
        end
    end
    # HarfBuzz emoji font for coverage checks on >U+FFFF clusters. Try
    # the same candidate paths as the atlas (a COLRv0 outline font like
    # Twemoji loads via FT_Set_Char_Size; bitmap-only Apple Color Emoji
    # fails and is skipped, which is fine -- atlas IsGlyphInFont is the
    # fallback in _paint_buffer!).
    if st.hb_emoji === nothing
        for path in _EMOJI_FONT_CANDIDATES
            p = expanduser(path)
            isfile(p) || continue
            try
                st.hb_emoji = HarfBuzz.Font(p; size = 18, index = 0)
                break
            catch
            end
        end
    end

    cw, ch = _measure_cell(st.font, fs)
    st.cell_w = cw
    st.cell_h = ch

    avail = CImGui.GetContentRegionAvail()
    avail_w = Float32(avail.x)
    avail_h = Float32(avail.y)
    new_cols = max(1, floor(Int, avail_w / cw))
    new_rows = max(1, floor(Int, avail_h / ch))

    vp = st.app.viewport
    if new_cols != vp.width || new_rows != vp.height
        ManyUICImGui.notify_resize!(st.driver, ManyUI.Size(new_cols, new_rows))
    end

    pos = CImGui.GetCursorScreenPos()
    st.origin_x = Float32(pos.x)
    st.origin_y = Float32(pos.y)

    # Process any pending events (resize, keyboard, mouse) BEFORE painting.
    # `frame!` does layout+paint but does NOT drain the event channel —
    # that's the job of `_loop!`, which we don't run. We drain inline.
    ch_events = ManyUITUI.events(st.driver)
    while isready(ch_events)
        e = try; take!(ch_events); catch; break; end
        ManyUITUI.handle!(st.app, e)
    end

    _pump_input!(st)
    ManyUITUI.frame!(st.app)
    _paint_buffer!(st)

    CImGui.Dummy((avail_w, avail_h))
    return nothing
end

# The shared draw-callback builder. Used by both `launch_tui` (which
# builds the App from a factory) and `launch_tui_app!` (which takes an
# already-built App, for animated demos that tick from a Timer).
function _tui_render_callback(st::_TuiRenderState, app::ManyUITUI.App,
                              width::Int, height::Int,
                              title::String)::Function
    flags = CImGui.ImGuiWindowFlags_NoTitleBar |
            CImGui.ImGuiWindowFlags_NoResize |
            CImGui.ImGuiWindowFlags_NoMove |
            CImGui.ImGuiWindowFlags_NoCollapse |
            CImGui.ImGuiWindowFlags_NoBringToFrontOnFocus |
            CImGui.ImGuiWindowFlags_NoNavFocus |
            CImGui.ImGuiWindowFlags_NoScrollbar |
            CImGui.ImGuiWindowFlags_NoScrollWithMouse
    return () -> begin
        CImGui.SetNextWindowPos((0, 0),
            CImGui.ImGuiCond_Always, (0, 0))
        CImGui.SetNextWindowSize((Float32(width), Float32(height)),
            CImGui.ImGuiCond_Always)
        is_open = Ref(true)
        CImGui.Begin(title, is_open, flags)
        try
            _tui_draw(st)
        finally
            CImGui.End()
        end
        # The App can stop WITHOUT the window being closed: `quit!` from
        # a Quit button, a demo's exit key, or the hub's Launch button,
        # which quits the hub App so the demo can take the screen. The
        # render loop only stops on `:imgui_exit_loop`, so returning
        # `nothing` unconditionally left the window up painting a dead
        # App -- and made every such click look inert.
        ManyUICImGui._tui_exit_signal(st.app.running, is_open[])
    end
end

"""
    ManyUICImGui.launch_tui(factory; width, height, title, wait, config, stylesheet)

Run a ManyUI widget FACTORY inside a Dear ImGui window, rendering the
TUI cell grid with ImDrawList. This is the TUI-in-ImGui projection: the
SAME `App` pipeline a terminal runs, painted cell-by-cell into an ImGui
window, so every terminal-style demo (sorting, graphemes, ASCII-art
capabilities tables, Tachikoma demos) runs unchanged.

Requires the optional CImGui / GLFW / ModernGL extension.
"""
function ManyUICImGui.launch_tui(factory::Function;
                                 width::Integer = 1280,
                                 height::Integer = 720,
                                 title::AbstractString = "ManyUI TUI",
                                 wait::Bool = true,
                                 config::ManyUITUI.AppConfig =
                                     ManyUITUI.AppConfig(),
                                 stylesheet::ManyUI.Stylesheet =
                                     ManyUI.STYLESHEET_EMPTY)
    width > 0 || throw(ArgumentError("width must be positive"))
    height > 0 || throw(ArgumentError("height must be positive"))

    backend = ManyUICImGui.ImGuiTUIBackend()
    driver = ManyUITUI.make_driver(backend)
    root = factory()::ManyUI.Widget
    app = ManyUITUI.App(root, driver;
                        config = config, stylesheet = stylesheet)

    st = _TuiRenderState(app, driver, 8.0f0, 16.0f0, 0.0f0, 0.0f0,
                         nothing, C_NULL, C_NULL, C_NULL, nothing, nothing, nothing)
    draw = _tui_render_callback(st, app, Int(width), Int(height),
                                String(title))

    # Start the App so the driver channel is open and the first `frame!`
    # has a running loop with the stylesheet applied. Without this the
    # window stays black: events are dropped (closed channel) and no
    # layout/cascade/paint runs.
    ManyUITUI.start!(driver, app.viewport)
    ManyUITUI._bootstrap!(app)

    ManyUICImGui.launch_imgui(draw; width = width, height = height,
                              title = String(title), wait = wait)
end

"""
    ManyUICImGui.launch_tui_app!(app; width, height, title, on_tick, tick_interval)

Run an ALREADY-BUILT ManyUI `App` inside a Dear ImGui window. The App
must have been constructed with an [`ImGuiTUIDriver`](@ref) (via
`ManyUITUI.make_driver(ManyUICImGui.ImGuiTUIBackend())`).

For animated demos, pass `on_tick = () -> ...` and `tick_interval`: a
timer fires `on_tick` every `tick_interval` seconds, and the callback
typically advances the simulation and posts a `TickEvent` to wake the
App loop.
"""
function ManyUICImGui.launch_tui_app!(app::ManyUITUI.App;
                                      width::Integer = 1280,
                                      height::Integer = 720,
                                      title::AbstractString = "ManyUI TUI",
                                      on_tick::Union{Nothing,Function} = nothing,
                                      tick_interval::Real = 0.1)
    width > 0 || throw(ArgumentError("width must be positive"))
    height > 0 || throw(ArgumentError("height must be positive"))

    driver = app.driver
    driver isa ManyUICImGui.ImGuiTUIDriver ||
        throw(ArgumentError("launch_tui_app!: app.driver must be an " *
                            "ImGuiTUIDriver; got $(typeof(driver))"))

    st = _TuiRenderState(app, driver, 8.0f0, 16.0f0, 0.0f0, 0.0f0,
                         nothing, C_NULL, C_NULL, C_NULL, nothing, nothing, nothing)
    draw = _tui_render_callback(st, app, Int(width), Int(height),
                                String(title))

    # Start the App so the first `frame!` has a running loop.
    ManyUITUI.start!(driver, app.viewport)
    ManyUITUI._bootstrap!(app)

    timer = nothing
    if on_tick !== nothing
        timer = Timer(Float64(tick_interval); interval = Float64(tick_interval)) do _
            try
                on_tick()
            catch err
                err isa InterruptException || rethrow()
            end
        end
    end
    try
        ManyUICImGui.launch_imgui(draw; width = width, height = height,
                                  title = String(title), wait = true)
    finally
        timer === nothing || close(timer)
        ManyUITUI.stop!(driver)
    end
end

end
