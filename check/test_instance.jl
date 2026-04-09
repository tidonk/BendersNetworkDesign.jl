"""
test_instance.jl

Script to solve a single network design instance and output results to CSV.

Usage:
    julia test_instance.jl <network_file> <settings_file> <output_csv>

Arguments:
    network_file: Path to SNDlib XML network file
    settings_file: Path to TOML settings file
    output_csv: Path to output CSV file (will append if exists)

Example:
    julia test_instance.jl ../data/sndlib/abilene.xml ../settings/test1.toml results/abilene.csv
"""

# JULIA_DEPOT_PATH is set to a local directory, so install all dependencies there
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()
Pkg.build()

using CSV
using DataFrames
using Printf
using JuMP

# Load BendersNetworkDesign module
include(joinpath(@__DIR__, "..", "src", "BendersNetworkDesign.jl"))
using .BendersNetworkDesign

# Result structure for instance statistics
const InstanceResult = NamedTuple{
    (:instance, :num_nodes, :num_links, :num_demands, :num_scenarios,
     :settings_file, :solver, :model_type, :cut_filtering_max_cuts,
     :subproblem_ordering, :scoring_weights, :total_time, :solve_time,
     :master_time, :callback_time, :subproblem_time, :ml_training_time,
     :dbscan_time, :objective_value, :bound, :status, :benders_iterations, 
     :benders_cuts, :benders_cuts_found, :benders_subproblems_solved, :bb_nodes),
    Tuple{String, Int, Int, Int, Int, String, String, String, Int,
          String, String, Float64, Float64, Float64, Float64, Float64, Float64,
          Float64, Float64, Float64, String, Int, Int, Int, Int, Int}
}

"""
    solve_instance_with_stats(network_file::String, settings_file::String)::InstanceResult

Solve a network design instance and return detailed statistics.

# Arguments
- `network_file::String`: Path to SNDlib XML network file
- `settings_file::String`: Path to TOML settings file

# Returns
- `InstanceResult`: Named tuple containing all instance statistics and results
"""
function solve_instance_with_stats(network_file::String, settings_file::String)::InstanceResult
    # Load settings
    settings = read_settings(settings_file)
    
    # Load network
    isfile(network_file) || error("Network file not found: $network_file")
    network = read_sndlib_network(network_file)
    
    # Count network elements
    num_nodes = length(network.network_structure.nodes)
    num_links = length(network.network_structure.links)
    num_demands = length(network.demands)
    
    # Prepare outage scenarios
    outage_scenarios = if settings.num_outage_scenarios == -1
        generate_outage_scenarios(network; include_base_case=true)
    else
        sample_outage_scenarios(
            network, 
            settings.num_outage_scenarios;
            seed=settings.outage_sampling_seed,
            include_base_case=true
        )
    end
    num_scenarios = length(outage_scenarios)
    
    # Solve instance with timing
    total_time_start = time()
    
    if settings.model_type == "benders"
        result = solve_benders(
            network;
            optimizer=settings.optimizer,
            outage_scenarios=outage_scenarios,
            settings=settings
        )
        
        total_time = time() - total_time_start
        solve_time = JuMP.solve_time(result.model)
        master_time = result.total_master_time
        callback_time = result.total_callback_time
        subproblem_time = result.total_subproblem_solve_time
        ml_training_time = result.total_ml_training_time
        dbscan_time = result.total_dbscan_time
        bound = JuMP.objective_bound(result.model)
        bb_nodes = result.node_count
        
        return (
            instance=basename(network_file),
            num_nodes=num_nodes,
            num_links=num_links,
            num_demands=num_demands,
            num_scenarios=num_scenarios,
            settings_file=basename(settings_file),
            solver=string(settings.solver),
            model_type=settings.model_type,
            cut_filtering_max_cuts=settings.cut_filtering_max_cuts,
            subproblem_ordering=settings.subproblem_ordering,
            scoring_weights=join(settings.scoring_weights, ";"),
            total_time=total_time,
            solve_time=solve_time,
            master_time=master_time,
            callback_time=callback_time,
            subproblem_time=subproblem_time,
            ml_training_time=ml_training_time,
            dbscan_time=dbscan_time,
            objective_value=result.objective_value,
            bound=bound,
            status=string(result.status),
            benders_iterations=result.iterations,
            benders_cuts=result.total_cuts_added,
            benders_cuts_found=result.total_cuts_found,
            benders_subproblems_solved=result.total_subproblems_solved,
            bb_nodes=bb_nodes
        )
    else
        # Compact model
        result = solve_compact_model(
            network;
            optimizer=settings.optimizer,
            outage_scenarios=outage_scenarios
        )
        
        total_time = time() - total_time_start
        solve_time = JuMP.solve_time(result.model)
        
        bound = JuMP.objective_bound(result.model)
        bb_nodes = result.node_count
        
        return (
            instance=basename(network_file),
            num_nodes=num_nodes,
            num_links=num_links,
            num_demands=num_demands,
            num_scenarios=num_scenarios,
            settings_file=basename(settings_file),
            solver=string(settings.solver),
            model_type=settings.model_type,
            cut_filtering_max_cuts=-1,
            subproblem_ordering="N/A",
            scoring_weights="N/A",
            total_time=total_time,
            solve_time=solve_time,
            master_time=0.0,
            callback_time=0.0,
            subproblem_time=0.0,
            ml_training_time=0.0,
            dbscan_time=0.0,
            objective_value=result.objective_value,
            bound=bound,
            status=string(result.status),
            benders_iterations=0,
            benders_cuts=0,
            benders_cuts_found=0,
            benders_subproblems_solved=0,
            bb_nodes=bb_nodes
        )
    end
