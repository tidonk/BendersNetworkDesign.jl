"""
    BendersNetworkDesign

Two-stage stochastic network design solver with Benders decomposition
and intelligent subproblem filtering strategies.

# Author
Tim Holt

# Features
- Compact MIP formulation (validated against literature)
- Benders decomposition with configurable subproblem/cut selection
- Gurobi optimization solver support
- SNDlib network instance reader
- Outage scenario generation (single-link failures)

# Exports
- `solve_compact_model`: Solve network design using compact formulation
- `build_compact_model`: Build JuMP model
- `read_sndlib_network`: Read SNDlib XML network files
- `generate_outage_scenarios`: Generate link failure scenarios
- `read_settings`: Load configuration from TOML
"""
module BendersNetworkDesign

using JuMP
using Random
using Dates

# Optional solvers
const GUROBI_AVAILABLE = try
    using Gurobi
    true
catch
    false
end

# Include submodules
include("io/read_settings.jl")
include("io/read_sndlib.jl")
include("io/write_sndlib.jl")
include("network/outages.jl")
include("network/graph.jl")
include("network/instance.jl")
include("core/subproblem.jl")
include("core/subproblem_scoring.jl")
include("core/subproblem_scoring_ml.jl")
include("core/subproblem_scoring_ml_multi.jl")
include("core/subproblem_scoring_ml_metrics.jl")
include("core/subproblem_selection_ml.jl")
include("core/subproblem_selection.jl")
include("core/subproblem_selection_oracle.jl")
include("core/cut_filtering.jl")
include("models/compact.jl")
include("models/benders.jl")

# Exports
export solve_compact_model, build_compact_model
export solve_benders
export SubproblemData, build_subproblem, update_subproblem!, reset_subproblem!, build_benders_cut
export SubproblemScore, update_subproblem_score!, increment_staleness!, compute_scaled_scores!, reset_all_scores!
export OnlineLogisticRegression, predict_subproblem_infeasibility, train_subproblem_model!, print_ml_metrics_summary
export MultiRegressorML, FeatureConfig, predict_multi_regressor, train_multi_regressor!, aggregate_metrics, save_multi_regressor_model, load_multi_regressor_model
export count_features, build_adjacency_list, get_khop_neighbors, get_links_in_khop_neighborhood, compute_khop_stats, extract_multi_regressor_features
export ProportionPredictor, predict_proportion, train_proportion_predictor!, 
       extract_full_features, update_exponential_average!, print_ml_selection_weights,
       extract_score_features, extract_utilization_features
export SelectionStrategy, StaticCutLimit, AdaptiveCutLimit, IterationData, should_stop_solving, order_scenarios, is_stabilization_round
export OracleSelection, OracleData, record_cut_scenario!, write_oracle_data, read_oracle_data, get_oracle_scenarios, order_scenarios_with_oracle
export compute_effective_limit, create_selection_strategy
export CutFilteringStrategy, NoFiltering, DiversityFiltering, EfficacyFiltering, HybridFiltering, CutCandidate, filter_cuts, create_filtering_strategy
export read_sndlib_network
export write_sndlib_network
export read_settings, get_optimizer, print_settings
export Settings, Limit
export SNDlibNetwork, NetworkStructure, Node, Link, Demand
export OutageScenario, generate_outage_scenarios, sample_outage_scenarios
export compute_node_degrees, get_high_degree_nodes, is_network_connected, compute_average_degree
export extract_subgraph, extract_network_subset, merge_networks, add_prefix_to_network, merge_two_networks
export combine_sndlib_instances, scale_network_demands, scale_network_capacities, normalize_network, balance_combined_network
export generate_single_instance, generate_instance_suite
export export_network_to_csv
export main

"""
    print_network_info(network::SNDlibNetwork, network_file::String)

Print network statistics.
"""
function print_network_info(network::SNDlibNetwork, network_file::String)::Nothing
    println("\nLoading network: $network_file")
    println("  Nodes: $(length(network.network_structure.nodes))")
    println("  Links: $(length(network.network_structure.links))")
    println("  Demands: $(length(network.demands))")
    println("  Total preinstalled capacity: $(sum(l.preinstalled_capacity !== nothing ? l.preinstalled_capacity : 0.0 for l in values(network.network_structure.links)))")
    println("  Base demand total: $(sum(d.demand_value for d in values(network.demands)))")
    if network.meta !== nothing && network.meta.granularity !== nothing
        println("  Base demand granularity: $(network.meta.granularity)")
    end
