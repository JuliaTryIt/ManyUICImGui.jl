using TestItemRunner

@testitem "Aqua.jl" begin
    import Aqua
    import ManyUICImGui
    Aqua.test_all(ManyUICImGui)
end

@testitem "ImGui driver lifecycle and event seam" begin
    import ManyUI
    import ManyUITUI
    import ManyUICImGui

    backend = ManyUICImGui.ImGuiBackend(; size=ManyUI.Size(100, 40))
    driver = ManyUITUI.make_driver(backend)

    @test ManyUITUI.check_driver_interface(typeof(driver)) == Symbol[]
    @test !isopen(driver)
    ManyUITUI.start!(driver)
    @test isopen(driver)
    @test ManyUITUI.display_size(driver) == ManyUI.Size(100, 40)
    @test ManyUITUI.capabilities(driver).mouse

    ManyUICImGui.push_event!(driver, ManyUI.FocusEvent(true))
    @test take!(ManyUITUI.events(driver)) == ManyUI.FocusEvent(true)

    ManyUICImGui.resize!(driver, ManyUI.Size(120, 50))
    @test ManyUITUI.display_size(driver) == ManyUI.Size(120, 50)
    @test take!(ManyUITUI.events(driver)) == ManyUI.ResizeEvent(ManyUI.Size(120, 50))

    ManyUITUI.emit!(driver, UInt8[0x41, 0x42])
    @test ManyUICImGui.take_output!(driver) == UInt8[0x41, 0x42]
    close(driver)
    @test !isopen(driver)
end

@testitem "Native support reports an actionable optional-dependency error" begin
    import ManyUICImGui
    @test !ManyUICImGui.native_available()
    err = try
        ManyUICImGui.launch_manyui(() -> nothing)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("CImGui", sprint(showerror, err))
end

@testitem "Backend availability and capabilities are portable" begin
    import ManyUI
    import ManyUITUI
    import ManyUICImGui

    tui = ManyUITUI.TerminalBackend()
    imgui = ManyUICImGui.ImGuiBackend()
    @test ManyUI.backend_available(tui)
    @test ManyUI.backend_kind(tui) == :tui
    @test ManyUI.backend_kind(imgui) == :imgui
    @test hasproperty(ManyUI.backend_capabilities(imgui), :native_window)
    @test !ManyUI.backend_available(imgui)
end

@testitem "ImGuiTUI backend descriptor and driver seam" begin
    import ManyUI
    import ManyUITUI
    import ManyUICImGui

    backend = ManyUICImGui.ImGuiTUIBackend(; size=ManyUI.Size(100, 40))
    driver = ManyUITUI.make_driver(backend)

    @test ManyUITUI.check_driver_interface(typeof(driver)) == Symbol[]
    @test !isopen(driver)
    ManyUITUI.start!(driver)
    @test isopen(driver)
    @test ManyUITUI.display_size(driver) == ManyUI.Size(100, 40)
    @test ManyUITUI.capabilities(driver).mouse
    @test ManyUITUI.capabilities(driver).unicode

    ManyUICImGui.push_event!(driver, ManyUI.FocusEvent(true))
    @test take!(ManyUITUI.events(driver)) == ManyUI.FocusEvent(true)

    ManyUICImGui.resize!(driver, ManyUI.Size(120, 50))
    @test ManyUITUI.display_size(driver) == ManyUI.Size(120, 50)
    @test take!(ManyUITUI.events(driver)) == ManyUI.ResizeEvent(ManyUI.Size(120, 50))

    # emit! is a no-op sink (the CImGui extension reads app.back directly).
    @test ManyUITUI.emit!(driver, UInt8[0x41, 0x42]) == 2
    close(driver)
    @test !isopen(driver)
end

@testitem "ImGuiTUI backend kind and capabilities" begin
    import ManyUI
    import ManyUICImGui

    backend = ManyUICImGui.ImGuiTUIBackend()
    @test ManyUI.backend_kind(backend) == :cimguitui
    caps = ManyUI.backend_capabilities(backend)
    @test hasproperty(caps, :native_window)
    @test hasproperty(caps, :transparency)
    # backend_available is false until the CImGui extension loads.
    @test !ManyUI.backend_available(backend)
end

@testitem "launch_tui reports an actionable error without the graphics deps" begin
    import ManyUICImGui
    err = try
        ManyUICImGui.launch_tui(() -> nothing)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("CImGui", sprint(showerror, err))
end

@run_package_tests