end

"""
    write_result_to_csv(result::InstanceResult, output_csv::String)::Nothing

Write instance result to CSV file (appends if file exists).

# Arguments
- `result::InstanceResult`: Named tuple containing instance statistics
- `output_csv::String`: Path to output CSV file
"""
function write_result_to_csv(result::InstanceResult, output_csv::String)::Nothing
    # Create DataFrame from result
    df = DataFrame(
        instance=[result.instance],
        num_nodes=[result.num_nodes],
        num_links=[result.num_links],
        num_demands=[result.num_demands],
        num_scenarios=[result.num_scenarios],
        settings_file=[result.settings_file],
        solver=[result.solver],
        model_type=[result.model_type],
        cut_filtering_max_cuts=[result.cut_filtering_max_cuts],
        subproblem_ordering=[result.subproblem_ordering],
        scoring_weights=[result.scoring_weights],
        total_time=[result.total_time],
        solve_time=[result.solve_time],
        master_time=[result.master_time],
        callback_time=[result.callback_time],
        subproblem_time=[result.subproblem_time],
        ml_training_time=[result.ml_training_time],
        dbscan_time=[result.dbscan_time],
        objective_value=[result.objective_value],
        bound=[result.bound],
        status=[result.status],
        benders_iterations=[result.benders_iterations],
        benders_cuts=[result.benders_cuts],
        benders_cuts_found=[result.benders_cuts_found],
        benders_subproblems_solved=[result.benders_subproblems_solved],
        bb_nodes=[result.bb_nodes]
    )
    
    # Ensure output directory exists
    output_dir = dirname(output_csv)
    isdir(output_dir) || mkpath(output_dir)
    
    # Write or append to CSV
    CSV.write(output_csv, df; append=isfile(output_csv))
    
    println("Results written to: $output_csv")
    return nothing
end

"""
    print_usage()::Nothing

Print usage information and exit.
"""
function print_usage()::Nothing
    println("Usage: julia test_instance.jl <network_file> <settings_file> <output_csv>")
    println()
    println("Arguments:")
    println("  network_file: Path to SNDlib XML network file")
    println("  settings_file: Path to TOML settings file")
    println("  output_csv: Path to output CSV file")
    println()
    println("Example: (execute from within check directory)")
    println("  julia test_instance.jl ../../data/sndlib/abilene.xml ../settings/default.toml results/abilene.csv")
    exit(1)
end

"""
    print_summary(result::InstanceResult)::Nothing

Print formatted summary of instance results.

# Arguments
- `result::InstanceResult`: Named tuple containing instance statistics
"""
function print_summary(result::InstanceResult)::Nothing
    println()
    println("="^70)
    println("Summary:")
    println("="^70)
    println("Status: $(result.status)")
    println("Objective: $(round(result.objective_value; digits=2))")
    println("Bound: $(round(result.bound; digits=2))")
    println("BB nodes: $(result.bb_nodes)")
    println("Total time: $(@sprintf("%.2f", result.total_time))s")
    println("Solve time: $(@sprintf("%.2f", result.solve_time))s")
    
    if result.model_type == "benders"
        println("Master time: $(@sprintf("%.2f", result.master_time))s")
        println("Callback time: $(@sprintf("%.2f", result.callback_time))s")
        println("Subproblem time: $(@sprintf("%.2f", result.subproblem_time))s")
        println("ML training time: $(@sprintf("%.2f", result.ml_training_time))s")
        println("DBSCAN time: $(@sprintf("%.2f", result.dbscan_time))s")
        println("Benders iterations: $(result.benders_iterations)")
        println("Benders cuts added: $(result.benders_cuts)")
        println("Benders cuts found: $(result.benders_cuts_found)")
        println("Benders subproblems solved: $(result.benders_subproblems_solved)")
    end
    
    println("="^70)
    return nothing
end

"""
    main()::Nothing

Main entry point for the script.
"""
function main()::Nothing
    length(ARGS) == 3 || print_usage()
    
    network_file = ARGS[1]
    settings_file = ARGS[2]
    output_csv = ARGS[3]
    
    println("="^70)
    println("Network Design Instance Test")
    println("="^70)
    println("Network file: $network_file")
    println("Settings file: $settings_file")
    println("Output CSV: $output_csv")
    println()
    
    try
        result = solve_instance_with_stats(network_file, settings_file)
        write_result_to_csv(result, output_csv)
        print_summary(result)
        exit(0)
    catch e
        println()
        println("ERROR: Failed to solve instance")
        println("Exception: $e")
        println()
        Base.showerror(stdout, e, catch_backtrace())
        println()
        exit(1)
    end
end

# Run main if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
