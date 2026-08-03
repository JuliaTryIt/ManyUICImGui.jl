module ManyUICImGuiCImGuiExt

using ManyUICImGui
import CImGui
import GLFW
import ModernGL

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
    spawn = wait ? false : 1
    CImGui.render(ui, ctx; window_size=(Int(width), Int(height)),
                  window_title=String(title), spawn=spawn, wait=wait)
end

end
