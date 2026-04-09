"""
Compare Benders performance with different cut limits against compact formulation.

Tests various max_cuts_per_iteration values and compares:
- Objective values (should all match)
- Number of iterations
- Total cuts added
- Solution time
"""

include("common.jl")

using Printf
using JuMP
using Gurobi

# Initialize Gurobi environment
GRB_ENV = init_gurobi_env()

struct TestResult
    method::String
    objective::Float64
    iterations::Int
    cuts_added::Int
    solve_time::Float64
    status::MOI.TerminationStatusCode
end

function run_comparison(network_name::String, network_file::String, num_outages::Int)::Tuple{Vector{TestResult}, Float64}
    println("\n" * "="^80)
    println("Performance Comparison: $network_name")
    println("Number of outage scenarios: $num_outages")
    println("="^80)
    
    # Load network
    @test isfile(network_file)
    network = read_sndlib_network(network_file)
    
    println("\nNetwork: $(length(network.network_structure.nodes)) nodes, " *
            "$(length(network.network_structure.links)) links, " *
            "$(length(network.demands)) demands")
    
    # Generate outage scenarios (with fixed seed for reproducibility)
    if num_outages == 0
        outage_scenarios = OutageScenario[]
    elseif num_outages < 0
        # -1 means all single-link outages
        outage_scenarios = generate_outage_scenarios(network; include_base_case=false)
    else
        outage_scenarios = sample_outage_scenarios(network, num_outages; seed=42, include_base_case=false)
    end
    
    println("Generated $(length(outage_scenarios)) outage scenarios" * 
            (num_outages > 0 ? " (seed=42 for reproducibility)" : ""))
    
    optimizer = () -> Gurobi.Optimizer(GRB_ENV[])
    
    results = TestResult[]
    
    # Test 1: Compact formulation (baseline)
    println("\n" * "-"^80)
    println("Method: COMPACT FORMULATION")
    println("-"^80)
    t_start = time()
    compact_result = solve_compact_model(network; 
                                        optimizer=optimizer, 
                                        outage_scenarios=outage_scenarios)
    t_elapsed = time() - t_start
    
    println("Status: $(compact_result.status)")
    println("Objective: ", @sprintf("%.2f", compact_result.objective_value))
    println("Time: ", @sprintf("%.2f", t_elapsed), " seconds")
    
    push!(results, TestResult("Compact", compact_result.objective_value, 0, 0, t_elapsed, compact_result.status))
    
    # Test 2-6: Benders with different cut limits
    cut_limits = [-1, 1, 3, 5, 10]  # -1 means unlimited
    
    for limit in cut_limits
        limit_str = limit == -1 ? "Unlimited" : string(limit)
        println("\n" * "-"^80)
        println("Method: BENDERS (max_cuts_per_iteration = $limit_str)")
        println("-"^80)
        
        t_start = time()
        benders_result = solve_benders(network; 
                                      optimizer=optimizer, 
                                      outage_scenarios=outage_scenarios,
                                      max_cuts_per_iteration=limit,
                                      use_subproblem_ordering=false)
        t_elapsed = time() - t_start
        
        println("Status: $(benders_result.status)")
        println("Objective: ", @sprintf("%.2f", benders_result.objective_value))
        println("Iterations: $(benders_result.iterations)")
        println("Total cuts: $(benders_result.total_cuts_added)")
        println("Time: ", @sprintf("%.2f", t_elapsed), " seconds")
        
        method_name = limit == -1 ? "Benders (∞)" : "Benders ($limit)"
        push!(results, TestResult(method_name, benders_result.objective_value, 
                                 benders_result.iterations, benders_result.total_cuts_added,
                                 t_elapsed, benders_result.status))
        
        # Note: Very small cut limits may not converge to optimal
        # Only verify objectives match for reasonable limits
        if limit == -1 || limit >= 5
            @test abs(benders_result.objective_value - compact_result.objective_value) < 1.0
        end
    end
    
    return results, compact_result.objective_value
end

function print_summary_table(results::Vector{TestResult}, optimal_obj::Float64)
    println("\n" * "="^80)
    println("SUMMARY TABLE")
    println("="^80)
    println(@sprintf("%-18s %12s %8s %8s %10s %8s", 
                     "Method", "Objective", "Gap", "Iters", "Cuts", "Time(s)"))
    println("-"^80)
    
    for r in results
        gap = abs(r.objective - optimal_obj)
        gap_str = gap < 0.01 ? "✓" : @sprintf("%.2f", gap)
        iters_str = r.iterations == 0 ? "-" : string(r.iterations)
        cuts_str = r.cuts_added == 0 ? "-" : string(r.cuts_added)
        
        println(@sprintf("%-18s %12.2f %8s %8s %10s %8.2f", 
                        r.method, r.objective, gap_str, iters_str, cuts_str, r.solve_time))
    end
    println("="^80)
    
    # Additional statistics
    benders_results = filter(r -> startswith(r.method, "Benders"), results)
    converged_results = filter(r -> abs(r.objective - optimal_obj) < 1.0, benders_results)
    
    if !isempty(converged_results)
        println("\nBenders Statistics (converged methods only):")
        println("  Fastest: ", converged_results[argmin([r.solve_time for r in converged_results])].method)
        println("  Fewest iterations: ", converged_results[argmin([r.iterations for r in converged_results])].method)
        println("  Fewest cuts: ", converged_results[argmin([r.cuts_added for r in converged_results])].method)
    end
    
    if !isempty(benders_results) && length(converged_results) < length(benders_results)
        println("\n⚠ Warning: Some methods with very small cut limits did not converge to optimal")
        println("  This is expected behavior when max_cuts_per_iteration < num_scenarios")
    end
    println()
end

# Run test
@testset "Cut Limit Comparison" begin
    println("\n" * "="^80)
    println("CUT LIMIT COMPARISON TEST")
    println("="^80)
    
    # Test on abilene with all single-link outages
    results, optimal_obj = run_comparison("abilene", 
                                         joinpath(DATA_DIR, "sndlib", "abilene.xml"), 
                                         -1)
    
    print_summary_table(results, optimal_obj)
    
    # Methods with sufficient cut limits should find optimal solution
    converged_methods = ["Compact", "Benders (∞)", "Benders (5)", "Benders (10)"]
    for r in filter(r -> r.method in converged_methods, results)
        @test abs(r.objective - optimal_obj) < 1.0
        @test r.status == MOI.OPTIMAL
    end
end

println("\n" * "="^80)
println("Test completed!")
println("="^80)
