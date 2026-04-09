"""
Run oracle experiments: record cut data, then replay with oracle strategy.

Two-phase approach:
1. Write phase: Solve with strategy="none" to record all cuts
2. Read phase: Solve with strategy="oracle" using recorded data
"""

using BendersNetworkDesign
using Statistics
using Printf

"""
    run_oracle_write(network_file, settings_file, oracle_file)

Phase 1: Record which scenarios yield cuts in each iteration.

Solves using strategy="none" (all scenarios) and writes oracle data.
"""
function run_oracle_write(network_file::String, settings_file::String, oracle_file::String)
    println("\n" * "="^80)
    println("ORACLE WRITE PHASE: Recording cut data")
    println("="^80)
    println("Network: $(basename(network_file))")
    println("Oracle output: $oracle_file")
    
    # Load network and settings
    network = BendersNetworkDesign.read_sndlib_network(network_file)
    settings = BendersNetworkDesign.read_settings(settings_file)
    
    # Override settings for write phase
    # Force strategy="none" to solve all scenarios
    # Set oracle_mode="write" and oracle_filepath
    # Note: Settings struct is immutable, so we need to create modified settings
    # For now, we'll use a settings file that already has the correct configuration
    
    if settings.selection_strategy != "oracle" || settings.oracle_mode != "write"
        @warn "Settings file should have selection_strategy=\"oracle\" and oracle_mode=\"write\""
        @warn "Current: strategy=$(settings.selection_strategy), mode=$(settings.oracle_mode)"
    end
    
    outage_scenarios = BendersNetworkDesign.prepare_outage_scenarios(network, settings)
    
    # Solve with Benders
    result = BendersNetworkDesign.solve_benders(
        network;
        optimizer=settings.optimizer,
        outage_scenarios=outage_scenarios,
        settings=settings
    )
    
    println("\nWrite phase completed:")
    @printf("  Objective: %.2f\n", result.objective_value)
    @printf("  Iterations: %d\n", result.iterations)
    @printf("  Total cuts: %d\n", result.total_cuts_added)
    @printf("  Solve time: %.2f s\n", result.total_solve_time)
    
    return result
end

"""
    run_oracle_read(network_file, settings_file, oracle_file)

Phase 2: Replay using oracle data.

Solves using strategy="oracle" mode="read" with pre-recorded data.
"""
function run_oracle_read(network_file::String, settings_file::String, oracle_file::String)
    println("\n" * "="^80)
    println("ORACLE READ PHASE: Replaying with oracle")
    println("="^80)
    println("Network: $(basename(network_file))")
    println("Oracle input: $oracle_file")
    
    # Load network and settings
    network = BendersNetworkDesign.read_sndlib_network(network_file)
    settings = BendersNetworkDesign.read_settings(settings_file)
    
    # Verify oracle settings
    if settings.selection_strategy != "oracle" || settings.oracle_mode != "read"
        @warn "Settings file should have selection_strategy=\"oracle\" and oracle_mode=\"read\""
        @warn "Current: strategy=$(settings.selection_strategy), mode=$(settings.oracle_mode)"
    end
    
    outage_scenarios = BendersNetworkDesign.prepare_outage_scenarios(network, settings)
    
    # Solve with Benders using oracle
    result = BendersNetworkDesign.solve_benders(
        network;
        optimizer=settings.optimizer,
        outage_scenarios=outage_scenarios,
        settings=settings
    )
    
    println("\nRead phase completed:")
    @printf("  Objective: %.2f\n", result.objective_value)
    @printf("  Iterations: %d\n", result.iterations)
    @printf("  Total cuts: %d\n", result.total_cuts_added)
    @printf("  Solve time: %.2f s\n", result.total_solve_time)
    
    return result
end

