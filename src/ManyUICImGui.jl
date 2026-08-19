module ManyUICImGui

using ManyUI
using ManyUITUI

# Grapheme clusters (UAX #29): what makes a ZWJ emoji sequence ONE
# piece of text rather than seven codepoints. See `_split_ligature_pieces`.
using Base.Unicode: graphemes

import Base: close, isopen
import ManyUITUI: Driver, DriverCaps, DriverInterfaceError, Size,
    capabilities, display_size, emit!, events, flush!, notify_resize!,
    restore!, start!, stop!

include("driver.jl")
include("backend.jl")
include("cimguitui.jl")

export ImGuiBackend, ImGuiDriver
export ImGuiTUIBackend, ImGuiTUIDriver
export push_event!, resize!, take_output!, clear_output!
export launch_imgui
export launch_manyui
export launch_tui, launch_tui_app!
export native_available
export request_close!

"""Launch a native Dear ImGui render function when the optional CImGui
extension is loaded."""
const _NATIVE_AVAILABLE = Ref(false)
native_available()::Bool = _NATIVE_AVAILABLE[]

function launch_imgui(ui::Function, args...; kwargs...)
    throw(ArgumentError("ManyUICImGui native support requires CImGui, GLFW, HarfBuzz and ModernGL; install the optional graphics dependencies"))
end

"""Launch a ManyUI widget factory once the optional ImGui extension is loaded."""
function launch_manyui(ui::Function, args...; kwargs...)
    throw(ArgumentError("ManyUICImGui native support requires CImGui, GLFW, HarfBuzz and ModernGL; install the optional graphics dependencies"))
end

"""
The extension's window-closer, installed by `ManyUICImGuiCImGuiExt.__init__`.
`nothing` while the extension is asleep, which is when there is no window.

A Ref and not a second method: `request_close!()` takes no arguments, so
a stub here and a method there would share a signature exactly, and the
extension overwriting it is an ERROR during precompilation ("Method
overwriting is not permitted") -- unlike `launch_tui`, whose stub and
real method differ in their argument types.
"""
const _CLOSE_REQUESTER = Ref{Union{Nothing,Function}}(nothing)

"""
The atlas font used to SHAPE ligature clusters, set by the extension
when it builds the font atlas. `Ptr{Cvoid}` because `ImFont` is a type
the extension owns; `C_NULL` while no atlas has been built.

It is deliberately NOT the merged font the native path draws ordinary
text with: shaping a merged font renders nothing. See `_load_fonts!`.
"""
const _SHAPED_EMOJI_FONT = Ref{Ptr{Cvoid}}(C_NULL)

"""
    request_close!() -> Bool

Ask the ImGui window that is currently rendering to close, and report
whether there was one. `false` when the extension is not loaded, or
when it is loaded but no window is rendering.

For the NATIVE (`launch_manyui`) path, which projects widgets straight
into ImGui and has no `App` behind them: a button callback that means
"we are done with this window" has nothing to `quit!`, so it asks. The
TUI path does not need it -- stopping its `App` is enough, see
`_tui_exit_signal`.

Callers may run under any backend, so this must never throw.
"""
function request_close!()::Bool
    f = _CLOSE_REQUESTER[]
    f === nothing && return false
    return try
        f()::Bool
    catch
        false
    end
end

end
