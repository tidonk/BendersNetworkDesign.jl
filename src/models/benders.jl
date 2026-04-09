using JuMP
using Statistics
using Printf
import Gurobi
const MOI = JuMP.MOI

# ============================================================================
# ML Helper Functions
# ============================================================================

"""
    extract_base_flow_values(cb_data, f_base_var, demands, links)

Extract base case flow solution from callback data for ML feature extraction.
"""
function extract_base_flow_values(cb_data, f_base_var, demands::Dict, links::Vector{String})
    f_base_values = Dict{Tuple{String,Tuple{String,Symbol}},Float64}()
    D = collect(keys(demands))
    
    for d in D
        for l in links
            f_base_values[(d, (l, :forward))] = callback_value(cb_data, f_base_var[d, (l, :forward)])
            f_base_values[(d, (l, :backward))] = callback_value(cb_data, f_base_var[d, (l, :backward)])
        end
    end
    
    return f_base_values
end

"""
    update_ml_predictions!(ml_model::Union{OnlineLogisticRegression,MultiRegressorML}, ...)

Update ML predictions for all subproblems based on current master solution.
Dispatches to single or multi-regressor implementation based on model type.
"""
function update_ml_predictions!(ml_model::OnlineLogisticRegression,
                                subproblem_scores::Dict{Int,SubproblemScore},
                                outage_scenarios::Vector{OutageScenario},
                                y_values::Dict{Tuple{String,Int},Float64},
                                link_modules::Dict{String,Vector{Tuple{Int,Float64,Float64}}},
                                f_base_values::Dict,
                                links::Vector{String},
                                iteration::Int,
                                upper_bound::Float64,
                                lower_bound::Float64,
                                cumulative_cuts::Int,
                                link_centrality::Union{Dict{String,Float64},Nothing}=nothing,
                                nodes=nothing,
                                network_links=nothing,
                                adjacency=nothing)::Nothing
    for outage in outage_scenarios
        # Skip base case (no failed links)
        if !isempty(outage.failed_link_indices)
            # Predict infeasibility probability (supports k-contingencies)
            prob_infeasible = predict_subproblem_infeasibility(
                ml_model, y_values, link_modules, outage.failed_link_indices, 
                f_base_values, links, outage.id, subproblem_scores,
                iteration, upper_bound, lower_bound, cumulative_cuts, link_centrality
            )
            
            # Update ML prediction score component
            subproblem_scores[outage.id].r_ml_prediction = prob_infeasible
        end
    end
    
    return nothing
end

"""
    update_ml_predictions!(ml_model::MultiRegressorML, ...)

Multi-regressor version: each scenario has its own model.
"""
function update_ml_predictions!(ml_model::MultiRegressorML,
                                subproblem_scores::Dict{Int,SubproblemScore},
                                outage_scenarios::Vector{OutageScenario},
                                y_values::Dict{Tuple{String,Int},Float64},
                                link_modules::Dict{String,Vector{Tuple{Int,Float64,Float64}}},
                                f_base_values::Dict,
                                links::Vector{String},
                                iteration::Int,
                                upper_bound::Float64,
                                lower_bound::Float64,
                                cumulative_cuts::Int,
                                link_centrality::Union{Dict{String,Float64},Nothing}=nothing,
                                nodes=nothing,
                                network_links=nothing,
                                adjacency=nothing)::Nothing
    @assert nodes !== nothing "Multi-regressor requires nodes"
    @assert network_links !== nothing "Multi-regressor requires network_links"
    @assert adjacency !== nothing "Multi-regressor requires adjacency"
    
    for outage in outage_scenarios
        # Skip base case (no failed links)
        if !isempty(outage.failed_link_indices)
            # Predict using scenario-specific regressor
            prob_infeasible = predict_multi_regressor(
                ml_model, outage.id,
                y_values, link_modules, outage.failed_link_indices,
                f_base_values, links, nodes, network_links, adjacency,
                link_centrality, subproblem_scores
            )
            
            # Update ML prediction score component
            subproblem_scores[outage.id].r_ml_prediction = prob_infeasible
        end
    end
    
    return nothing
end

"""
    train_ml_on_subproblem!(ml_model::Union{OnlineLogisticRegression,MultiRegressorML}, ...)

Train ML model on a subproblem result and return training time.
Dispatches to single or multi-regressor implementation.
"""
function train_ml_on_subproblem!(ml_model::OnlineLogisticRegression,
                                 outage::OutageScenario,
                                 y_values::Dict{Tuple{String,Int},Float64},
                                 link_modules::Dict{String,Vector{Tuple{Int,Float64,Float64}}},
                                 f_base_values::Dict,
                                 links::Vector{String},
                                 cut_found::Bool,
                                 subproblem_scores::Dict{Int,SubproblemScore},
                                 iteration::Int,
                                 upper_bound::Float64,
                                 lower_bound::Float64,
                                 cumulative_cuts::Int,
                                 link_centrality::Union{Dict{String,Float64},Nothing}=nothing,
                                 nodes=nothing,
                                 network_links=nothing,
                                 adjacency=nothing)::Float64
    # Train for all contingencies (k>=1)
    if isempty(outage.failed_link_indices)
        return 0.0
    end
    
    ml_train_start = time()
    train_subproblem_model!(ml_model, y_values, link_modules, 
                           outage.failed_link_indices, f_base_values, links, outage.id, cut_found, subproblem_scores,
                           iteration, upper_bound, lower_bound, cumulative_cuts, link_centrality)
    
    return time() - ml_train_start
end

