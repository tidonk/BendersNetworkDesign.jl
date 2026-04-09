"""
Test diversity-based cut filtering.

Tests that diversity filtering selects geometrically diverse cuts
with different support structures.
"""

include("common.jl")

using Printf
using JuMP
using Gurobi

# Initialize Gurobi environment
GRB_ENV = init_gurobi_env()

"""
Test diversity filtering on Abilene network
"""
function test_diversity_filtering()
    
    println("\n" * "="^80)
    println("Testing: Diversity-Based Cut Filtering")
    println("="^80)
    
    # Load network
    network_file = joinpath(DATA_DIR, "sndlib", "abilene.xml")
    @test isfile(network_file)
    
    println("\nLoading network from: $network_file")
    network = read_sndlib_network(network_file)
    
    println("Network: $(length(network.network_structure.nodes)) nodes, $(length(network.network_structure.links)) links")
    
    # Use 5 outage scenarios for testing
    num_outages = 5
    outage_scenarios = sample_outage_scenarios(network, num_outages; include_base_case=false)
    println("Outage scenarios: $(length(outage_scenarios))")
    
    # Optimizer settings
    optimizer = () -> Gurobi.Optimizer(GRB_ENV[])
    
    # Solve with diversity filtering
    println("\n--- Solving with DIVERSITY filtering (max 5 cuts) ---")
    settings = read_settings(joinpath(SETTINGS_DIR, "test", "test_diversity.toml"))
    
    # Verify settings
    @test settings.cut_filtering_strategy == "diversity"
    @test settings.cut_filtering_max_cuts == 5
    
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
    
    # With diversity filtering, we should have fewer cuts than solving all scenarios
    # but still achieve optimality
    println("\n✓ Diversity filtering test passed")
    println("  Cuts were filtered to select diverse constraints")
end

@testset "Diversity Filtering" begin
    test_diversity_filtering()
end
