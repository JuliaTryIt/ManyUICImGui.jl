using TestItemRunner

@testitem "Aqua.jl" begin
    import Aqua
    import ManyUICImGui
    Aqua.test_all(ManyUICImGui)
end

@run_package_tests