"""
    train_ml_on_subproblem!(ml_model::MultiRegressorML, ...)

Multi-regressor version: train scenario-specific model.
"""
function train_ml_on_subproblem!(ml_model::MultiRegressorML,
                                 outage::OutageScenario,
                                 y_values::Dict{Tuple{String,Int},Float64},
                                 link_modules::Dict{String,Vector{Tuple{Int,Float64,Float64}}},
                                 f_base_values::Dict,
                                 links::Vector{String},
                                 cut_found::Bool,
                                 subproblem_scores::Dict{Int,SubproblemScore},
                                 iteration::Int,
                                 upper_bound::Float64,
                                 lower_bound::Float64,
                                 cumulative_cuts::Int,
                                 link_centrality::Union{Dict{String,Float64},Nothing}=nothing,
                                 nodes=nothing,
                                 network_links=nothing,
                                 adjacency=nothing)::Float64
    if isempty(outage.failed_link_indices)
        return 0.0
    end
    
    @assert nodes !== nothing "Multi-regressor requires nodes"
    @assert network_links !== nothing "Multi-regressor requires network_links"
    @assert adjacency !== nothing "Multi-regressor requires adjacency"
    
    ml_train_start = time()
    train_multi_regressor!(ml_model, outage.id, cut_found,
                          y_values, link_modules, outage.failed_link_indices,
                          f_base_values, links, nodes, network_links, adjacency,
                          link_centrality, subproblem_scores)
    
    return time() - ml_train_start
end

"""
    filter_cuts_with_timing(candidate_cuts, filtering_strategy, settings, iteration, total_dbscan_time_ref) -> (Vector{CutCandidate}, Float64)

Apply cut filtering strategy and track timing, return filtered cuts and elapsed time.
Consolidates filtering, timing, and logging into a single function.
"""
function filter_cuts_with_timing(candidate_cuts::Vector{CutCandidate}, 
                                 filtering_strategy::CutFilteringStrategy, 
                                 settings::Settings, 
                                 iteration::Int,
                                 total_dbscan_time_ref::Base.RefValue{Float64})::Tuple{Vector{CutCandidate}, Float64}
    filtering_start = time()
    filtered_cuts = filter_cuts(candidate_cuts, filtering_strategy)
    filtering_elapsed = time() - filtering_start
    
    # Track DBSCAN time if using diversity filtering
    if isa(filtering_strategy, DiversityFiltering) && length(candidate_cuts) > 0
        total_dbscan_time_ref[] += filtering_elapsed
        
        # Print DBSCAN timing if logging enabled
        if settings.subproblem_log
            print_dbscan_line(iteration, filtering_elapsed, length(filtered_cuts), length(candidate_cuts))
        end
    end
    
    return filtered_cuts, filtering_elapsed
end

# ============================================================================
# Iteration Data and Helper Functions
# ============================================================================

"""
    populate_iteration_data!(iter_data, cb_data, callback_start_time, iteration)

Populate iteration data structure with bounds, gap, and timing information.

Extracts from Gurobi callback:
- Upper bound (primal): from GRB_CB_MIPSOL_OBJBST or GRB_CB_MIPNODE_OBJBST
- Lower bound (dual): from GRB_CB_MIPNODE_OBJBND
- Calculates optimality gap from bounds

Updates iter_data fields:
- iteration, cuts_added_this_iter, consecutive_no_cuts, iteration_start_time
- ub, lb, gap

See: https://docs.gurobi.com/projects/optimizer/en/current/reference/numericcodes/callbacks.html#where-mip
"""
function populate_iteration_data!(iter_data::IterationData, cb_data, callback_start_time::Float64, iteration::Int)
    # Set basic iteration info
    iter_data.iteration = iteration
    iter_data.cuts_found_this_iter = 0
    iter_data.cuts_added_this_iter = 0
    iter_data.num_solves_this_iter = 0
    iter_data.consecutive_no_cuts = 0
    iter_data.iteration_start_time = callback_start_time
    
    # Extract bounds from Gurobi callback using GRBcbget
    try
        primal_bound = Ref{Cdouble}()
        dual_bound = Ref{Cdouble}()
        
        # Try to get primal bound (best objective found)
        ret_primal = Gurobi.GRBcbget(cb_data, Gurobi.GRB_CB_MIPSOL, Gurobi.GRB_CB_MIPSOL_OBJBST, primal_bound)
        if ret_primal == 0 && isfinite(primal_bound[])
            iter_data.ub = primal_bound[]
        end
        
        # Try to get dual bound (best bound)
        ret_dual = Gurobi.GRBcbget(cb_data, Gurobi.GRB_CB_MIPSOL, Gurobi.GRB_CB_MIPSOL_OBJBND, dual_bound)
        if ret_dual == 0 && isfinite(dual_bound[]) && dual_bound[] > -1e10
            iter_data.lb = dual_bound[]
        end
    catch e
        # If callback query fails, keep default values
    end
    
    # Calculate optimality gap using Gurobi's formula
    # Gap = |UB - LB| / |UB| (relative gap based on primal bound)
    # See: https://www.gurobi.com/documentation/current/refman/mipgap2.html
    if isfinite(iter_data.ub) && isfinite(iter_data.lb) && abs(iter_data.ub) > 1e-10
        iter_data.gap = abs(iter_data.ub - iter_data.lb) / abs(iter_data.ub)
    else
        iter_data.gap = Inf
    end
end

"""
    get_node_count(cb_data) -> Int

Get current node count from Gurobi callback.

Returns the number of explored nodes in the branch-and-bound tree.
Used to detect root node (node_count == 0).
"""
function get_node_count(cb_data)::Int
    try
        node_count = Ref{Cdouble}()
        ret = Gurobi.GRBcbget(cb_data, Gurobi.GRB_CB_MIPSOL, Gurobi.GRB_CB_MIPSOL_NODCNT, node_count)
        if ret == 0
            return Int(node_count[])
        end
    catch e
        # If callback query fails, assume not at root
    end
    return 1  # Default: assume not at root node
end

"""
    print_iteration_header(iteration::Int, use_ml::Bool)

Print header for verbose iteration output.
"""
function print_iteration_header(iteration::Int, use_ml::Bool)
    if use_ml
        @printf("                                                                                         Iter | Scenario | Score     | ML Pred  | Time(s)  | Cut\n")
    else
        @printf("                                                                                         Iter | Scenario | Score     | Time(s)  | Cut\n")
    end
end

