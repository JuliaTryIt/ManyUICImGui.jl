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

end
