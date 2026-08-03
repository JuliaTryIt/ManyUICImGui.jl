module ManyUICImGui

using ManyUI
using ManyUITUI

import Base: close, isopen
import ManyUITUI: Driver, DriverCaps, DriverInterfaceError, Size,
    capabilities, display_size, emit!, events, flush!, notify_resize!,
    restore!, start!, stop!

include("driver.jl")
include("backend.jl")

export ImGuiBackend, ImGuiDriver
export push_event!, resize!, take_output!, clear_output!
export launch_imgui
export launch_manyui

"""Launch a native Dear ImGui render function when the optional CImGui
extension is loaded."""
function launch_imgui end

"""Launch a ManyUI widget factory once the optional ImGui extension is loaded."""
function launch_manyui end

end
