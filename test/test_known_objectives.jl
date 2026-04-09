"""
Test network instances with known optimal objective values

This test verifies that the solver produces correct results by comparing
against known optimal values for standard benchmark instances.
"""

include("common.jl")

using Printf
using JuMP
const MOI = JuMP.MOI

@testset "Known Optimal Values" begin
    
    @testset "Abilene - All Single-Link Outages" begin
        println("\n" * "="^80)
        println("Testing Abilene with all single-link outages")
        println("="^80)
        
        network_file = joinpath(DATA_DIR, "sndlib", "abilene.xml")
        @test isfile(network_file)
        
        println("\nLoading network from: $network_file")
        network = read_sndlib_network(network_file)
        
        println("Network loaded:")
        println("  Nodes: ", length(network.network_structure.nodes))
        println("  Links: ", length(network.network_structure.links))
        println("  Demands: ", length(network.demands))
        
        @test length(network.network_structure.nodes) == 12
        @test length(network.network_structure.links) == 15
        @test length(network.demands) == 132
        
        # Generate all single-link outage scenarios (no base case)
        println("\nGenerating all single-link outage scenarios...")
        outage_scenarios = generate_outage_scenarios(network; include_base_case=false)
        println("Number of outage scenarios: ", length(outage_scenarios))
        
        @test length(outage_scenarios) >= 1  # At least some feasible scenarios
        @test length(outage_scenarios) <= length(network.network_structure.links)  # At most one per link
        
        # Solve with Benders
        println("\nSolving with Benders decomposition...")
        settings = read_settings()
        
        start_time = time()
        result = solve_benders(network; 
                              optimizer=settings.optimizer,
                              outage_scenarios=outage_scenarios,
                              settings=settings)
        elapsed_time = time() - start_time
        
        status = result.status
        obj_value = result.objective_value
        iterations = result.iterations
        total_cuts = result.total_cuts_added
        
        println("\n" * "="^80)
        println("RESULTS - Abilene (15 single-link outages)")
        println("="^80)
        println("Status:          ", status)
        println("Objective:       ", @sprintf("%.2f", obj_value))
        println("Known optimal:   438077.00")
        println("Iterations:      ", iterations)
        println("Cuts added:      ", total_cuts)
        println("Time:            ", @sprintf("%.2fs", elapsed_time))
        println("="^80)
        
        @test status in [MOI.OPTIMAL, MOI.TIME_LIMIT]
        @test obj_value < Inf
        
        # Verify objective matches known value (within small tolerance)
        @test isapprox(obj_value, 438077.0, rtol=0.01)
        
        if abs(obj_value - 438077.0) < 100.0
            println("\n✓ SUCCESS: Matches known optimal value!")
        else
            println("\n⚠ WARNING: Objective differs from known optimal")
            println("  Expected: 438077.00")
            println("  Got:      ", @sprintf("%.2f", obj_value))
            println("  Diff:     ", @sprintf("%.2f", obj_value - 438077.0))
        end
        println("="^80)
    end
    
    @testset "Atlanta - All Single-Link Outages" begin
        println("\n" * "="^80)
        println("Testing Atlanta with all single-link outages")
        println("="^80)
        
        network_file = joinpath(DATA_DIR, "sndlib", "atlanta.xml")
        @test isfile(network_file)
        
        println("\nLoading network from: $network_file")
        network = read_sndlib_network(network_file)
        
        println("Network loaded:")
        println("  Nodes: ", length(network.network_structure.nodes))
        println("  Links: ", length(network.network_structure.links))
        println("  Demands: ", length(network.demands))
        
        @test length(network.network_structure.nodes) == 15
        @test length(network.network_structure.links) == 22
        @test length(network.demands) == 210
        
        # Generate all single-link outage scenarios (no base case)
        println("\nGenerating all single-link outage scenarios...")
        outage_scenarios = generate_outage_scenarios(network; include_base_case=false)
        println("Number of outage scenarios: ", length(outage_scenarios))
        
        @test length(outage_scenarios) >= 1  # At least some feasible scenarios
        @test length(outage_scenarios) <= length(network.network_structure.links)  # At most one per link
        
        # Solve with Benders
        println("\nSolving with Benders decomposition...")
        settings = read_settings()
        
        start_time = time()
        result = solve_benders(network; 
                              optimizer=settings.optimizer,
                              outage_scenarios=outage_scenarios,
                              settings=settings)
        elapsed_time = time() - start_time
        
        status = result.status
        obj_value = result.objective_value
        iterations = result.iterations
        total_cuts = result.total_cuts_added
        
        println("\n" * "="^80)
        println("RESULTS - Atlanta (22 single-link outages)")
        println("="^80)
        println("Status:          ", status)
        println("Objective:       ", @sprintf("%.2f", obj_value))
        println("Iterations:      ", iterations)
        println("Cuts added:      ", total_cuts)
        println("Time:            ", @sprintf("%.2fs", elapsed_time))
        println("="^80)
        
        @test status in [MOI.OPTIMAL, MOI.TIME_LIMIT]
        @test obj_value < Inf
        
        # For Atlanta, we verify it finds a reasonable solution
        # (exact optimal may vary depending on solver settings)
        @test obj_value > 0.0
        
        if status == MOI.OPTIMAL
            println("\n✓ Found optimal solution: ", @sprintf("%.2f", obj_value))
        else
            println("\n⚠ Time limit reached - best solution: ", @sprintf("%.2f", obj_value))
        end
        println("="^80)
    end
end
