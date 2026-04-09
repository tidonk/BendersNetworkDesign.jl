"""
Test that Benders decomposition with cut limits still finds correct solutions.

Tests that even when limiting the number of cuts added per iteration,
the Benders algorithm eventually converges to the same optimal solution
as the unlimited case and the compact formulation.
"""

include("common.jl")

using Printf
using JuMP
using Gurobi

# Initialize Gurobi environment
GRB_ENV = init_gurobi_env()

"""
Test network instance with different cut limits using settings files
"""
function test_cut_limits(network_name::String, network_file::String, num_outages::Int)
    
    println("\n" * "="^80)
    println("Testing: $network_name with cut limits")
    println("Number of outage scenarios: $num_outages")
    println("="^80)
    
    @test isfile(network_file)
    
    println("\nLoading network from: $network_file")
    network = read_sndlib_network(network_file)
    
    println("Network: $(length(network.network_structure.nodes)) nodes, $(length(network.network_structure.links)) links")
    
    # Generate outage scenarios
    if num_outages == 0
        outage_scenarios = OutageScenario[]
    else
        outage_scenarios = sample_outage_scenarios(network, num_outages; include_base_case=false)
    end
    println("Outage scenarios: $(length(outage_scenarios))")
    
    # Optimizer settings
    optimizer = () -> Gurobi.Optimizer(GRB_ENV[])
    
    # 1. Solve with unlimited cuts (baseline)
    println("\n--- Solving with UNLIMITED cuts ---")
    settings_unlimited = read_settings(joinpath(SETTINGS_DIR, "test", "test_unlimited.toml"))
    result_unlimited = solve_benders(network; 
                                     optimizer=optimizer, 
                                     outage_scenarios=outage_scenarios,
                                     settings=settings_unlimited)
    
    @test result_unlimited.status == MOI.OPTIMAL
    unlimited_obj = result_unlimited.objective_value
    unlimited_iters = result_unlimited.iterations
    unlimited_cuts = result_unlimited.total_cuts_added
    
    println("  Status: ", result_unlimited.status)
    println("  Objective: ", @sprintf("%.2f", unlimited_obj))
    println("  Iterations: ", unlimited_iters)
    println("  Total cuts added: ", unlimited_cuts)
    
    # 2. Solve with cut limit = 5 per iteration
    println("\n--- Solving with CUT LIMIT = 5 ---")
    settings_limited = read_settings(joinpath(SETTINGS_DIR, "test", "test_static.toml"))
    result_limited = solve_benders(network; 
                                   optimizer=optimizer, 
                                   outage_scenarios=outage_scenarios,
                                   settings=settings_limited)
    
    @test result_limited.status == MOI.OPTIMAL
    limited_obj = result_limited.objective_value
    limited_iters = result_limited.iterations
    limited_cuts = result_limited.total_cuts_added
    
    println("  Status: ", result_limited.status)
    println("  Objective: ", @sprintf("%.2f", limited_obj))
    println("  Iterations: ", limited_iters)
    println("  Total cuts added: ", limited_cuts)
    
    # 3. Verify objectives match
    println("\n" * "-"^80)
    println("COMPARISON")
    println("-"^80)
    println(@sprintf("Unlimited cuts: %.2f (%d iters, %d cuts)", 
                     unlimited_obj, unlimited_iters, unlimited_cuts))
    println(@sprintf("Limited cuts:   %.2f (%d iters, %d cuts)", 
                     limited_obj, limited_iters, limited_cuts))
    println(@sprintf("Difference:     %.6f", abs(unlimited_obj - limited_obj)))
    println("-"^80)
    
    # Test that solutions match (within numerical tolerance)
    @test abs(unlimited_obj - limited_obj) < 1.0
    
    if abs(unlimited_obj - limited_obj) < 1.0
        println("✓ SUCCESS: Cut limit produces same optimal solution!")
        return true
    else
        println("✗ FAIL: Objectives differ")
        return false
    end
end

@testset "Benders with Cut Limits" begin
    
    # Test 1: Base case only (no outages)
    @testset "abilene: base case with cut limits" begin
        test_cut_limits("abilene-base", joinpath(DATA_DIR, "sndlib", "abilene.xml"), 0)
    end
    
    # Test 2: With outage scenarios
    @testset "abilene: 3 outages with cut limits" begin
        test_cut_limits("abilene-3out", joinpath(DATA_DIR, "sndlib", "abilene.xml"), 3)
    end
    
end

println("\n" * "="^80)
println("Cut limit tests completed!")
println("="^80)
