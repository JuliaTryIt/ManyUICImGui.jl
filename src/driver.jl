# driver.jl -- backend-neutral ImGui driver seam.

"""
    ImGuiDriver

The lifecycle and input seam for the Dear ImGui projection. The current
implementation is deliberately headless: `emit!` records the generic ManyUI
frame bytes while the native CImGui renderer is added in a later phase. This
keeps the package testable on CI machines without a windowing system.
"""
mutable struct ImGuiDriver <: Driver
    size::Size
    caps::DriverCaps
    buffer::Vector{UInt8}
    input::Channel{ManyUI.Event}
    open::Bool
    started::Bool
end

function ImGuiDriver(size::Size = Size(80, 24);
                     depth::ManyUI.ColorDepth.T = ManyUI.ColorDepth.TRUECOLOR,
                     buffer::Int = 256)::ImGuiDriver
    buffer > 0 || throw(ArgumentError("buffer must be positive"))
    ImGuiDriver(size,
                DriverCaps(; color_depth=depth, mouse=true,
                            bracketed_paste=false, focus_events=true,
                            alt_screen=false, title=true, unicode=true,
                            sync_output=false),
                UInt8[], Channel{ManyUI.Event}(buffer), false, false)
end

function start!(d::ImGuiDriver, size_hint::Union{Nothing,Size}=nothing)::Nothing
    size_hint === nothing || (d.size = size_hint)
    d.open = true
    d.started = true
    nothing
end

function stop!(d::ImGuiDriver)::Nothing
    d.open = false
    isopen(d.input) && close(d.input)
    nothing
end

function restore!(d::ImGuiDriver)::Nothing
    try
        stop!(d)
    catch
        d.open = false
    end
    nothing
end

function emit!(d::ImGuiDriver, bytes::AbstractVector{UInt8})::Int
    d.open || return 0
    append!(d.buffer, bytes)
    length(bytes)
end

flush!(::ImGuiDriver)::Nothing = nothing
display_size(d::ImGuiDriver)::Size = d.size
capabilities(d::ImGuiDriver)::DriverCaps = d.caps
events(d::ImGuiDriver)::Channel{ManyUI.Event} = d.input
Base.isopen(d::ImGuiDriver)::Bool = d.open

"""Queue a canonical ManyUI event for the ImGui input adapter."""
function push_event!(d::ImGuiDriver, event::ManyUI.Event)::Nothing
    d.open || return nothing
    isopen(d.input) && put!(d.input, event)
    nothing
end

function notify_resize!(d::ImGuiDriver, size::Size)::Nothing
    d.size = size
    push_event!(d, ManyUI.ResizeEvent(size))
    nothing
end

function resize!(d::ImGuiDriver, size::Size)::Nothing
    notify_resize!(d, size)
end

"""Return and clear bytes emitted since the previous call."""
function take_output!(d::ImGuiDriver)::Vector{UInt8}
    out = copy(d.buffer)
    empty!(d.buffer)
    out
end

clear_output!(d::ImGuiDriver)::Nothing = (empty!(d.buffer); nothing)
