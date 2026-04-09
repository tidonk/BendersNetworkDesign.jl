"""
Unit tests for settings reader and configuration management
"""

include("common.jl")

@testset "Settings Tests" begin
    
    @testset "Read default settings" begin
        settings = read_settings()
        
        @test settings.solver isa Symbol
        @test settings.solver == :Gurobi
        @test settings.optimizer !== nothing
        
        @test settings.subproblem_selection isa String
        @test settings.subproblem_selection ∈ ["all", "most_violated", "random", "round_robin"]
        
        @test settings.cut_selection isa String
        @test settings.cut_selection ∈ ["all", "strongest", "top_k", "threshold"]
        
        @test settings.cut_selection_k isa Int
        @test settings.cut_selection_k > 0
        
        @test settings.cut_selection_threshold isa Float64
        @test settings.cut_selection_threshold > 0
        
        println("✓ Default settings loaded correctly")
    end
    
    @testset "Optimizer retrieval" begin
        # Test Gurobi optimizer
        if BendersNetworkDesign.GUROBI_AVAILABLE
            opt = get_optimizer(:Gurobi)
            @test opt !== nothing
            println("✓ Gurobi optimizer available")
        else
            @test_throws ErrorException get_optimizer(:Gurobi)
            println("✓ Gurobi not available - error thrown as expected")
        end
    end
    
    @testset "Settings structure" begin
        settings = read_settings()
        
        # Test that all fields are accessible
        @test hasfield(typeof(settings), :solver)
        @test hasfield(typeof(settings), :optimizer)
        @test hasfield(typeof(settings), :subproblem_selection)
        @test hasfield(typeof(settings), :cut_selection)
        @test hasfield(typeof(settings), :cut_selection_k)
        @test hasfield(typeof(settings), :cut_selection_threshold)
        
        println("✓ Settings structure complete")
    end
    
    @testset "Benders parameters validation" begin
        settings = read_settings()
        
        # Valid subproblem selection strategies
        valid_subproblem = ["all", "most_violated", "random", "round_robin"]
        @test settings.subproblem_selection ∈ valid_subproblem
        
        # Valid cut selection strategies
        valid_cut = ["all", "strongest", "top_k", "threshold"]
        @test settings.cut_selection ∈ valid_cut
        
        # Parameter bounds
        @test 1 <= settings.cut_selection_k <= 1000
        @test 0.0 < settings.cut_selection_threshold <= 1.0
        
        println("✓ Benders parameters validated")
    end
end
