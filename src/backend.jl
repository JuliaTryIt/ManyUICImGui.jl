# backend.jl -- ManyUI backend descriptor.

"""
    ImGuiBackend(; size=Size(80, 24), depth=ColorDepth.TRUECOLOR, buffer=256)

Describe a Dear ImGui target. The descriptor is inert; `make_driver` creates a
fresh driver for each launch, matching the `ManyUITUI.Backend` contract. The
native CImGui/GLFW window is intentionally not created until the optional
renderer phase is enabled.
"""
struct ImGuiBackend <: ManyUITUI.Backend
    size::Size
    depth::ManyUI.ColorDepth.T
    buffer::Int
end

ManyUI.backend_available(::ImGuiBackend) = native_available()
ManyUI.backend_kind(::ImGuiBackend) = :imgui
ManyUI.backend_capabilities(::ImGuiBackend) = merge(
    ManyUI.DEFAULT_BACKEND_CAPABILITIES,
    (transparency = true, native_window = true, gpu = native_available(),
     multi_session = false))

function ImGuiBackend(; size::Size=Size(80, 24),
                      depth::ManyUI.ColorDepth.T=ManyUI.ColorDepth.TRUECOLOR,
                      buffer::Int=256)::ImGuiBackend
    buffer > 0 || throw(ArgumentError("buffer must be positive"))
    ImGuiBackend(size, depth, buffer)
end

ManyUITUI.make_driver(b::ImGuiBackend)::ImGuiDriver =
    ImGuiDriver(b.size; depth=b.depth, buffer=b.buffer)
