"""
Run comparison experiments for determinism testing.

Runs multiple instances and collects timing statistics.
"""

using BendersNetworkDesign
using Statistics
using Printf

"""
    shifted_geomean(values; shift=10.0)

Compute shifted geometric mean: exp(mean(log(x + shift))) - shift
The shift helps handle small values and zeros.
"""
function shifted_geomean(values; shift=10.0)
    if isempty(values)
        return 0.0
    end
    shifted_values = values .+ shift
    exp(mean(log.(shifted_values))) - shift
end

"""
    run_experiment(network_file, settings_file, num_runs)

Run the same instance multiple times and collect timing data.
"""
function run_experiment(network_file::String, settings_file::String, num_runs::Int)
    results = []
    
    for run in 1:num_runs
        println("\n" * "="^80)
        println("Run $run/$num_runs: $(basename(settings_file))")
        println("="^80)
        
        # Load network and settings
        network = BendersNetworkDesign.read_sndlib_network(network_file)
        settings = BendersNetworkDesign.read_settings(settings_file)
        outage_scenarios = BendersNetworkDesign.prepare_outage_scenarios(network, settings)
        
        # Solve with appropriate method
        if settings.model_type == "benders"
            result = BendersNetworkDesign.solve_benders(
                network;
                optimizer=settings.optimizer,
                outage_scenarios=outage_scenarios,
                settings=settings
            )
        else
            result = BendersNetworkDesign.solve_compact_model(
                network;
                optimizer=settings.optimizer,
                outage_scenarios=outage_scenarios
            )
        end
        
        # Extract timing information from result NamedTuple
        # Use total solve time directly (includes all components)
        total_time = result.total_solve_time
        
        timing_data = Dict(
            "run" => run,
            "total_time" => total_time,
            "master_time" => result.total_master_time,
            "subproblem_time" => result.total_subproblem_solve_time,
            "objective" => result.objective_value
        )
        
        push!(results, timing_data)
        
        println("\nRun $run completed:")
        @printf("  Total: %.2f s, Master: %.2f s, Subproblem: %.2f s, Obj: %.2f\n", 
                timing_data["total_time"], timing_data["master_time"], 
                timing_data["subproblem_time"], timing_data["objective"])
    end
    
    return results
end

"""
    print_statistics(config_name, results)

Print summary statistics for a set of runs.
"""
function print_statistics(config_name::String, results::Vector)
    println("\n" * "="^80)
    println("Statistics for: $config_name")
    println("="^80)
    
    total_times = [r["total_time"] for r in results]
    master_times = [r["master_time"] for r in results]
    subproblem_times = [r["subproblem_time"] for r in results]
    objectives = [r["objective"] for r in results]
    
    # Print individual runs
    println("\nIndividual Runs:")
    println(@sprintf("%-6s %12s %12s %12s %15s", "Run", "Total (s)", "Master (s)", "Subprob (s)", "Objective"))
    println("-"^62)
    for (i, r) in enumerate(results)
        @printf("%-6d %12.2f %12.2f %12.2f %15.2f\n", 
                i, r["total_time"], r["master_time"], r["subproblem_time"], r["objective"])
    end
    
    # Print statistics
    println("\nStatistics:")
    println(@sprintf("%-15s %12s %12s %12s", "Metric", "Total (s)", "Master (s)", "Subprob (s)"))
    println("-"^54)
    @printf("%-15s %12.2f %12.2f %12.2f\n", "Mean", mean(total_times), mean(master_times), mean(subproblem_times))
    @printf("%-15s %12.2f %12.2f %12.2f\n", "Shifted GMean", 
            shifted_geomean(total_times), shifted_geomean(master_times), shifted_geomean(subproblem_times))
    @printf("%-15s %12.2f %12.2f %12.2f\n", "Std Dev", std(total_times), std(master_times), std(subproblem_times))
    @printf("%-15s %12.2f %12.2f %12.2f\n", "Min", minimum(total_times), minimum(master_times), minimum(subproblem_times))
    @printf("%-15s %12.2f %12.2f %12.2f\n", "Max", maximum(total_times), maximum(master_times), maximum(subproblem_times))
    @printf("%-15s %12.2f %12.2f %12.2f\n", "Range", 
            maximum(total_times) - minimum(total_times),
            maximum(master_times) - minimum(master_times),
            maximum(subproblem_times) - minimum(subproblem_times))
    
    # Check determinism
    if length(unique(objectives)) == 1
        println("\n✓ Objective values are identical across all runs (deterministic)")
    else
        println("\n⚠ WARNING: Objective values differ across runs!")
        println("  Unique objectives: ", unique(objectives))
    end
    
    return Dict(
        "total_mean" => mean(total_times),
        "master_mean" => mean(master_times),
        "subproblem_mean" => mean(subproblem_times),
        "total_geomean" => shifted_geomean(total_times),
        "master_geomean" => shifted_geomean(master_times),
        "subproblem_geomean" => shifted_geomean(subproblem_times)
    )
