"""
Test to verify our compact.jl formulation matches expected results for TA2
Expected objective: 37871728.59
"""

include("common.jl")

using Printf
const MOI = JuMP.MOI

@testset "ta2 Network Test" begin
    println("\n" * "="^80)
    println("Testing ta2 network with compact formulation")
    println("="^80)
    
    # Load ta2 network
    network_file = joinpath(DATA_DIR, "sndlib", "ta2.xml")
    @test isfile(network_file)
    
    println("\nLoading network from: $network_file")
    network = read_sndlib_network(network_file)
    
    println("Network loaded:")
    println("  Nodes: ", length(network.network_structure.nodes))
    println("  Links: ", length(network.network_structure.links))
    println("  Demands: ", length(network.demands))
    
    # Test with base case only (no outages)
    println("\nTesting with base case only (no outage scenarios)...")
    total_demand = sum(demand.demand_value for (_, demand) in network.demands)
    println("Total demand: ", @sprintf("%.2f", total_demand))
    
    # Build and solve with compact formulation (base case only, no outages)
    println("\nBuilding compact model...")
    settings = read_settings()
    base_case = [OutageScenario(0, Int[])]
    result = solve_compact_model(network; optimizer=settings.optimizer, outage_scenarios=base_case)
    
    println("\n" * "="^80)
    println("RESULTS")
    println("="^80)
    println("Status: ", result.status)
    println("Our objective:      ", @sprintf("%.2f", result.objective_value))
    println("Expected:           37871728.59")
    println("Difference:         ", @sprintf("%.2f", abs(result.objective_value - 3.787172859e7)))
    println("="^80)
    
    # Test that we match
    @test result.status == MOI.OPTIMAL
    @test abs(result.objective_value - 3.787172859e7) < 1.0
    
    if abs(result.objective_value - 3.787172859e7) < 1.0
        println("\n✓ SUCCESS: Our formulation matches expected result!")
    else
        println("\n✗ FAIL: Objective values differ")
    end
end
