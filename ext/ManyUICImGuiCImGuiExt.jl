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
                                   wait::Bool=true)
    width > 0 || throw(ArgumentError("width must be positive"))
    height > 0 || throw(ArgumentError("height must be positive"))
    CImGui.set_backend(:GlfwOpenGL3)
    ctx = CImGui.CreateContext()

    # Load fonts: a monospace primary (Menlo) for ASCII/box-drawing, and
    # a CJK fallback (Hiragino Sans GB) for 漢字か. Per-cell font
    # selection is done in _paint_buffer!.
    _fonts = _load_fonts!(ctx)

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

function _load_fonts!(ctx)::Tuple{Ptr{CImGui.lib.ImFont}, Ptr{CImGui.lib.ImFont}, Ptr{CImGui.lib.ImFont}}
    io = CImGui.GetIO()
    fonts = unsafe_load(getproperty(io, :Fonts))

    # Enable color emoji rasterization for the whole atlas. The FreeType
    # loader is auto-selected at Build time because libcimgui was compiled
    # with IMGUI_ENABLE_FREETYPE. LoadColor only affects fonts that actually
    # have color layers (COLR/sbix); monochrome fonts render as usual.
    # The Bitmap flag allows bitmap-only strikes (Apple Color Emoji sbix).
    _set_atlas_font_loader_flags!(fonts, _FT_LOAD_COLOR_FLAG)

    primary = _add_first_font(fonts, _MONO_FONT_CANDIDATES, _MONO_GLYPH_RANGES)
    cjk = _add_first_font(fonts, _CJK_FONT_CANDIDATES, _CJK_GLYPH_RANGES)
    emoji = _add_first_font(fonts, _EMOJI_FONT_CANDIDATES, _EMOJI_GLYPH_RANGES)

    return (primary, cjk, emoji)
end

function _draw_widget(w::ManyUI.Label)
    CImGui.TextUnformatted(w.text[])
end

function _draw_widget(w::ManyUI.Static)
    CImGui.TextUnformatted(w.text[])
end

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
            label = string(w.format(item))
            if CImGui.Selectable("$(label)##$(w.node.id)_$i", is_selected)
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
            label = prefix * string(w.format(r.node.value))
            is_selected = (w.sel.cursor == i) || (i in w.sel.rows)
            if CImGui.Selectable("$(label)##$(w.node.id)_$i", is_selected)
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
                    label = string(w.cell(row, j))
                    if j == 1
                        is_selected = (w.sel.cursor == i) || (i in w.sel.rows)
                        if CImGui.Selectable("$(label)##$(w.node.id)_$(i)_$(j)", is_selected, CImGui.ImGuiSelectableFlags_SpanAllColumns)
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
                        CImGui.TextUnformatted(label)
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
                    label = string(w.cell(row, j))
                    if j == 1
                        is_selected = (w.sel.cursor == src_i) || (src_i in w.sel.rows)
                        if CImGui.Selectable("$(label)##$(w.node.id)_$(src_i)_$(j)", is_selected, CImGui.ImGuiSelectableFlags_SpanAllColumns)
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
                        CImGui.TextUnformatted(label)
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
                if CImGui.BeginTabItem("$(title)##$(w.node.id)_$i", is_open, flags)
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
    ManyUICImGui.launch_imgui(draw; kwargs...)
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
function _is_ligature_cluster(s::AbstractString)::Bool
    has_zwj = false
    n_ri = 0
    for ch in s
        cp = UInt32(ch)
        if cp == 0x200D
            has_zwj = true
        elseif 0x1F1E6 <= cp <= 0x1F1FF
            n_ri += 1
        end
    end
    return has_zwj || n_ri >= 2
end

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
                if use_font === st.emoji_font && _is_ligature_cluster(draw_content) &&
                        isdefined(CImGui, :HasShaping) && isdefined(CImGui, :RenderShapedText) &&
                        CImGui.HasShaping()
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
        nothing
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