end

"""
    print_comparison_table(config1_name, stats1, config2_name, stats2)

Print side-by-side comparison of two configurations.
"""
function print_comparison_table(config1_name::String, stats1::Dict, config2_name::String, stats2::Dict)
    println("\n" * "="^100)
    println("COMPARISON TABLE")
    println("="^100)
    
    println(@sprintf("\n%-20s | %12s %12s %12s | %12s %12s %12s", 
                     "Configuration", "Total (s)", "Master (s)", "Subprob (s)", "Total (s)", "Master (s)", "Subprob (s)"))
    println(@sprintf("%-20s | %12s %12s %12s | %12s %12s %12s", 
                     "", "---- Mean ----", "", "", "- Shifted GMean -", "", ""))
    println("-"^100)
    
    @printf("%-20s | %12.2f %12.2f %12.2f | %12.2f %12.2f %12.2f\n",
            config1_name,
            stats1["total_mean"], stats1["master_mean"], stats1["subproblem_mean"],
            stats1["total_geomean"], stats1["master_geomean"], stats1["subproblem_geomean"])
    
    @printf("%-20s | %12.2f %12.2f %12.2f | %12.2f %12.2f %12.2f\n",
            config2_name,
            stats2["total_mean"], stats2["master_mean"], stats2["subproblem_mean"],
            stats2["total_geomean"], stats2["master_geomean"], stats2["subproblem_geomean"])
    
    println("-"^100)
    
    # Speedup
    @printf("%-20s | %12.2fx %12.2fx %12.2fx | %12.2fx %12.2fx %12.2fx\n",
            "Speedup (2 vs 1)",
            stats1["total_mean"] / stats2["total_mean"],
            stats1["master_mean"] / stats2["master_mean"],
            stats1["subproblem_mean"] / stats2["subproblem_mean"],
            stats1["total_geomean"] / stats2["total_geomean"],
            stats1["master_geomean"] / stats2["master_geomean"],
            stats1["subproblem_geomean"] / stats2["subproblem_geomean"])
    
    println("="^100)
end

# Main execution
function main_comparison(network_file::String="", config1_file::String="", config2_file::String="")
    network_name = "$(basename(network_file))"
    config1_name = "$(basename(config1_file))"
    config2_name = "$(basename(config2_file))"

    num_runs = 3
    
    println("="^80)
    println("DETERMINISM TEST - Running $num_runs iterations each")
    println("="^80)
    println("Network: $network_name")
    println("Config 1: $config1_name")
    println("Config 2: $config2_name")
    
    # Run experiments
    println("\n\n" * "█"^80)
    println("EXPERIMENT 2: $config2_name")
    println("█"^80)
    results2 = run_experiment(network_file, config2_file, num_runs)
    stats2 = print_statistics(config2_name, results2)
    
    println("\n\n" * "█"^80)
    println("EXPERIMENT 1: $config1_name")
    println("█"^80)
    results1 = run_experiment(network_file, config1_file, 1)
    stats1 = print_statistics(config1_name, results1)

    # Print comparison
    print_comparison_table(config1_name, stats1, config2_name, stats2)
end


network_file = joinpath(@__DIR__, "../data/sndlib/newyork.xml")
config1_file = joinpath(@__DIR__, "settings/benders_standard.toml")
config2_file = joinpath(@__DIR__, "settings/experiment4/benders_ML-P0.5-20S-UR.toml")

# Run the comparison
main_comparison(network_file, config1_file, config2_file)