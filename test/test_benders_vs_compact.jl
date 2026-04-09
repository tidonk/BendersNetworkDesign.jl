"""
Test that Benders decomposition matches compact model with outage scenarios

Both models should give the same objective value when considering the same
set of outage scenarios (including base case).
"""

include("common.jl")

using Printf
using JuMP
using Gurobi

# Initialize Gurobi environment
GRB_ENV = init_gurobi_env()

# Store results for final summary
struct TestResult
    name::String
    num_outages::Int
    objective::Float64
    compact_time::Float64
    benders_time::Float64
    benders_iters::Int
    match::Bool
end

const test_results = TestResult[]

"""
Helper function to test a network instance with outage scenarios
"""
function test_network_instance(network_name::String, network_file::String, num_outage_scenarios::Int;
                               time_limit::Float64=60.0)
    
    println("\n" * "="^80)
    println("Testing: $network_name with $num_outage_scenarios outage scenarios")
    println("="^80)
    
    @test isfile(network_file)
    
    println("\nLoading network from: $network_file")
    network = read_sndlib_network(network_file)
    
    println("Network: $(length(network.network_structure.nodes)) nodes, $(length(network.network_structure.links)) links, $(length(network.demands)) demands")
    
    # Generate outage scenarios
    println("\nGenerating outage scenarios...")
    outage_scenarios = if num_outage_scenarios == 0
        # Base case only
        [OutageScenario(0, Int[])]
    else
        sample_outage_scenarios(network, num_outage_scenarios; seed=42, include_base_case=true)
    end
    
    println("  Total scenarios: $(length(outage_scenarios)) (including base case)")
    
    # Optimizer setup
    optimizer = () -> Gurobi.Optimizer(GRB_ENV[])
    
    # Solve with compact model
    println("\nSolving with COMPACT model...")
    compact_start = time()
    compact_model = build_compact_model(network; optimizer=optimizer, outage_scenarios=outage_scenarios)
    set_time_limit_sec(compact_model, time_limit)
    optimize!(compact_model)
    compact_time = time() - compact_start
    
    compact_status = termination_status(compact_model)
    compact_obj = has_values(compact_model) ? objective_value(compact_model) : Inf
    
    println("  Status: $compact_status")
    println("  Objective: ", @sprintf("%.2f", compact_obj))
    println("  Time: ", @sprintf("%.2fs", compact_time))
    
    # Solve with Benders
    println("\\nSolving with BENDERS...")
    
    settings = read_settings()
    
    benders_start = time()
    benders_result = solve_benders(network; optimizer=optimizer, outage_scenarios=outage_scenarios, settings=settings)
    benders_time = time() - benders_start
    benders_status = benders_result.status
    benders_obj = benders_result.objective_value
    benders_iters = benders_result.iterations
    
    println("  Status: $benders_status")
    println("  Objective: ", @sprintf("%.2f", benders_obj))
    println("  Iterations: $benders_iters")
    println("  Time: ", @sprintf("%.2fs", benders_time))
    
    # Compare results
    println("\n" * "-"^80)
    println("COMPARISON")
    println("-"^80)
    abs_diff = abs(compact_obj - benders_obj)
    rel_diff = compact_obj > 0 ? 100 * abs_diff / compact_obj : 0.0
    
    println(@sprintf("%-20s %12.2f  %8.2fs", "Compact:", compact_obj, compact_time))
    println(@sprintf("%-20s %12.2f  %8.2fs  (%d iters)", "Benders:", benders_obj, benders_time, benders_iters))
    println(@sprintf("%-20s %12.2f  (%.6f%%)", "Difference:", abs_diff, rel_diff))
    println("-"^80)
    
    # Test assertions
    @test compact_status == MOI.OPTIMAL
    @test benders_status == MOI.OPTIMAL
    @test abs_diff < 1.0
    
    match = abs_diff < 1.0
    if match
        println("✓ SUCCESS: Benders matches compact!")
    else
        println("✗ FAILURE: Objectives differ!")
    end
    
    # Store result for summary
    push!(test_results, TestResult(network_name, num_outage_scenarios, compact_obj, 
                                    compact_time, benders_time, benders_iters, match))
    
    return match
end

@testset "Benders vs Compact with Outage Scenarios" begin
    
    # Test with base case only (0 outages)
    @testset "abilene: base case only" begin
        test_network_instance("abilene-base", joinpath(DATA_DIR, "sndlib", "abilene.xml"), 0; time_limit=30.0)
    end
    
    # Test with 1 outage scenario
    @testset "abilene: 1 outage" begin
        test_network_instance("abilene-1out", joinpath(DATA_DIR, "sndlib", "abilene.xml"), 1; time_limit=60.0)
    end
    
    # Test with 3 outage scenarios
    @testset "abilene: 3 outages" begin
        test_network_instance("abilene-3out", joinpath(DATA_DIR, "sndlib", "abilene.xml"), 3; time_limit=60.0)
    end
    
    # Test with 10 outage scenarios
    @testset "abilene: 10 outages" begin
        test_network_instance("abilene-10out", joinpath(DATA_DIR, "sndlib", "abilene.xml"), 10; time_limit=120.0)
    end
    
    # Print final summary
    println("\n" * "="^80)
    println("FINAL SUMMARY: Benders vs Compact with Outage Scenarios")
    println("="^80)
    println(@sprintf("%-15s %8s %12s %10s %10s %8s %6s", "Instance", "Outages", "Objective", "Compact", "Benders", "Iters", "Match"))
    println("-"^80)
    for result in test_results
        match_str = result.match ? "✓" : "✗"
        println(@sprintf("%-15s %8d %12.2f %9.2fs %9.2fs %8d  %6s", 
                        result.name, result.num_outages, result.objective, 
                        result.compact_time, result.benders_time, result.benders_iters, match_str))
    end
    println("="^80)
    
    all_match = all(r.match for r in test_results)
    if all_match
        println("All tests passed - Benders implementation verified ✓")
    else
        println("Some tests failed - review results above ✗")
    end
    println("="^80)
end