"""
    print_subproblem_line(iteration::Int, scenario_id::Int, subproblem_score::SubproblemScore, elapsed::Float64, cut_added::Bool, use_ml::Bool)

Print single line for a solved subproblem.
"""
function print_subproblem_line(iteration::Int, scenario_id::Int, subproblem_score::SubproblemScore, elapsed::Float64, cut_added::Bool, use_ml::Bool)
    cut_marker = cut_added ? "X" : ""
    score = subproblem_score.scaled_score
    ml_pred = subproblem_score.r_ml_prediction
    
    if use_ml
        @printf("                                                                                         %4d | %8d | %9.6f | %8.6f | %8.4f | %s\n", 
                iteration, scenario_id, score, ml_pred, elapsed, cut_marker)
    else
        @printf("                                                                                         %4d | %8d | %9.6f | %8.4f | %s\n", 
                iteration, scenario_id, score, elapsed, cut_marker)
    end
end

"""
    print_iteration_summary(iteration::Int, num_solved::Int, num_cuts::Int, total_time::Float64)

Print summary after completing an iteration, including accuracy (percentage of solved SPs that produced cuts).
"""
function print_iteration_summary(iteration::Int, num_solved::Int, num_cuts::Int, total_time::Float64)
    accuracy = num_solved > 0 ? round(100.0 * num_cuts / num_solved, digits=1) : 0.0
    @printf("                                                                                            Σ | %8d | %9s | %8.4f | Cuts: %d (Hits: %.1f%%)\n", 
            num_solved, "", total_time, num_cuts, accuracy)
end

"""
    print_solve_summary(total_solve_time, total_master_time, total_callback_time, total_subproblem_solve_time, total_ml_training_time, use_ml, ml_model)

Print timing and ML metrics summary after solving.
"""
function print_solve_summary(total_solve_time::Float64, 
                            total_master_time::Float64, 
                            total_callback_time::Float64, 
                            total_subproblem_solve_time::Float64, 
                            total_ml_training_time::Float64,
                            total_ml_selection_time::Float64,
                            total_dbscan_time::Float64,
                            use_ml::Bool,
                            use_selection_ml::Bool,
                            ml_model,
                            ml_statistics::Bool)::Nothing
    println("\n" * "="^80)
    println("TIMING SUMMARY")
    println("="^80)
    @printf("Total solve time:           %10.2f s\n", total_solve_time)
    @printf("Total master time:          %10.2f s  (%5.1f%%)\n", 
            total_master_time, 100.0 * total_master_time / total_solve_time)
    @printf("Total callback time:        %10.2f s  (%5.1f%%)\n", 
            total_callback_time, 100.0 * total_callback_time / total_solve_time)
    @printf("  └─ Subproblem solve time: %10.2f s  (%5.1f%% of callback)\n", 
            total_subproblem_solve_time, 100.0 * total_subproblem_solve_time / max(total_callback_time, 1e-10))
    if use_ml
        @printf("  └─ ML scoring time:       %10.2f s  (%5.1f%% of callback)\n", 
                total_ml_training_time, 100.0 * total_ml_training_time / max(total_callback_time, 1e-10))
    end
    if use_selection_ml && total_ml_selection_time > 0.0
        @printf("  └─ ML selection time:     %10.2f s  (%5.1f%% of callback)\n", 
                total_ml_selection_time, 100.0 * total_ml_selection_time / max(total_callback_time, 1e-10))
    end
    if total_dbscan_time > 0.0
        @printf("  └─ DBSCAN clustering:     %10.2f s  (%5.1f%% of callback)\n", 
                total_dbscan_time, 100.0 * total_dbscan_time / max(total_callback_time, 1e-10))
    end
    println("="^80)
    
    # Print ML metrics if model was used and ml_statistics is enabled
    if ml_statistics && use_ml && !isnothing(ml_model)
        print_ml_metrics_summary(ml_model)
    end
    
    return nothing
end

"""
    print_dbscan_line(iteration::Int, elapsed::Float64, selected::Int, total::Int)

Print timing information for DBSCAN clustering with cut selection statistics.
"""
function print_dbscan_line(iteration::Int, elapsed::Float64, selected::Int, total::Int)
    pct = total > 0 ? round(100.0 * selected / total, digits=1) : 0.0
    @printf("                                                                                         %4d | %8s | %9s | %8.4f | Selected %d/%d (%.1f%%)\n", 
            iteration, "DBSCAN", "", elapsed, selected, total, pct)
end
"""
    print_ml_training_line(iteration::Int, elapsed::Float64, num_trained::Int)

Print timing information for ML training.
"""
function print_ml_training_line(iteration::Int, elapsed::Float64, num_trained::Int)
    @printf("                                                                                         %4d | %8s | %9s | %8.4f | Trained on %d scenarios\n", 
            iteration, "ML Train", "", elapsed, num_trained)
end
"""
    update_scores_for_iteration!(subproblem_scores, settings, iter_data, stabilization_frequency)

Handle all score-related updates for the current iteration:
- Check for initialization round (iteration 1) if enabled
- Check for stabilization round and reset scores if needed
- Increment staleness for all scenarios
- Compute scaled scores for ordering
"""
function update_scores_for_iteration!(subproblem_scores::Dict{Int,SubproblemScore}, 
                                     settings::Settings, 
                                     iter_data::IterationData,
                                     stabilization_frequency::Int)
    # Check if this is an initialization round (first iteration with score initialization enabled)
    iter_data.is_initialization_round = (iter_data.iteration == 1 && settings.score_initialization_enabled)
    
    if iter_data.is_initialization_round
        println("  [Score initialization round: solving all scenarios to establish initial rankings]")
        reset_all_scores!(subproblem_scores)
    end
    
    # Check if this is a stabilization round
    iter_data.is_stabilization_round = is_stabilization_round(iter_data.iteration, stabilization_frequency)
    
    if iter_data.is_stabilization_round
        # Only reset scores if not at root node (preserve ML training data at root)
        if !iter_data.is_root_node
            println("  [Stabilization round $(iter_data.iteration): solving all scenarios, resetting scores]")
            reset_all_scores!(subproblem_scores)
        else
            println("  [Stabilization round $(iter_data.iteration) at root node: solving all scenarios, preserving ML scores]")
        end
    end
    
    # Increment staleness
    if settings.subproblem_ordering == "score" && !iter_data.is_stabilization_round
        increment_staleness!(subproblem_scores)
    end
end

"""
Benders decomposition for network design with survivability.

Master Problem (MP): 
  - First-stage: module installation decisions (y variables)
  - Second-stage: base case (no failure) flow routing
  - Includes Benders cuts from subproblems

Subproblem (SP): 
  - For each link failure scenario, routes demands
  - Fixed capacity from MP's y solution
  - One reusable LP model, modified per scenario
"""