"""
    run_oracle_experiment(network_file, write_settings, read_settings, oracle_file)

Complete oracle experiment: write then read phases.

Compares performance between full solve and oracle replay.
"""
function run_oracle_experiment(network_file::String, 
                               write_settings::String, 
                               read_settings::String,
                               oracle_file::String="check/oracle/oracle_data.csv")
    println("="^80)
    println("ORACLE EXPERIMENT")
    println("="^80)
    println("Network: $(basename(network_file))")
    println("Write settings: $(basename(write_settings))")
    println("Read settings: $(basename(read_settings))")
    println()
    
    # Phase 1: Write
    #write_result = run_oracle_write(network_file, write_settings, oracle_file)
    
    # Phase 2: Read
    read_result = run_oracle_read(network_file, read_settings, oracle_file)
    
    # Compare results
    println("\n" * "="^80)
    println("COMPARISON")
    println("="^80)
    println(@sprintf("%-20s %15s %15s %15s", "Metric", "Write (Full)", "Read (Oracle)", "Difference"))
    println("-"^80)
    
    # Objective value (should be identical or very close)
    obj_diff = read_result.objective_value - write_result.objective_value
    println(@sprintf("%-20s %15.2f %15.2f %15.2f", "Objective", write_result.objective_value, 
                    read_result.objective_value, obj_diff))
    
    # Iterations
    iter_diff = read_result.iterations - write_result.iterations
    println(@sprintf("%-20s %15d %15d %15d", "Iterations", write_result.iterations, 
                    read_result.iterations, iter_diff))
    
    # Total cuts
    cuts_diff = read_result.total_cuts_added - write_result.total_cuts_added
    println(@sprintf("%-20s %15d %15d %15d", "Cuts added", write_result.total_cuts_added, 
                    read_result.total_cuts_added, cuts_diff))
    
    # Subproblems solved
    sp_diff = write_result.total_subproblems_solved - read_result.total_subproblems_solved
    sp_pct = sp_diff / write_result.total_subproblems_solved * 100
    println(@sprintf("%-20s %15d %15d %12d (%.1f%%)", "Subproblems solved", 
                    write_result.total_subproblems_solved, read_result.total_subproblems_solved, 
                    sp_diff, sp_pct))
    
    # Solve time
    time_diff = write_result.total_solve_time - read_result.total_solve_time
    time_pct = time_diff / write_result.total_solve_time * 100
    println(@sprintf("%-20s %15.2f %15.2f %11.2f (%.1f%%)", "Total time (s)", 
                    write_result.total_solve_time, read_result.total_solve_time, 
                    time_diff, time_pct))
    
    # Subproblem time
    sp_time_diff = write_result.total_subproblem_solve_time - read_result.total_subproblem_solve_time
    sp_time_pct = sp_time_diff / write_result.total_subproblem_solve_time * 100
    println(@sprintf("%-20s %15.2f %15.2f %11.2f (%.1f%%)", "Subproblem time (s)", 
                    write_result.total_subproblem_solve_time, read_result.total_subproblem_solve_time, 
                    sp_time_diff, sp_time_pct))
    
    println("\nOracle experiment completed successfully!")
    
    # Write the table into a CSV file for further analysis (optional)
    csv_file = "check/oracle/oracle_experiment_comparison.csv"
    open(csv_file, "w") do io
        println(io, "Metric,Write (Full),Read (Oracle),Difference")
        println(io, @sprintf("Objective,%.2f,%.2f,%.2f", write_result.objective_value, 
                            read_result.objective_value, obj_diff))
        println(io, @sprintf("Iterations,%d,%d,%d", write_result.iterations, 
                            read_result.iterations, iter_diff))
        println(io, @sprintf("Cuts added,%d,%d,%d", write_result.total_cuts_added, 
                            read_result.total_cuts_added, cuts_diff))
        println(io, @sprintf("Subproblems solved,%d,%d,%d", 
                            write_result.total_subproblems_solved, 
                            read_result.total_subproblems_solved, sp_diff))
        println(io, @sprintf("Total time (s),%.2f,%.2f,%.2f", 
                            write_result.total_solve_time, 
                            read_result.total_solve_time, time_diff))
        println(io, @sprintf("Subproblem time (s),%.2f,%.2f,%.2f", 
                            write_result.total_subproblem_solve_time, 
                            read_result.total_subproblem_solve_time, sp_time_diff))
    end
    println("Comparison results written to: $csv_file")


    return nothing#(write=write_result, read=read_result)
end

# Example usage (commented out - uncomment to run)
using BendersNetworkDesign
network_file = joinpath(@__DIR__, "../data/sndlib/newyork.xml")
write_settings = joinpath(@__DIR__, "settings/test/oracle_write.toml")
read_settings = joinpath(@__DIR__, "settings/test/oracle_read.toml")
#oracle_file = joinpath(@__DIR__, "check/oracle/newyork_oracle.csv")
run_oracle_experiment(network_file, write_settings, read_settings)
 