end

"""
    prepare_outage_scenarios(network::SNDlibNetwork, settings::Settings) -> Vector{OutageScenario}

Generate or sample outage scenarios based on settings.
"""
function prepare_outage_scenarios(network::SNDlibNetwork, settings::Settings)::Vector{OutageScenario}
    k = settings.contingency_k
    # println("\nGenerating outage scenarios (N-$k contingencies)...")
    
    outage_scenarios = if settings.num_outage_scenarios == -1
        # Use all valid scenarios
        scenarios = generate_outage_scenarios(network, include_base_case=true, k=k)
        # println("  Using all valid $k-link outage scenarios: $(length(scenarios))")
        scenarios
    else
        # Sample specified number of scenarios
        scenarios = sample_outage_scenarios(
            network, 
            settings.num_outage_scenarios,
            seed=settings.outage_sampling_seed,
            k=k,
            include_base_case=true
        )
        # println("  Sampled $(length(scenarios)) outage scenarios (including base case)")
        # println("  Random seed: $(settings.outage_sampling_seed)")
        scenarios
    end
    
    # println("  (Filtered out outages that disconnect demand nodes)")
    
    # Print scenario details
    # for scenario in outage_scenarios
    #     if isempty(scenario.failed_link_indices)
    #         println("  Scenario $(scenario.id): Base case (no failures)")
    #     else
    #         println("  Scenario $(scenario.id): Failed link indices: $(scenario.failed_link_indices)")
    #     end
    # end
    
    return outage_scenarios
end

"""
    print_solution(result, model_type::String, settings)

Print solution statistics and installed modules.
"""
function print_solution(result::NamedTuple, model_type::String, settings)::Nothing
    println("\n" * "=" ^70)
    println("Solution:")
    println("=" ^70)
    
    if model_type == "benders"
        println("  Status: $(result.status)")
        println("  Objective: $(round(result.objective_value, digits=2))")
        println("  Iterations: $(result.iterations)")
        println("  Modules installed: $(length(result.y_solution))")
    else
        println("  Status: $(result.status)")
        println("  Objective: $(round(result.objective_value, digits=2))")
        println("  Modules installed: $(length(result.y_solution))")
    end
    
    # Show installed modules if print_solution is enabled
    if settings.print_solution && !isempty(result.y_solution)
        println("\nInstalled modules:")
        for ((l, m), val) in sort(collect(result.y_solution), by=x->x[1])
            println("    Link $l, module $m: $(round(Int, val)) units")
        end
    end
    println("=" ^70)
end

function main(network_file::String="../data/sndlib/abilene.xml",
              settings_file::String="")::Int
    # Validate arguments
    if isempty(network_file)
        println("Usage: main(network_file, [settings_file])")
        println("Example: main(\"../data/sndlib/germany50.xml\", \"settings/default.toml\")")
        return 1
    end
    
    println("=" ^70)
    println("Two-Stage Stochastic Network Design Solver")
    println("=" ^70)
    
    # Load settings
    settings = isempty(settings_file) ? read_settings() : read_settings(settings_file)
    println("\nSettings file: ", isempty(settings_file) ? "default (built-in)" : settings_file)
    #print_settings(settings)
    
    # Check file exists
    if !isfile(network_file)
        println("\nError: Network file not found: $network_file")
        return 1
    end
    
    # Load network
    network = read_sndlib_network(network_file)
    print_network_info(network, network_file)
    
    # Prepare outage scenarios
    outage_scenarios = prepare_outage_scenarios(network, settings)
    
    # Solve with selected model type
    if settings.model_type == "benders"
        println("\nSolving with Benders decomposition...")
        
        result = solve_benders(
            network;
            optimizer=settings.optimizer,
            outage_scenarios=outage_scenarios,
            settings=settings
        )
        
        print_solution(result, "benders", settings)
        return result.status == MOI.OPTIMAL ? 0 : 1
        
    else  # compact model
        println("\nSolving with compact formulation...")
        
        result = solve_compact_model(
            network;
            optimizer=settings.optimizer,
            outage_scenarios=outage_scenarios
        )
        
        print_solution(result, "compact", settings)
        return result.status == OPTIMAL ? 0 : 1
    end
end

end # module
