"""
Test adaptive mechanism with default configuration.

Uses the benders_adaptive.toml settings to test the adaptive selection strategy.
"""

include("common.jl")

using Printf
using JuMP
using Gurobi

# Initialize Gurobi environment
GRB_ENV = init_gurobi_env()

"""
Test adaptive mechanism on small Abilene network
"""
function test_adaptive_abilene()
    
    println("\n" * "="^80)
    println("Testing: Adaptive Mechanism (Abilene)")
    println("="^80)
    
    # Load network
    network_file = joinpath(DATA_DIR, "sndlib", "abilene.xml")
    @test isfile(network_file)
    
    println("\nLoading network from: $network_file")
    network = read_sndlib_network(network_file)
    
    println("Network: $(length(network.network_structure.nodes)) nodes, $(length(network.network_structure.links)) links")
    
    # Use 5 outage scenarios for quick testing
    num_outages = 5
    outage_scenarios = sample_outage_scenarios(network, num_outages; include_base_case=false)
    println("Outage scenarios: $(length(outage_scenarios))")
    
    # Optimizer settings
    optimizer = () -> Gurobi.Optimizer(GRB_ENV[])
    
    # Solve with default adaptive settings
    println("\n--- Solving with ADAPTIVE mechanism ---")
    settings = read_settings(joinpath(@__DIR__, "..", "settings", "test", "benders_adaptive.toml"))
    
    # Verify settings use adaptive strategy
    @test settings.selection_strategy == "adaptive"
    
    result = solve_benders(network; 
                          optimizer=optimizer, 
                          settings=settings, 
                          outage_scenarios=outage_scenarios)
    
    # Print results
    println("\n--- Results ---")
    println("Status: $(result.status)")
    println("Objective: $(round(result.objective_value, digits=2))")
    println("Iterations: $(result.iterations)")
    println("Total cuts: $(result.total_cuts_added)")
    
    # Verify solution is valid
    @test result.status == OPTIMAL
    @test isfinite(result.objective_value)
    @test result.objective_value > 0
    @test result.iterations > 0
    @test result.total_cuts_added > 0
    
    println("\n✓ Adaptive mechanism test passed")
end

@testset "Adaptive Mechanism" begin
    test_adaptive_abilene()
end