"""
    build_master_problem(network, demands; optimizer) -> (Model, Dict)

Construct Benders master problem with module installation decisions and base case flows.

Configures Gurobi with LazyConstraints=1 for lazy constraint callback support.

# Arguments
- `network`: SNDlib network structure
- `demands`: Dict{String,Float64} mapping demand_id to demand_value
- `optimizer`: JuMP optimizer constructor

# Returns
- Master problem JuMP model
- Dictionary of link modules: link_id => [(module_id, capacity, cost), ...]
"""
function build_master_problem(network, demands::Dict{String,Float64}; optimizer)::Tuple{Model, Dict{String, Vector{Tuple{Int, Float64, Float64}}}}
    nodes = network.network_structure.nodes
    links = network.network_structure.links
    
    N = collect(keys(nodes))
    L = collect(keys(links))
    A = vcat([(l, :forward) for l in L], [(l, :backward) for l in L])
    D = collect(intersect(keys(network.demands), keys(demands)))
    
    # Build module index for each link
    link_modules = Dict{String, Vector{Tuple{Int, Float64, Float64}}}()
    for (lid, link) in links
        mods = Tuple{Int, Float64, Float64}[]
        if !isnothing(link.preinstalled_capacity) && link.preinstalled_capacity > 0
            push!(mods, (0, link.preinstalled_capacity, 0.0))
        end
        for (m_idx, (cap, cost)) in enumerate(link.additional_modules)
            push!(mods, (m_idx, cap, cost))
        end
        link_modules[lid] = mods
    end
    
    model = Model(optimizer)
    
    # Set time limit
    settings = read_settings()
    set_time_limit_sec(model, settings.time_limit)
    
    # Configure Gurobi parameters for Benders
    try
        set_attribute(model, "LazyConstraints", 1)
        set_attribute(model, "Seed", 0)  # Set seed for deterministic solving
    catch
        @warn "Failed to set Gurobi attributes (may not be using Gurobi)"
    end
    
    # First-stage: module installation variables
    @variable(model, y[l in L, m in eachindex(link_modules[l])] >= 0, Int, base_name="y")
    
    # Second-stage: base case flow variables
    @variable(model, f_base[d in D, a in A] >= 0, base_name="f_base")
    
    # Recourse variable: cost of handling failure scenarios
    @variable(model, θ >= 0, base_name="theta")
    
    # Preinstalled capacity constraints
    for l in L
        mods = link_modules[l]
        if !isempty(mods) && mods[1][1] == 0
            @constraint(model, y[l, 1] <= 1, base_name="preinstalled")
        end
    end
    
    install_cost = sum(link_modules[l][m][3] * y[l, m] for l in L for m in eachindex(link_modules[l]))
    @objective(model, Min, install_cost + θ)
    
    arc_endpoints(link_id, dir) = begin
        link = links[link_id]
        dir == :forward ? (link.source, link.target) : (link.target, link.source)
    end
    
    # Base case flow conservation constraints
    for d in D
        demand = network.demands[d]
        src, tgt = demand.source, demand.target
        demand_val = demands[d]
        
        for n in N
            out_arcs = [a for a in A if arc_endpoints(a[1], a[2])[1] == n]
            in_arcs = [a for a in A if arc_endpoints(a[1], a[2])[2] == n]
            
            net_flow = sum(f_base[d,a] for a in out_arcs; init=0.0) - 
                      sum(f_base[d,a] for a in in_arcs; init=0.0)
            
            if n == src
                @constraint(model, net_flow == demand_val, base_name="flow_base")
            elseif n == tgt
                @constraint(model, net_flow == -demand_val, base_name="flow_base")
            else
                @constraint(model, net_flow == 0, base_name="flow_base")
            end
        end
    end
    
    # Base case capacity constraints
    for l in L
        mods = link_modules[l]
        total_capacity = sum(mods[m][2] * y[l, m] for m in eachindex(mods))
        @constraint(model, sum(f_base[d,(l,:forward)] for d in D) + 
                    sum(f_base[d,(l,:backward)] for d in D) <= total_capacity, 
                    base_name="capacity_base")
    end
    
    return model, link_modules
end




"""
    validate_cut(cut_lhs, cut_rhs, cb_data)

Check if a cut is violated by the current solution.

For constraint cut_lhs <= cut_rhs, violation occurs when cut_lhs > cut_rhs.
Returns true if cut is violated (should be added), false otherwise.
Prints warning if cut is not violated.
"""
function validate_cut(cut_lhs::AffExpr, cut_rhs::Union{Float64, VariableRef}, cb_data)::Bool
    lhs_value = callback_value(cb_data, cut_lhs)
    rhs_value = isa(cut_rhs, Number) ? cut_rhs : callback_value(cb_data, cut_rhs)
    violation = lhs_value - rhs_value
    
    if violation <= 1e-6
        @warn "Cut is not violated! LHS=$(lhs_value), RHS=$(rhs_value), violation=$(violation)"
        return false
    end
    
    return true
end


"""
    predict_ml_selection_limit!(selection_strategy, network, subproblem_scores, 
                                 outage_scenarios, iteration, iter_data, settings)

Helper function: Predict proportion of subproblems that will yield cuts and set dynamic limit.
"""
function predict_ml_selection_limit!(selection_strategy, network, subproblem_scores, 
                                     outage_scenarios, iteration, iter_data, settings)
    if !(selection_strategy isa AdaptiveCutLimit && selection_strategy.mode == "prediction_based" && 
         selection_strategy.proportion_predictor !== nothing && !iter_data.is_initialization_round)
        return
    end
    
    predictor = selection_strategy.proportion_predictor
    n_scenarios = length(outage_scenarios)
    features = extract_full_features(network, subproblem_scores)
    predicted_prop = predict_proportion(predictor, features)
    
    min_cuts = max(1, round(Int, selection_strategy.min_proportion * n_scenarios))
    max_cuts = round(Int, selection_strategy.max_proportion * n_scenarios)
    predicted_cuts = round(Int, predicted_prop * n_scenarios)
    selection_strategy.current_cuts = clamp(predicted_cuts, min_cuts, max_cuts)
    
    if settings.subproblem_log
        @printf("                                                                                         %4d | %8s | %9s | %8s | Predicted %.1f%% → solving %d/%d\n", 
                iteration[], "ML Pred", "", "", predicted_prop*100, selection_strategy.current_cuts, n_scenarios)
    end
