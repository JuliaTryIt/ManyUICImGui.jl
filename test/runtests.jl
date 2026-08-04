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

@testitem "HarfBuzz shaping coverage for TUI cells" begin
    # This test exercises the text-shaping foundation that the
    # ManyUICImGuiCImGuiExt font selector (`_hb_full_coverage`) relies
    # on. The extension itself needs CImGui/GLFW/ModernGL and a display
    # to load, so it cannot be loaded headless; here we verify the
    # underlying HarfBuzz shaping pipeline produces reliable glyph IDs
    # for whole grapheme clusters (combining marks, ligatures), which
    # is the property the per-cell font fallback in `_paint_buffer!`
    # depends on.
    import HarfBuzz

    # Cross-platform font discovery via HarfBuzz's family-name ctor
    # (uses FreeTypeAbstraction internally). Skip if no system mono
    # font is reachable.
    families = ["Menlo", "DejaVu Sans Mono", "Consolas",
                "Liberation Mono", "Courier New", "Monaco",
                "Noto Sans Mono"]
    hb_font = let found = nothing
        for fam in families
            try
                found = HarfBuzz.HbFont(fam, 18)
                break
            catch
            end
        end
        found
    end

    if hb_font === nothing
        @test_skip true
    else
        # A plain ASCII cluster shapes to exactly one non-zero glyph.
        r_ascii = HarfBuzz.shape(hb_font, "A")
        @test !isempty(r_ascii.infos)
        @test all(g.glyph_id != UInt32(0) for g in r_ascii.infos)

        # A grapheme cluster with a combining mark ("e" + U+0301)
        # shapes to one or more glyphs; whatever the count, the
        # coverage property the selector uses is "all glyph_id != 0".
        r_comb = HarfBuzz.shape(hb_font, "e\u0301")
        @test !isempty(r_comb.infos)

        # `has_glyph` on the base codepoint is what the OLD selector
        # did. Shaping is a refinement: it can only ever reject MORE
        # clusters than `has_glyph` (a missing combining mark makes
        # coverage false while `has_glyph('e')` is true), never fewer.
        # Assert the refinement invariant for the base codepoint.
        @test HarfBuzz.has_glyph(hb_font, UInt32('e')) ||
              !all(g.glyph_id != UInt32(0) for g in r_comb.infos)
    end
end

@run_package_tests
