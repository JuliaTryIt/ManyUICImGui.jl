# cimguitui.jl -- a TUI backend that paints the ManyUI cell grid inside
# a Dear ImGui window using ImDrawList.
#
# The native projection in `backend.jl` / `ManyUICImGuiCImGuiExt.jl` maps
# each ManyUI widget to a Dear ImGui widget. That projection is fragile
# for terminal-style demos: it does not implement DataTable header sort
# callbacks, it cannot express the ManyUI cell-width model (CJK/emoji =
# 2 cells, combining marks = 0), and any ASCII-art table built from
# `Label`s is misaligned by ImGui's proportional font.
#
# `ImGuiTUIBackend` takes the opposite tack: it runs the SAME `App`
# pipeline a terminal runs -- `frame!` paints `app.back`, a `Buffer` of
# `Cell`s -- and the CImGui extension reads that buffer back and draws
# each cell with ImDrawList using a MONOSPACE font at a fixed cell pitch.
# Every terminal-style demo (ManyUI's and Tachikoma's) runs unchanged,
# because it IS a terminal-style demo, rendered into an ImGui window.
#
# The driver itself is headless-shaped: it owns the event channel, the
# display size and the last painted `Buffer`. The CImGui extension owns
# the GLFW window and the ImDrawList paint loop, and pumps ImGui mouse /
# keyboard events back through `push_event!`.

"""
    ImGuiTUIBackend(; size, depth, buffer)

A [`ManyUITUI.Backend`](@ref) whose driver is an [`ImGuiTUIDriver`](@ref).

The backend is INERT, like every `Backend`: `make_driver` mints the
driver, and `ManyUICImGui.launch_tui` binds the driver to an `App` and
to the native CImGui render loop. Use this backend -- not the widget-by-
widget `ImGuiBackend` -- when you want a terminal-style ManyUI app
rendered inside an ImGui window with correct grapheme widths, DataTable
sorting, and ASCII-art alignment.
"""
struct ImGuiTUIBackend <: ManyUITUI.Backend
    size::Size
    depth::ManyUI.ColorDepth.T
    buffer::Int
end

ManyUI.backend_available(::ImGuiTUIBackend) = native_available()
ManyUI.backend_kind(::ImGuiTUIBackend) = :cimguitui
ManyUI.backend_capabilities(::ImGuiTUIBackend) = merge(
    ManyUI.DEFAULT_BACKEND_CAPABILITIES,
    (transparency = true, native_window = true, gpu = native_available(),
     multi_session = false))

function ImGuiTUIBackend(; size::Size = Size(100, 30),
                         depth::ManyUI.ColorDepth.T =
                             ManyUI.ColorDepth.TRUECOLOR,
                         buffer::Int = 256)::ImGuiTUIBackend
    buffer > 0 || throw(ArgumentError("buffer must be positive"))
    ImGuiTUIBackend(size, depth, buffer)
end

"""
    ImGuiTUIDriver <: Driver

The lifecycle and input seam for the TUI-in-ImGui projection. Mirrors
`HeadlessDriver`: events come from a `Channel{Event}`, `emit!` is a
no-op sink (the CImGui extension reads `app.back` directly, so the ANSI
byte stream is never produced), and the last painted `Buffer` is
exposed for the extension to rasterize.

The driver carries the CELL GRID rather than ANSI bytes because the
CImGui renderer needs per-cell style + content to issue `AddText` /
`AddRectFilled` calls. Re-parsing ANSI would be lossy (a width-2
grapheme's continuation cell is not recoverable from bytes alone) and
wasteful (the grid is already built).
"""
mutable struct ImGuiTUIDriver <: Driver
    size::Size
    caps::DriverCaps
    input::Channel{ManyUI.Event}
    open::Bool
    started::Bool
end