end

"""
    train_ml_selection!(selection_strategy, network, subproblem_scores, iter_data, 
                       total_cuts_added, total_ml_selection_time, iteration, settings, outage_scenarios)

Helper function: Train ML selection predictor with recall bias protection.
"""
function train_ml_selection!(selection_strategy, network, subproblem_scores, iter_data, 
                            total_cuts_added, total_ml_selection_time, iteration, settings, outage_scenarios)
    if !(selection_strategy isa AdaptiveCutLimit && selection_strategy.mode == "prediction_based" && 
         selection_strategy.proportion_predictor !== nothing && iteration[] > 1)
        return
    end
    
    selection_train_start = time()
    predictor = selection_strategy.proportion_predictor
    sample_rate = iter_data.num_solves_this_iter / length(outage_scenarios)
    
    if sample_rate < predictor.min_training_sample_rate
        if settings.subproblem_log
            @printf("                                                                                         %4d | %8s | %9s | %8s | Skip training (%.1f%% < %.1f%%)\n", 
                    iteration[], "ML Skip", "", "", sample_rate*100, predictor.min_training_sample_rate*100)
        end
        total_ml_selection_time[] += time() - selection_train_start
        return
    end
    
    actual_proportion = iter_data.cuts_found_this_iter / iter_data.num_solves_this_iter
    features = extract_full_features(network, subproblem_scores)
    train_proportion_predictor!(predictor, features, actual_proportion)
    update_exponential_average!(predictor.performance_history, actual_proportion, predictor.history_decay)
    
    total_ml_selection_time[] += time() - selection_train_start
    
    if settings.subproblem_log
        @printf("                                                                                         %4d | %8s | %9s | %8s | Trained: %.1f%% (%d/%d scenarios)\n", 
                iteration[], "ML Train", "", "", actual_proportion*100, iter_data.cuts_found_this_iter, iter_data.num_solves_this_iter)
    end
end

