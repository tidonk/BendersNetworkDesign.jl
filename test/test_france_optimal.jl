"""
Test to verify our compact.jl formulation for France network instances

SNDlib Classification System (8 positions):
1. D=Directed/U=Undirected demands
2. B=Bidirected/D=Directed/U=Undirected links
3. M=Modular/S=Single/L=Linear capacity
4. N=No/Y=Yes fixed charges
5. C=Continuous/I=Integer/S=Shortest-path routing
6. A=All/L=Limited paths
7. N=No/Y=Yes hop limits
8. N=No survivability/U=Unrestricted flow reconfiguration/P=Protection/S=Shared

France instances:
- france--U-U-M-N-C-A-N-N: Undirected demands/links, Modular capacity, No fixed charges,
  Continuous routing, All paths, No hop limits, No survivability
  Expected optimal: 20200
  
- france--U-U-M-N-C-A-N-U: Same as above but with Unrestricted flow reconfiguration
  (must survive single link failures)
  Expected optimal: 33400

Key insights:
- Position 2 "U" (Undirected links): Both flow directions share the same physical capacity
- Position 4 "N" (No fixed charges): Only module costs, no setup costs
- Position 8 "U" (Unrestricted flow reconfiguration): Model each single link failure scenario
"""

include("common.jl")

using Printf

@testset "France Network Tests" begin
    
    @testset "france--U-U-M-N-C-A-N-N (No survivability)" begin
        println("\n" * "="^80)
        println("Testing france--U-U-M-N-C-A-N-N")
        println("="^80)
        
        network_file = joinpath(DATA_DIR, "sndlib", "france.xml")
        @test isfile(network_file)
        
        println("\nLoading network from: $network_file")
        network = read_sndlib_network(network_file)
        
        println("Network loaded:")
        println("  Nodes: ", length(network.network_structure.nodes))
        println("  Links: ", length(network.network_structure.links))
        println("  Demands: ", length(network.demands))
        
        @test length(network.network_structure.nodes) == 25
        @test length(network.network_structure.links) == 45
        @test length(network.demands) == 300
        
        # Test with base case only (no outage scenarios = no survivability)
        total_demand = sum(demand.demand_value for (_, demand) in network.demands)
        println("\nTotal demand: ", @sprintf("%.2f", total_demand))
        
        # Build and solve WITHOUT survivability (base case only, no outages)
        println("\nBuilding compact model (no survivability)...")
        settings = read_settings()
        base_case = [OutageScenario(0, Int[])]
        result = solve_compact_model(network; optimizer=settings.optimizer, outage_scenarios=base_case)
        
        status = result.status
        obj_value = result.objective_value
        
        println("\n" * "="^80)
        println("RESULTS - france--U-U-M-N-C-A-N-N")
        println("="^80)
        println("Status: ", status)
        println("Objective value:     ", @sprintf("%.2f", obj_value))
        println("SNDlib optimal:      20200.00")
        println("="^80)
        
        @test status in [MOI.OPTIMAL, MOI.TIME_LIMIT]
        @test obj_value < Inf
        
        # Should match SNDlib value (±1000 tolerance for time limit)
        @test 19_000.0 <= obj_value <= 21_000.0
        
        if abs(obj_value - 20200.0) < 100.0
            println("\n✓ SUCCESS: Matches SNDlib optimal value!")
        elseif status == MOI.OPTIMAL
            println("\n✓ Found optimal: ", @sprintf("%.2f", obj_value))
        else
            println("\n⚠ Good solution but time limit reached")
        end
        println("="^80)
    end
    
    @testset "france--U-U-M-N-C-A-N-U (Unrestricted flow reconfiguration)" begin
        println("\n" * "="^80)
        println("Testing france--U-U-M-N-C-A-N-U")
        println("="^80)
        
        network_file = joinpath(DATA_DIR, "sndlib", "france.xml")
        @test isfile(network_file)
        
        println("\nLoading network from: $network_file")
        network = read_sndlib_network(network_file)
        
        println("Network loaded:")
        println("  Nodes: ", length(network.network_structure.nodes))
        println("  Links: ", length(network.network_structure.links))
        println("  Demands: ", length(network.demands))
        
        @test length(network.network_structure.nodes) == 25
        @test length(network.network_structure.links) == 45
        @test length(network.demands) == 300
        
        # Generate sample of outage scenarios (all would be too slow for testing)
        total_demand = sum(demand.demand_value for (_, demand) in network.demands)
        println("\nTotal demand: ", @sprintf("%.2f", total_demand))
        
        println("\nGenerating sample of outage scenarios for testing...")
        outage_scenarios = sample_outage_scenarios(network, 5; include_base_case=false)
        println("Number of outage scenarios: ", length(outage_scenarios))
        println("Note: Using sample for faster testing - full model would have all ", length(network.network_structure.links), " scenarios")
        
        # Build and solve WITH survivability
        println("\nBuilding compact model (unrestricted flow reconfiguration)...")
        println("Note: This models single link failure scenarios")
        settings = read_settings()
        result = solve_compact_model(network; optimizer=settings.optimizer, outage_scenarios=outage_scenarios)
        
        status = result.status
        obj_value = result.objective_value
        
        println("\n" * "="^80)
        println("RESULTS - france--U-U-M-N-C-A-N-U (sample of outages)")
        println("="^80)
        println("Status: ", status)
        println("Objective value:     ", @sprintf("%.2f", obj_value))
        println("Note: Using sample of outages for testing")
        println("Expected range:      20000-36000 (between no-survivability and full)")
        println("="^80)
        
        @test status in [MOI.OPTIMAL, MOI.TIME_LIMIT]
        @test obj_value < Inf
        
        # With sample of outages, should be between base case (20200) and full (33400)
        @test 20_000.0 <= obj_value <= 36_000.0
        
        if status == MOI.OPTIMAL
            println("\n✓ Found optimal: ", @sprintf("%.2f", obj_value))
        else
            println("\n⚠ Good solution but time limit reached")
        end
        println("="^80)
    end
end
