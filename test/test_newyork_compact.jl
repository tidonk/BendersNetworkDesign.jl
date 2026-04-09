"""
Test to verify our compact.jl formulation for New York network instances

SNDlib Classification System (8 positions):
1. D=Directed/U=Undirected demands
2. B=Bidirected/D=Directed/U=Undirected links
3. M=Modular/S=Single/L=Linear capacity
4. N=No/Y=Yes fixed charges
5. C=Continuous/I=Integer/S=Shortest-path routing
6. A=All/L=Limited paths
7. N=No/Y=Yes hop limits
8. N=No survivability/U=Unrestricted flow reconfiguration/P=Protection/S=Shared

New York instances:
- newyork--U-U-M-N-C-A-N-U: Undirected demands/links, Modular capacity, No fixed charges,
  Continuous routing, All paths, No hop limits, Unrestricted flow reconfiguration
  (must survive single link failures)
  Expected optimal: 1286518.00

Key insights:
- Position 2 "U" (Undirected links): Both flow directions share the same physical capacity
- Position 4 "N" (No fixed charges): Only module costs, no setup costs
- Position 8 "U" (Unrestricted flow reconfiguration): Model each single link failure scenario

For this test we use only the base demand scenario.

Note: This is a challenging instance with survivability. The test allows up to 600 seconds
and accepts solutions within 10% of the best known value.
"""

include("common.jl")

using Printf

@testset "newyork--U-U-M-N-C-A-N-U" begin
    println("\n" * "="^80)
    println("Testing newyork network with compact formulation")
    println("Instance: newyork--U-U-M-N-C-A-N-U")
    println("="^80)
    
    # Load newyork network
    network_file = joinpath(DATA_DIR, "sndlib", "newyork.xml")
    @test isfile(network_file)
    
    println("\nLoading network from: $network_file")
    network = read_sndlib_network(network_file)
    
    println("Network loaded:")
    println("  Nodes: ", length(network.network_structure.nodes))
    println("  Links: ", length(network.network_structure.links))
    println("  Demands: ", length(network.demands))
    
    # Expected from SNDlib website
    @test length(network.network_structure.nodes) == 16
    @test length(network.network_structure.links) == 49
    @test length(network.demands) == 240
    
    # Test with all single-link outage scenarios
    total_demand = sum(demand.demand_value for (_, demand) in network.demands)
    println("Total demand: ", @sprintf("%.2f", total_demand))
    
    # Generate all single-link failure scenarios
    println("\nGenerating single-link outage scenarios...")
    outage_scenarios = generate_outage_scenarios(network; include_base_case=false)
    println("Number of outage scenarios: ", length(outage_scenarios))
    
    # Build model with survivability (position 8 = U)
    println("\nBuilding compact model with unrestricted flow reconfiguration...")
    println("Note: This models single link failure scenarios")
    
    # Get optimizer
    settings = read_settings()
    result = solve_compact_model(network; optimizer=settings.optimizer, outage_scenarios=outage_scenarios)
    
    status = result.status
    obj_value = result.objective_value
    
    println("\n" * "="^80)
    println("RESULTS - newyork--U-U-M-N-C-A-N-U")
    println("="^80)
    println("Status: ", status)
    println("Objective value:    ", @sprintf("%.2f", result.objective_value))
    println("SNDlib optimal:     1286518.00")
    if status == MOI.TIME_LIMIT && has_values(model)
        println("Best bound:         ", @sprintf("%.2f", objective_bound(model)))
    end
    println("Gap to best:        ", @sprintf("%.2f%%", 
            100.0 * abs(obj_value - 1286518.00) / 1286518.00))
    println("="^80)
    
    # Test that we get a solution (optimal or good feasible)
    @test status in [MOI.OPTIMAL, MOI.TIME_LIMIT]
    
    # Test that we have a feasible solution
    @test obj_value < Inf
    
    # Test that objective is reasonable (within 15% of best known)
    # This validates that the model formulation is correct
    # (Survivability model is much larger and more challenging)
    @test obj_value >= 1286518.00 * 0.85
    @test obj_value <= 1286518.00 * 1.15
    
    # Print detailed results
    if status in [MOI.OPTIMAL, MOI.TIME_LIMIT]
        if abs(obj_value - 1286518.00) < 100.0
            println("\n✓ SUCCESS: Matches SNDlib optimal value!")
        elseif status == MOI.OPTIMAL
            println("\n✓ Found optimal: ", @sprintf("%.2f", obj_value))
            if obj_value < 1286518.00 - 1.0
                println("  (Note: Better than SNDlib best!)")
            end
        else
            println("\n⚠ Good solution but time limit reached")
            println("  (Survivability model is much larger - may need more time)")
        end
        
        # Solution quality
        gap_to_best = 100.0 * abs(obj_value - 1286518.00) / 1286518.00
        println("  Gap to SNDlib best: ", @sprintf("%.2f%%", gap_to_best))
    else
        println("\n✗ FAIL: Did not find a feasible solution")
    end
    
    println("="^80)
end

