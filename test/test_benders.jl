"""
Tests for Benders decomposition implementation
"""

include("common.jl")

using JuMP
using Printf

@testset "Benders Decomposition Tests" begin
    
    @testset "Subproblem setup and modification" begin
        println("\n" * "="^80)
        println("Testing Benders subproblem structure")
        println("="^80)
        
        network_file = joinpath(DATA_DIR, "sndlib", "ta2.xml")
        network = read_sndlib_network(network_file)
        
        base_scenario = Dict{String, Float64}()
        for (did, demand) in network.demands
            base_scenario[did] = demand.demand_value
        end
        
        settings = read_settings()
        sp = BendersNetworkDesign.build_subproblem(network, base_scenario; optimizer=settings.optimizer)
        
        @test sp.model isa Model
        @test !isempty(sp.f)
        @test !isempty(sp.capacity_constraints)
        @test length(sp.capacity_constraints) == length(sp.links)
        
        y_values = Dict((l, 1) => 1.0 for l in sp.links)
        link_modules = Dict{String, Vector{Tuple{Int, Float64, Float64}}}()
        for l in sp.links
            link_modules[l] = [(1, 1000.0, 100.0)]
        end
        
        # Test with no failures (empty set)
        BendersNetworkDesign.update_subproblem!(sp, y_values, link_modules, Set{Int}())
        for l in sp.links
            @test sp.base_capacities[l] == 1000.0
        end
        
        # Test with first link failed (index 1)
        BendersNetworkDesign.update_subproblem!(sp, y_values, link_modules, Set{Int}([1]))
        failed_link = sp.links[1]
        @test normalized_rhs(sp.capacity_constraints[failed_link]) == 0.0
        
        BendersNetworkDesign.reset_subproblem!(sp)
        for l in sp.links
            @test normalized_rhs(sp.capacity_constraints[l]) == sp.base_capacities[l]
        end
        
        # Test that constraint references are stored correctly
        @test length(sp.capacity_constraints) == length(sp.links)
        @test length(sp.flow_conservation) >= length(sp.demands) * length(sp.nodes)
        
        println("✓ Subproblem setup and modification working correctly")
    end
    
    @testset "Benders callback execution" begin
        println("\n" * "="^80)
        println("Testing Benders callback execution")
        println("="^80)
        
        network_file = joinpath(DATA_DIR, "sndlib", "abilene.xml")
        network = read_sndlib_network(network_file)
        
        # Create base case scenario only (no outages)
        base_case = [OutageScenario(0, Int[])]
        
        settings = read_settings()
        
        println("\nTesting Benders with base case only (no outages)...")
        benders_result = solve_benders(network; 
                                      optimizer=settings.optimizer,
                                      outage_scenarios=base_case,
                                      max_cuts_per_iteration=5)
        
        println("Benders solution:")
        println("  Status: ", benders_result.status)
        println("  Objective: ", @sprintf("%.2f", benders_result.objective_value))
        println("  Iterations: ", benders_result.iterations)
        println("  Modules installed: ", length(benders_result.y_solution))
        
        @test benders_result.objective_value < Inf
        @test !isempty(benders_result.y_solution) || benders_result.status == MOI.INFEASIBLE
        
        println("\n✓ Benders decomposition callback executed successfully")
        println("="^80)
    end
end
