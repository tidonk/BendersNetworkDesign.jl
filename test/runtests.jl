"""
BendersNetworkDesign Test Suite

Run all tests for the BendersNetworkDesign package.
"""

using Test
using JuMP
using Printf

# Load module once
include("../src/BendersNetworkDesign.jl")
using .BendersNetworkDesign

println("="^70)
println("BendersNetworkDesign Test Suite")
println("="^70)

# Define TEST_DIR and DATA_DIR for all test files
const TEST_DIR = @__DIR__
const DATA_DIR = abspath(joinpath(TEST_DIR, "..", "data"))

@testset "All Tests" begin
    # Settings Tests
    @testset "Settings Tests" begin
        @testset "Read default settings" begin
            settings = read_settings()
            
            @test settings.solver isa Symbol
            @test settings.subproblem_ordering isa String
            @test settings.scoring_weights isa Vector{Float64}
            @test settings.time_limit isa Number
            @test settings.stabilization_frequency isa Int
        end
    end
    
    # SNDlib Reader Tests
    @testset "SNDlib Reader Tests" begin
        @testset "Data structures" begin
            node = Node("A", 10.5, 20.3)
            @test node.id == "A"
            @test node.x == 10.5
            @test node.y == 20.3
        end
    end
    
    # TA2 Compact Model Test
    #@testset "TA2 Compact Model" begin
    #    include("test_ta2_compact.jl")
    #end
    
    # France Optimal Tests
    #@testset "France Optimal Tests" begin
    #    include("test_france_optimal.jl")
    #end
    
    # TODO: These tests take too long for the full test suite
    # # New York Compact Model Test
    # @testset "New York Compact Model" begin
    #     include("test_newyork_compact.jl")
    # end
    
    # Benders Cut Limit Test
    @testset "Benders with Cut Limits" begin
        include("test_benders_cut_limit.jl")
    end
    
    # Adaptive Mechanism Test
    @testset "Adaptive Mechanism" begin
        include("test_adaptive_phase.jl")
    end
    
    # Benders vs Compact Equivalence Test
    @testset "Benders vs Compact (No Survivability)" begin
        include("test_benders_vs_compact.jl")
    end
    
    # Known Optimal Values Test
    @testset "Known Optimal Values" begin
        include("test_known_objectives.jl")
    end
    
    @testset "ML Training and Testing Workflow" begin
        include("test_ml_train_and_test.jl")
    end
    
    # Oracle Recording and Replay Test
    #@testset "Oracle Recording and Replay" begin
    #    include("test_oracle.jl")
    #end
end

println("\n" * "="^70)
println("All tests completed!")
println("Run individual test files for detailed output:")
println("  julia --project=. tests/test_settings.jl")
println("  julia --project=. tests/test_sndlib.jl")
println("  julia --project=. tests/test_ta2_compact.jl")
println("  julia --project=. tests/test_france_optimal.jl")
println("  julia --project=. tests/test_newyork_compact.jl")
println("  julia --project=. tests/test_benders_cut_limit.jl")
println("  julia --project=. tests/test_benders_vs_compact.jl")
println("  julia --project=. tests/test_known_objectives.jl")
println("  julia --project=. tests/test_ml_train_and_test.jl")
println("="^70)
