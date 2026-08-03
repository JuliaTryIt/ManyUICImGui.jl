using ManyUICImGui
using Test
using Aqua

@testset "ManyUICImGui.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(ManyUICImGui)
    end
    # Write your tests here.
end