function ImGuiTUIDriver(size::Size = Size(100, 30);
                        depth::ManyUI.ColorDepth.T =
                            ManyUI.ColorDepth.TRUECOLOR,
                        buffer::Int = 256)::ImGuiTUIDriver
    buffer > 0 || throw(ArgumentError("buffer must be positive"))
    ImGuiTUIDriver(size,
                   DriverCaps(; color_depth = depth, mouse = true,
                              bracketed_paste = false, focus_events = true,
                              alt_screen = false, title = true,
                              unicode = true, sync_output = false),
                   Channel{ManyUI.Event}(buffer), false, false)
end

function start!(d::ImGuiTUIDriver,
                size_hint::Union{Nothing,Size} = nothing)::Nothing
    size_hint === nothing || (d.size = size_hint)
    d.open = true
    d.started = true
    return nothing
end

function stop!(d::ImGuiTUIDriver)::Nothing
    d.open = false
    d.started = false
    isopen(d.input) && close(d.input)
    return nothing
end

function restore!(d::ImGuiTUIDriver)::Nothing
    try
        stop!(d)
    catch
        d.open = false
    end
    return nothing
end

# The ANSI byte stream is never consumed by the CImGui renderer, which
# reads `app.back` directly. Accept the bytes and drop them so `frame!`
# does not error.
emit!(d::ImGuiTUIDriver, bytes::AbstractVector{UInt8})::Int = length(bytes)

flush!(::ImGuiTUIDriver)::Nothing = nothing
display_size(d::ImGuiTUIDriver)::Size = d.size
capabilities(d::ImGuiTUIDriver)::DriverCaps = d.caps
events(d::ImGuiTUIDriver)::Channel{ManyUI.Event} = d.input
Base.isopen(d::ImGuiTUIDriver)::Bool = d.open

# `_bootstrap!` calls this when `capabilities(driver).title` is true.
# ImGui sets the title via the window creation kwargs, so this is a no-op.
set_title!(::ImGuiTUIDriver, ::AbstractString)::Nothing = nothing

"""Queue a canonical ManyUI event for the TUI-in-ImGui input adapter."""
function push_event!(d::ImGuiTUIDriver, e::ManyUI.Event)::Nothing
    d.open || return nothing
    isopen(d.input) || return nothing
    try
        put!(d.input, e)
    catch err
        err isa InvalidStateException || rethrow()
    end
    return nothing
end

function notify_resize!(d::ImGuiTUIDriver, size::Size)::Nothing
    d.size = size
    push_event!(d, ManyUI.ResizeEvent(size))
    return nothing
end

function resize!(d::ImGuiTUIDriver, size::Size)::Nothing
    notify_resize!(d, size)
    return nothing
end

ManyUITUI.make_driver(b::ImGuiTUIBackend)::ImGuiTUIDriver =
    ImGuiTUIDriver(b.size; depth = b.depth, buffer = b.buffer)

"""
    launch_tui(factory; kwargs...)

Launch a ManyUI widget FACTORY inside a Dear ImGui window, rendering the
TUI cell grid with ImDrawList. Requires the optional CImGui / GLFW /
ModernGL extension to be loaded.

Returns the exit code of the ManyUI `App` loop once the ImGui window is
closed. With `wait = false`, returns the running `App` handle instead.
"""
function launch_tui end

"""
    launch_tui_app!(app; kwargs...)

Run an ALREADY-BUILT ManyUI `App` (constructed with an
[`ImGuiTUIDriver`](@ref)) inside a Dear ImGui window. For animated demos,
pass `on_tick` and `tick_interval`.
"""
function launch_tui_app! end

const _TUI_NATIVE_AVAILABLE = Ref(false)
tui_native_available()::Bool = _TUI_NATIVE_AVAILABLE[]

function launch_tui(factory; kwargs...)
    throw(ArgumentError("ManyUICImGui.launch_tui requires the optional " *
                        "CImGui, GLFW and ModernGL dependencies"))

end

function launch_tui_app!(app; kwargs...)
    throw(ArgumentError("ManyUICImGui.launch_tui_app! requires the " *
                        "optional CImGui, GLFW and ModernGL dependencies"))
end