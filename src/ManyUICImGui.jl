module ManyUICImGui

using ManyUI
using ManyUITUI

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

"""Launch a native Dear ImGui render function when the optional CImGui
extension is loaded."""
const _NATIVE_AVAILABLE = Ref(false)
native_available()::Bool = _NATIVE_AVAILABLE[]

function launch_imgui(ui::Function, args...; kwargs...)
    throw(ArgumentError("ManyUICImGui native support requires CImGui, GLFW and ModernGL; install the optional graphics dependencies"))
end

"""Launch a ManyUI widget factory once the optional ImGui extension is loaded."""
function launch_manyui(ui::Function, args...; kwargs...)
    throw(ArgumentError("ManyUICImGui native support requires CImGui, GLFW and ModernGL; install the optional graphics dependencies"))
end

end