"""
    solve_benders(network; optimizer, outage_scenarios, settings)

Solve network design problem using Benders decomposition with lazy constraint callback.

# Arguments
- `network`: SNDlibNetwork structure (demands extracted from network.demands)
- `optimizer`: JuMP-compatible optimizer constructor
- `outage_scenarios`: Vector{OutageScenario} of outage scenarios to consider
- `settings`: Settings object with all configuration parameters

# Returns
Named tuple with solution details
"""
function solve_benders(network::SNDlibNetwork; 
                      optimizer, 
                      outage_scenarios::Vector{OutageScenario},
                      settings::Settings)
    # Extract demands from network
    demands = Dict{String,Float64}(d_id => d.demand_value for (d_id, d) in network.demands)
    
    master, link_modules = build_master_problem(network, demands; optimizer)
    sp = build_subproblem(network, demands; optimizer)
    
    L = sp.links
    y_var = master[:y]
    θ_var = master[:θ]
    
    iteration = Ref(0)
    total_cuts_added = Ref(0)
    total_cuts_found = Ref(0)
    total_subproblems_solved = Ref(0)
    total_callback_time = Ref(0.0)
    total_subproblem_solve_time = Ref(0.0)
    total_ml_training_time = Ref(0.0)
    total_ml_selection_time = Ref(0.0)  # For proportion predictor training (when prediction_based mode active)
    total_dbscan_time = Ref(0.0)
    total_master_time = Ref(0.0)
    last_callback_end_time = Ref(0.0)
    # Track iterations at root for limiting fractional separation
    root_node_iterations = Ref(0)
    
    # Initialize subproblem scores
    subproblem_scores = Dict{Int,SubproblemScore}()
    for outage in outage_scenarios
        subproblem_scores[outage.id] = SubproblemScore()
    end
    
    # Check if ML model should be used
    # Train ML only if: (1) ML weight > 0, (2) ordering is "score" (so ML predictions matter), 
    # AND (3) either using selection strategy or exporting model
    use_ml = settings.scoring_weights[6] > 0.0 && 
             settings.subproblem_ordering == "score" && 
             (settings.selection_strategy != "none" || settings.ml_model_write)
    
    # Get instance name from network metadata for model persistence
    instance_name = splitext(network.meta.filename)[1]
    models_dir = joinpath(@__DIR__, "..", "..", "check", "models")
    model_path = joinpath(models_dir, "trained_model_$(instance_name).jls")
    
    # Initialize ML model only if weight > 0
    ml_model = if use_ml
        if settings.ml_model_read
            # Load pre-trained model
            if isfile(model_path)
                if settings.ml_mode == "single"
                    load_ml_model(model_path)
                else
                    load_multi_regressor_model(model_path)
                end
            else
                @warn "ML model read enabled but file not found: $model_path. Training new model."
                if settings.ml_mode == "single"
                    OnlineLogisticRegression(9; learning_rate=settings.ml_learning_rate, 
                                            regularization=settings.ml_regularization,
                                            decision_threshold=settings.ml_decision_threshold,
                                            positive_class_weight=settings.ml_positive_class_weight)
                else
                    MultiRegressorML(length(outage_scenarios);
                                    khop_distance=settings.ml_khop_distance,
                                    learning_rate=settings.ml_learning_rate,
                                    regularization=settings.ml_regularization,
                                    decision_threshold=settings.ml_decision_threshold,
                                    positive_class_weight=settings.ml_positive_class_weight)
                end
            end
        else
            # Initialize new model
            if settings.ml_mode == "single"
                # Single regressor: 9 deterministic features (3 link + 1 centrality + 5 score)
                OnlineLogisticRegression(9; learning_rate=settings.ml_learning_rate,
                                        regularization=settings.ml_regularization,
                                        decision_threshold=settings.ml_decision_threshold,
                                        positive_class_weight=settings.ml_positive_class_weight)
            else
                # Multi-regressor: configurable features (default 21 with all enabled)
                MultiRegressorML(length(outage_scenarios);
                                khop_distance=settings.ml_khop_distance,
                                learning_rate=settings.ml_learning_rate,
                                regularization=settings.ml_regularization,
                                decision_threshold=settings.ml_decision_threshold,
                                positive_class_weight=settings.ml_positive_class_weight)
            end
        end
    else
        nothing
    end
    
    # Extract base case flow variables for feature extraction (only if using ML)
    f_base_var = master[:f_base]
    D = collect(keys(demands))
    
    # Compute link betweenness centrality once (only if using ML)
    link_centrality = if use_ml
        compute_link_betweenness_centrality(network.network_structure.nodes, 
                                           network.network_structure.links)
    else
        nothing
    end
    
    # Build adjacency list for multi-regressor k-hop features (only if using multi mode)
    adjacency = if use_ml && settings.ml_mode == "multi"
        build_adjacency_list(network.network_structure.nodes, 
                            network.network_structure.links)
    else
        nothing
    end
    
    # Create selection strategy with computed limits (pass network for oracle filepath default)
    selection_strategy = create_selection_strategy(settings, length(outage_scenarios), network)
    
    # Create cut filtering strategy
    filtering_strategy = create_filtering_strategy(settings)
    
    # Initialize oracle recording if in write mode
    oracle_data = if settings.selection_strategy == "oracle" && settings.oracle_mode == "write"
        OracleData()
    else
        nothing
    end
    
    iter_data = IterationData()
    prev_iter_data = nothing
    
    # Benders callback
    function benders_callback(cb_data, cb_where::Cint)

        # Only proceed at MIP solution callbacks
        if cb_where != GRB_CB_MIPSOL #&& cb_where != GRB_CB_MIPNODE
            return
        end

        # check if status is optimal
        if cb_where == GRB_CB_MIPNODE
            resultP = Ref{Cint}()
            GRBcbget(cb_data, cb_where, GRB_CB_MIPNODE_STATUS, resultP)
            if resultP[] != GRB_OPTIMAL
                return  # Solution is something other than optimal.
            end

            nodeCount = Ref{Cint}()
            GRBcbget(cb_data, cb_where, GRB_CB_MIPNODE_NODCNT, nodeCount)
            # if not in the root node, return
            if nodeCount[] > 0
                return
            end
            
            # Check if we've exceeded the iteration limit for fractional separation at root
            if settings.max_fractional_iterations_at_root >= 0 && 
               root_node_iterations[] >= settings.max_fractional_iterations_at_root
                return  # Already completed max iterations of fractional separation at root
            end
        end

        callback_start_time = time()
        
        # Track master time (time between callbacks)
        if iteration[] > 0 && last_callback_end_time[] > 0
            total_master_time[] += callback_start_time - last_callback_end_time[]
        end
        
        iteration[] += 1
        
        # Populate iteration data (bounds, gap, timing)
        populate_iteration_data!(iter_data, cb_data, callback_start_time, iteration[])
        
        # Get current node count to check if at root node
        node_count = get_node_count(cb_data)
        iter_data.is_root_node = (node_count == 0)
        
        # Track root node iterations
        if iter_data.is_root_node
            iter_data.root_node_iteration += 1
        else
            iter_data.root_node_iteration = 0  # Reset when leaving root
        end
        
        
        # Update scores for this iteration (handles stabilization, staleness, and scaling)
        update_scores_for_iteration!(subproblem_scores, settings, iter_data, settings.stabilization_frequency)
        
        # Print header for verbose output
        if settings.subproblem_log
            print_iteration_header(iteration[], use_ml)
        end
        
        # Track iteration statistics for verbose output
        num_subproblems_solved = 0
        
        # Load primal variable values
        Gurobi.load_callback_variable_primal(cb_data, cb_where)

        # Extract current y solution
        y_values = Dict{Tuple{String,Int},Float64}()
        for l in L
            mods = link_modules[l]
            for m in eachindex(mods)
                y_values[(l,m)] = callback_value(cb_data, y_var[l,m])
            end
        end
        
        # Extract base case flow solution for ML feature extraction (only if using ML)
        f_base_values = use_ml ? extract_base_flow_values(cb_data, f_base_var, demands, L) : nothing
        
        # Update ML predictions for all subproblems (only after first iteration and if using ML)
        if use_ml && iteration[] > 1
            update_ml_predictions!(ml_model, subproblem_scores, outage_scenarios, 
                                  y_values, link_modules, f_base_values, L,
                                  iteration[], iter_data.ub, iter_data.lb, total_cuts_added[], link_centrality,
                                  network.network_structure.nodes, network.network_structure.links, adjacency)
        end
        
        # Compute scaled scores after ML predictions are updated (so Score matches ML Pred)
        if settings.subproblem_ordering == "score"
            compute_scaled_scores!(subproblem_scores; weights=settings.scoring_weights, scale=settings.scale_score)
        end
        
        # Predict proportion and set dynamic limit (prediction_based mode)
        predict_ml_selection_limit!(selection_strategy, network, subproblem_scores, 
                                   outage_scenarios, iteration, iter_data, settings)
        
        # Order scenarios (unless initialization or stabilization round)
        # Note: Oracle mode ignores initialization/stabilization and always uses oracle data
        scenarios_to_solve = if selection_strategy isa OracleSelection
            # Oracle strategy: filter scenarios based on oracle data (match by failed_link_indices)
            oracle_failed_links = get_oracle_scenarios(selection_strategy, iteration[])
            # If oracle list is empty for this iteration, it means NO cuts were found
            # In this case, we must solve ALL scenarios to verify the solution
            if isempty(oracle_failed_links)
                outage_scenarios  # Solve all scenarios (no filtering)
            else
                # Filter scenarios by matching failed_link_indices (no ordering needed - we solve all matching)
                filter(s -> s.failed_link_indices in oracle_failed_links, outage_scenarios)
            end
        elseif iter_data.is_initialization_round || iter_data.is_stabilization_round
            outage_scenarios  # Original order in initialization and stabilization rounds
        else
            order_scenarios(outage_scenarios, subproblem_scores, settings.subproblem_ordering, settings.scoring_random_seed)
        end
        
        # Collect candidate cuts before filtering
        candidate_cuts = CutCandidate[]
        cut_scenarios = Dict{Int,Bool}()  # Track which scenarios generated cuts
        scenario_solve_times = Dict{Int,Float64}()  # Track solve time per scenario (reset each iteration)
        total_iteration_subproblem_time = 0.0  # Track actual subproblem solving time for this iteration
        iteration_ml_training_time = 0.0  # Track ML training time for this iteration
        num_ml_trained = 0  # Track number of scenarios trained on
        
        # Solve subproblems with stopping criteria
        for outage in scenarios_to_solve
            # Get current score for threshold check
            # For ML-only scoring, use raw ML prediction instead of scaled score
            current_score = if use_ml && settings.scoring_weights == [0.0, 0.0, 0.0, 0.0, 0.0, 1.0]
                # ML-only: use raw prediction probability for threshold
                get(subproblem_scores, outage.id, SubproblemScore()).r_ml_prediction
            else
                # Standard: use scaled score
                get(subproblem_scores, outage.id, SubproblemScore()).scaled_score
            end
            
            # Check stopping criteria - but NOT for oracle mode (must solve all oracle scenarios)
            # For other modes: only stop after we've added at least one cut
            if !(selection_strategy isa OracleSelection) && 
               length(candidate_cuts) > 0 && 
               should_stop_solving(selection_strategy, iter_data, current_score, settings.root_node_stabilization)
                break
            end
            
            # Skip base case
            isempty(outage.failed_link_indices) && continue
            
            # Solve subproblem
            failed_indices = Set(outage.failed_link_indices)
            update_subproblem!(sp, y_values, link_modules, failed_indices)
            
            optimize!(sp.model)
            subproblem_elapsed = solve_time(sp.model)
            
            status = termination_status(sp.model)
            total_subproblem_solve_time[] += subproblem_elapsed
            total_iteration_subproblem_time += subproblem_elapsed
            num_subproblems_solved += 1
            total_subproblems_solved[] += 1
            iter_data.num_solves_this_iter += 1
            
            # Store solve time for this scenario
            scenario_solve_times[outage.id] = subproblem_elapsed
            
            # Track if cut was found
            cut_found = false
            
            # Handle infeasible: collect cut
            if status == INFEASIBLE || status == DUAL_INFEASIBLE
                cut_lhs, cut_rhs = build_benders_cut(y_var, θ_var, link_modules, L, 
                                                     failed_indices, sp, network, demands)
                
                lhs_val = callback_value(cb_data, cut_lhs)
                violation = lhs_val - cut_rhs
                
                if settings.validate_cuts && violation <= 1e-6
                    @warn "Cut not violated! LHS=$lhs_val, RHS=$cut_rhs, scenario=$(outage.id)"
                end
                
                # Extract coefficients for filtering
                coefficients = extract_cut_coefficients(cut_lhs)
                
                # Create candidate cut
                candidate = CutCandidate(cut_lhs, cut_rhs, violation, outage.id, coefficients)
                push!(candidate_cuts, candidate)
                
                iter_data.consecutive_no_cuts = 0
                iter_data.cuts_found_this_iter += 1
                total_cuts_found[] += 1
                cut_found = true
                cut_scenarios[outage.id] = true
                
                # Record oracle data if in write mode
                if oracle_data !== nothing
                    record_cut_scenario!(oracle_data, iteration[], outage.failed_link_indices)
                end
            else
                # No cut found
                iter_data.consecutive_no_cuts += 1
                cut_scenarios[outage.id] = false
                
                # Oracle validation: scenarios indicated by oracle MUST yield cuts
                # Exception: "*" iterations (expect_no_cuts=true) should NOT yield cuts
                if selection_strategy isa OracleSelection && !selection_strategy.expect_no_cuts[]
                    throw(OracleError("Oracle validation failed at iteration $(iteration[]): scenario $(outage.id) was indicated by oracle but did not yield a cut! Status: $status"))
                end
            end
            
            # Train ML model (only if using ML)
            if use_ml
                training_time = train_ml_on_subproblem!(ml_model, outage, y_values, 
                                                        link_modules, f_base_values, L, cut_found, subproblem_scores,
                                                        iteration[], iter_data.ub, iter_data.lb, total_cuts_added[], link_centrality,
                                                        network.network_structure.nodes, network.network_structure.links, adjacency)
                total_ml_training_time[] += training_time
                iteration_ml_training_time += training_time
                if training_time > 0.0
                    num_ml_trained += 1
                end
            end
            
            # Print verbose subproblem info
            if settings.subproblem_log
                # Only print if not cuts_only mode, or if a cut was found
                if !settings.subproblem_log_success || cut_found
                    print_subproblem_line(iteration[], outage.id, subproblem_scores[outage.id], 
                                         subproblem_elapsed, cut_found, use_ml)
                end
            end
            
            reset_subproblem!(sp)
        end
        
        # Apply cut filtering (consolidates timing and logging)
        filtered_cuts, filtering_elapsed = filter_cuts_with_timing(
            candidate_cuts, filtering_strategy, settings, iteration[], total_dbscan_time
        )
        
        # Record oracle data: if no cuts found in this iteration, record that fact
        if oracle_data !== nothing && isempty(candidate_cuts)
            record_no_cuts!(oracle_data, iteration[])
        end
        
        # Add filtered cuts to master problem
        for cut in filtered_cuts
            if settings.validate_cuts && settings.subproblem_log
                println("  [Iter $(iteration[])] Adding cut from scenario $(cut.scenario_id): violation=$(round(cut.violation, digits=4))")
            end
            
            con = @build_constraint(cut.cut_lhs <= cut.cut_rhs)
            MOI.submit(master, MOI.LazyConstraint(cb_data), con)
            
            iter_data.cuts_added_this_iter += 1
            total_cuts_added[] += 1
            
            # Update score for scenarios that produced cuts that were added
            if settings.subproblem_ordering == "score"
                solve_time = get(scenario_solve_times, cut.scenario_id, 0.0)
                update_subproblem_score!(subproblem_scores[cut.scenario_id], true, true, cut.violation, total_cuts_added[], solve_time)
            end
        end
        
        # Update scores for scenarios that generated cuts but weren't selected
        if settings.subproblem_ordering == "score"
            for (scenario_id, cut_found) in cut_scenarios
                solve_time = get(scenario_solve_times, scenario_id, 0.0)
                # Only update if cut was found but not added
                if cut_found && !any(c -> c.scenario_id == scenario_id, filtered_cuts)
                    update_subproblem_score!(subproblem_scores[scenario_id], true, false, 0.0, total_cuts_added[], solve_time)
                elseif !cut_found
                    update_subproblem_score!(subproblem_scores[scenario_id], false, false, 0.0, total_cuts_added[], solve_time)
                end
            end
        end
        
        # Record only actual subproblem solving time for this iteration
        iter_data.subproblem_solve_time = total_iteration_subproblem_time
        
        # Print iteration summary
        if settings.subproblem_log
            iteration_elapsed = time() - callback_start_time
            print_iteration_summary(iteration[], num_subproblems_solved, iter_data.cuts_added_this_iter, iteration_elapsed)
            
            # Print ML training time if ML was used
            if use_ml && iteration_ml_training_time > 0.0
                print_ml_training_line(iteration[], iteration_ml_training_time, num_ml_trained)
            end
        end
        
        # Update adaptive cut limit for next iteration
        if settings.selection_strategy == "adaptive"
            update_cut_limit!(selection_strategy, iter_data, prev_iter_data, false)
        end
        
        # Train proportion predictor after iteration (prediction_based mode)
        train_ml_selection!(selection_strategy, network, subproblem_scores, iter_data, 
                           total_cuts_added, total_ml_selection_time, iteration, settings, outage_scenarios)
        
        # Store current iteration data for next iteration's adaptation
        prev_iter_data = deepcopy(iter_data)
        
        # Track total callback time and record callback end time
        callback_elapsed = time() - callback_start_time
        total_callback_time[] += callback_elapsed
        last_callback_end_time[] = time()
    end
    
    # Register callback and solve
    MOI.set(master, Gurobi.CallbackFunction(), benders_callback)
    
    optimize!(master)
    total_solve_time = solve_time(master)
    
    status = termination_status(master)
    
    # Determine if selection ML is active
    use_selection_ml = (selection_strategy isa AdaptiveCutLimit && selection_strategy.mode == "prediction_based" && 
                        selection_strategy.proportion_predictor !== nothing)
    
    # Print timing and ML metrics summary if statistics enabled
    if settings.statistics
        print_solve_summary(total_solve_time, total_master_time[], total_callback_time[], 
                              total_subproblem_solve_time[], total_ml_training_time[], total_ml_selection_time[],
                              total_dbscan_time[], use_ml, use_selection_ml, ml_model, settings.ml_statistics)
    end
    
    # Display ML selection weights if active (similar to scoring weights)
    if use_selection_ml && selection_strategy.proportion_predictor !== nothing
        print_ml_selection_weights(selection_strategy.proportion_predictor)
    end
    
    if status == INFEASIBLE || !has_values(master)
        # Write oracle data before returning, even on infeasibility or time limit
        if oracle_data !== nothing
            oracle_path = if isempty(settings.oracle_filepath)
                instance_name = splitext(network.meta.filename)[1]
                joinpath(@__DIR__, "..", "..", "check", "oracle", "$(instance_name).csv")
            else
                settings.oracle_filepath
            end
            write_oracle_data(oracle_data, oracle_path)
        end
        
        return (
            objective_value = Inf,
            y_solution = Dict{Tuple{String,Int},Float64}(),
            model = master,
            status = status,
            iterations = iteration[],
            total_cuts_added = total_cuts_added[],
            total_cuts_found = total_cuts_found[],
            total_subproblems_solved = total_subproblems_solved[],
            total_solve_time = total_solve_time,
            total_callback_time = total_callback_time[],
            total_subproblem_solve_time = total_subproblem_solve_time[],
            total_ml_training_time = total_ml_training_time[],
            total_ml_selection_time = total_ml_selection_time[],
            total_dbscan_time = total_dbscan_time[],
            total_master_time = total_master_time[],
            node_count = MOI.get(master, MOI.NodeCount())
        )
    end
    
    # Extract solution
    y_solution = Dict{Tuple{String,Int},Float64}()
    for l in L
        mods = link_modules[l]
        for m in eachindex(mods)
            val = value(y_var[l,m])
            if val > 1e-6
                y_solution[(l,m)] = val
            end
        end
    end
    
    # Export ML model if enabled and model was trained
    if settings.ml_model_write && ml_model !== nothing
        # Check if model has been trained
        has_updates = if isa(ml_model, OnlineLogisticRegression)
            ml_model.n_updates > 0
        else  # MultiRegressorML
            any(r.n_updates > 0 for r in values(ml_model.regressors))
        end
        
        if has_updates
            # Ensure models directory exists
            mkpath(models_dir)
            if isa(ml_model, OnlineLogisticRegression)
                save_ml_model(ml_model, model_path)
            else
                save_multi_regressor_model(ml_model, model_path)
            end
        end
    end
    
    # Write oracle data if in write mode
    if oracle_data !== nothing
        # Set default filepath if not specified: check/oracle/<instance_name>.csv
        oracle_path = if isempty(settings.oracle_filepath)
            instance_name = splitext(network.meta.filename)[1]
            joinpath(@__DIR__, "..", "..", "check", "oracle", "$(instance_name).csv")
        else
            settings.oracle_filepath
        end
        write_oracle_data(oracle_data, oracle_path)
    end
    
    return (
        objective_value = objective_value(master),
        y_solution = y_solution,
        model = master,
        status = status,
        iterations = iteration[],
        total_cuts_added = total_cuts_added[],
        total_cuts_found = total_cuts_found[],
        total_subproblems_solved = total_subproblems_solved[],
        total_solve_time = total_solve_time,
        total_callback_time = total_callback_time[],
        total_subproblem_solve_time = total_subproblem_solve_time[],
        total_ml_training_time = total_ml_training_time[],
        total_ml_selection_time = total_ml_selection_time[],
        total_dbscan_time = total_dbscan_time[],
        total_master_time = total_master_time[],
        node_count = MOI.get(master, MOI.NodeCount())
    )
end
