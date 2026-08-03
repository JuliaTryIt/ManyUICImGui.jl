module ManyUICImGuiCImGuiExt

using ManyUICImGui
import CImGui
import GLFW
import ModernGL
import ManyUI

ManyUICImGui.native_available() = true

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

end
