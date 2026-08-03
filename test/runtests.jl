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

@run_package_tests
