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

@testitem "A stopped App ends the ImGui render loop" begin
    # The regression: `_tui_render_callback` always returned `nothing`,
    # and the CImGui render loop only stops on `:imgui_exit_loop` (or
    # the OS window close button). So `quit!` -- what the hub's Launch
    # and Quit buttons call -- stopped the App while the window stayed
    # up, painting a dead App. Every click looked like it did nothing.
    #
    # The decision lives in `src` and not in the extension precisely so
    # it can be tested without a GPU: the extension only has to ask.
    import ManyUICImGui

    # Alive and open -> keep rendering.
    @test ManyUICImGui._tui_exit_signal(true, true) === nothing
    # `quit!` stopped the App -> tell the render loop to stop too.
    @test ManyUICImGui._tui_exit_signal(false, true) === :imgui_exit_loop
    # The ImGui window itself was closed -> same.
    @test ManyUICImGui._tui_exit_signal(true, false) === :imgui_exit_loop
    @test ManyUICImGui._tui_exit_signal(false, false) === :imgui_exit_loop
end

@testitem "request_close! is a no-op without the graphics deps" begin
    # The native (`launch_manyui`) path has no App to stop, so a caller
    # that wants the window gone -- the hub's Launch button -- asks for
    # it directly. Without the extension there is no window, and asking
    # must not throw: the hub calls this from every backend.
    import ManyUICImGui

    @test ManyUICImGui.request_close!() === false
end

@testitem "Ligature clusters are split out of a line of text" begin
    # The native (`launch_manyui`) path draws whole strings with
    # `TextUnformatted`, which is codepoint-by-codepoint: no GSUB, so
    # 👨‍👩‍👧‍👦 came out as four separate faces and 🇫🇷 as the letters F R.
    # Those clusters have to be drawn by the shaping path instead, which
    # means finding them in the middle of ordinary text first.
    import ManyUICImGui
    split = ManyUICImGui._split_ligature_pieces

    # Nothing to shape: one piece, untouched.
    @test split("plain ascii") == [(false, "plain ascii")]
    @test split("") == Tuple{Bool,String}[]

    # A ZWJ family is one piece, and the text around it survives intact.
    @test split("famille 👨‍👩‍👧‍👦 fin") ==
          [(false, "famille "), (true, "👨‍👩‍👧‍👦"), (false, " fin")]

    # A regional-indicator PAIR is one cluster (a flag), not two letters.
    @test split("🇫🇷") == [(true, "🇫🇷")]

    # A single emoji needs no shaping -- `TextUnformatted` draws it --
    # so it must NOT be split out, or every emoji would pay for it.
    @test split("😀") == [(false, "😀")]
    @test split("cjk 漢字 et é") == [(false, "cjk 漢字 et é")]

    # Two clusters in a row stay separate pieces: each is shaped alone.
    @test split("👨‍👩‍👧‍👦🇫🇷") == [(true, "👨‍👩‍👧‍👦"), (true, "🇫🇷")]

    # Every piece concatenated back must reproduce the input exactly --
    # the drawer relies on this to not lose or duplicate text.
    for s in ("", "plain", "a👨‍👩‍👧‍👦b🇫🇷c", "👨‍👩‍👧‍👦", "é😀漢")
        @test join(last.(split(s))) == s
    end
end

@testitem "Only text containing a ligature cluster needs shaping" begin
    # The shaped path costs a per-cluster draw call and an overlaid
    # Selectable, so it must be taken ONLY when it changes the result.
    # Every ordinary label -- which is nearly all of them -- stays on
    # the plain path.
    import ManyUICImGui
    needs = ManyUICImGui._needs_shaping

    @test !needs("")
    @test !needs("Launch in Terminal")
    @test !needs("😀 emoji")          # single codepoint: drawn correctly already
    @test !needs("漢字 CJK")
    @test needs("👨‍👩‍👧‍👦")
    @test needs("regional 🇫🇷 indicators")
end

@testitem "A ZWJ sequence is one ligature cluster, a lone emoji is not" begin
    import ManyUICImGui
    lig = ManyUICImGui._is_ligature_cluster

    @test lig("👨‍👩‍👧‍👦")          # ZWJ sequence
    @test lig("🇫🇷")           # two regional indicators
    @test !lig("😀")           # one codepoint, nothing to join
    @test !lig("a")
    @test !lig("漢")
    # ONE regional indicator is not a flag -- no ligature to form.
    @test !lig("🇫")
end

@run_package_tests
