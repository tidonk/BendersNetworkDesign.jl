"""
Subproblem selection strategies for adaptive Benders decomposition.

Implements stopping criteria and adaptive solving limits to determine
when to stop solving subproblems within an iteration.
"""

using Random

"""
    IterationData

Tracks progress data within the current Benders iteration for adaptive strategies.

# Fields
- `iteration`: Current iteration number
- `ub`: Current upper bound (primal bound)
- `lb`: Current lower bound (dual bound)
- `gap`: Optimality gap (relative or absolute)
- `master_solve_time`: Time spent solving master problem
- `subproblem_solve_time`: Time spent solving subproblems
- `cuts_found_this_iter`: Cuts found in current iteration
- `cuts_added_this_iter`: Cuts added (after cut filtering) in current iteration
- `num_solves_this_iter`: Number of subproblems solved in current iteration
- `consecutive_no_cuts`: Count of consecutive subproblems with no cuts
- `node_count`: Number of opened nodes in MIP tree
- `simplex_iterations`: Total simplex iterations
- `iteration_start_time`: Time when iteration started
- `is_stabilization_round`: Whether this is a stabilization round

# TODO: Collect MIP callback data from Gurobi
Use Gurobi callback codes to track:
- GRB_CB_MIP_NODCNT: Number of nodes explored
- GRB_CB_MIP_ITRCNT: Total simplex iterations
- GRB_CB_MIP_OBJBST: Best objective (primal bound)
- GRB_CB_MIP_OBJBND: Best bound (dual bound)
See: https://docs.gurobi.com/projects/optimizer/en/current/reference/numericcodes/callbacks.html#where-mip
"""
mutable struct IterationData
    iteration::Int
    ub::Float64
    lb::Float64
    gap::Float64
    master_solve_time::Float64
    subproblem_solve_time::Float64
    cuts_found_this_iter::Int
    cuts_added_this_iter::Int
    consecutive_no_cuts::Int
    node_count::Int
    simplex_iterations::Int
    iteration_start_time::Float64
    is_stabilization_round::Bool
    is_initialization_round::Bool
    is_root_node::Bool
    root_node_iteration::Int  # Count of iterations at root node
    num_solves_this_iter::Int  # Number of subproblems solved in this iteration
    
    IterationData() = new(0, Inf, -Inf, Inf, 0.0, 0.0, 0, 0, 0, 0, 0, 0.0, false, false, false, 0, 0)
end

"""
    SelectionStrategy

Abstract type for subproblem selection strategies.
"""
abstract type SelectionStrategy end

"""
    NoneSelection <: SelectionStrategy

No selection strategy - always solve all subproblems.
Useful for baseline comparisons and ensuring completeness.
"""
struct NoneSelection <: SelectionStrategy
end

"""
    StaticCutLimit <: SelectionStrategy

Static subproblem selection with multiple stopping criteria.

# Fields
- `max_cuts`: Maximum cuts to add per iteration (computed from mode and limits)
- `max_solves`: Maximum subproblems to solve per iteration (computed from mode and limits)
- `max_consecutive_misses`: Max consecutive scenarios without cuts (computed from mode and limits)
- `min_score_threshold`: Stop when scenario score falls below this threshold (-1 to disable)
- `iteration_time_limit`: Maximum time (seconds) per iteration (-1 to disable)
"""
struct StaticCutLimit <: SelectionStrategy
    max_cuts::Int
    max_solves::Int
    max_consecutive_misses::Int
    min_score_threshold::Float64
    iteration_time_limit::Float64
    
    StaticCutLimit(max_cuts=-1, max_solves=-1, max_misses=100, min_score=0.1, time_limit=-1.0) = 
        new(max_cuts, max_solves, max_misses, min_score, time_limit)
end

"""
    compute_effective_limit(limit::Limit, num_scenarios::Int) -> Int

Compute effective limit based on mode (absolute or relative).

# Arguments
- `limit`: Limit object with mode, absolute, and relative fields
- `num_scenarios`: Total number of scenarios

# Returns
Effective integer limit. Returns -1 if disabled.

# Examples
```julia
compute_effective_limit(Limit("absolute", 5, 0.1), 100)  # Returns 5
compute_effective_limit(Limit("relative", 5, 0.1), 100)  # Returns 10 (ceil(0.1 * 100))
compute_effective_limit(Limit("absolute", -1, 0.1), 100) # Returns -1 (disabled)
compute_effective_limit(Limit("relative", 5, -1.0), 100) # Returns -1 (disabled)
```
"""
function compute_effective_limit(limit, num_scenarios::Int)::Int
    if limit.mode == "absolute"
        return limit.absolute
    elseif limit.mode == "relative"
        if limit.relative < 0.0
            return -1  # Disabled
        end
        return ceil(Int, limit.relative * num_scenarios)
    else
        @warn "Unknown limit mode: $(limit.mode), using absolute"
        return limit.absolute
    end
end

"""
    create_selection_strategy(settings, num_scenarios::Int, network=nothing) -> SelectionStrategy

Create selection strategy from settings, computing effective limits based on num_scenarios.

# Arguments
- `settings`: Settings object with limit modes and values
- `num_scenarios`: Total number of scenarios (for relative limit computation)
- `network`: Optional SNDlibNetwork for instance-specific oracle filepath (default: nothing)

# Returns
Configured SelectionStrategy instance
"""
function create_selection_strategy(settings, num_scenarios::Int, network=nothing)::SelectionStrategy
    if settings.selection_strategy == "none"
        # No selection - solve all subproblems every iteration
        return NoneSelection()
    elseif settings.selection_strategy == "static"
        # Compute effective limits
        max_cuts = compute_effective_limit(settings.cut_limit, num_scenarios)
        max_solves = compute_effective_limit(settings.solve_limit, num_scenarios)
        max_misses = compute_effective_limit(settings.consecutive_miss, num_scenarios)
        
        return StaticCutLimit(
            max_cuts,
            max_solves,
            max_misses,
            settings.min_score_threshold,
            settings.iteration_time_limit
        )
    elseif settings.selection_strategy == "adaptive"
        # Get adaptive parameters from settings
        if hasfield(typeof(settings), :adaptive_mode)
            mode = settings.adaptive_mode
            
            if mode == "prediction_based"
                # Import ProportionPredictor (done at module level)
                # Features: 8 total (4 score stats + 4 utilization stats)
                predictor = ProportionPredictor(8,
                    learning_rate=settings.adaptive_prediction_learning_rate,
                    regularization=settings.adaptive_prediction_regularization,
                    history_decay=settings.adaptive_prediction_history_decay,
                    min_training_sample_rate=settings.adaptive_prediction_min_training_rate
                )
                
                return AdaptiveCutLimit(
                    mode=mode,
                    min_score=settings.min_score_threshold,
                    time_limit=settings.iteration_time_limit,
                    predictor=predictor,
                    default_prop=settings.adaptive_prediction_default_proportion,
                    min_prop=settings.adaptive_prediction_min_proportion,
                    max_prop=settings.adaptive_prediction_max_proportion
                )
            elseif mode == "phase_based"
                return AdaptiveCutLimit(
                    mode=mode,
                    min_score=settings.min_score_threshold,
                    time_limit=settings.iteration_time_limit,
                    large_gap=settings.adaptive_phase_large_gap,
                    medium_gap=settings.adaptive_phase_medium_gap,
                    early_cuts=min(settings.adaptive_phase_early_cuts, num_scenarios),
                    middle_cuts=min(settings.adaptive_phase_middle_cuts, num_scenarios),
                    late_cuts=min(settings.adaptive_phase_late_cuts, num_scenarios)
                )
            elseif mode == "progress_based"
                return AdaptiveCutLimit(
                    mode=mode,
                    min_score=settings.min_score_threshold,
                    time_limit=settings.iteration_time_limit,
                    base=min(settings.adaptive_progress_base_cuts, num_scenarios),
                    min_cuts=settings.adaptive_progress_min_cuts,
                    max_cuts=min(settings.adaptive_progress_max_cuts, num_scenarios),
                    factor=settings.adaptive_progress_factor,
                    low_imp=settings.adaptive_progress_low_threshold,
                    high_imp=settings.adaptive_progress_high_threshold,
                    stag_rounds=settings.adaptive_progress_stagnation_rounds,
                    movement_factor=settings.adaptive_progress_movement_factor,
                    stagnation_factor=settings.adaptive_progress_stagnation_factor
                )
            elseif mode == "time_balance"
                return AdaptiveCutLimit(
                    mode=mode,
                    min_score=settings.min_score_threshold,
                    time_limit=settings.iteration_time_limit,
                    base=min(settings.adaptive_time_base_cuts, num_scenarios),
                    min_cuts=settings.adaptive_time_min_cuts,
                    max_cuts=min(settings.adaptive_time_max_cuts, num_scenarios),
                    master_dom=settings.adaptive_time_master_threshold,
                    subproblem_dom=settings.adaptive_time_subproblem_threshold,
                    dec_factor=settings.adaptive_time_decrease_factor,
                    inc_factor=settings.adaptive_time_increase_factor
                )
            else
                @warn "Unknown adaptive mode: $mode, using default phase_based"
                return AdaptiveCutLimit()
            end
        else
            # Use defaults if adaptive fields not present
            @warn "Adaptive settings not found, using default adaptive parameters"
            return AdaptiveCutLimit()
        end
    elseif settings.selection_strategy == "oracle"
        # Oracle strategy: read pre-recorded data
        if settings.oracle_mode == "read"
            # Compute oracle filepath: use instance-specific default if empty
            oracle_path = if isempty(settings.oracle_filepath)
                if network !== nothing
                    instance_name = splitext(network.meta.filename)[1]
                    joinpath(@__DIR__, "..", "..", "check", "oracle", "$(instance_name).csv")
                else
                    throw(OracleError("Oracle read mode requires either oracle_filepath in settings or network parameter"))
                end
            else
                # If relative path, resolve relative to project root
                path = settings.oracle_filepath
                if !isabspath(path)
                    path = joinpath(@__DIR__, "..", "..", path)
                end
                abspath(path)
            end
            oracle_data = read_oracle_data(oracle_path)
            return OracleSelection(oracle_data)
        else
            # In "write" mode, use NoneSelection to solve all scenarios
            # Oracle recording happens in benders.jl
            return NoneSelection()
        end
    else
        @warn "Unknown selection strategy: $(settings.selection_strategy), using static"
        return StaticCutLimit()
    end
end

"""
    AdaptiveCutLimit <: SelectionStrategy

Adaptive cut limit based on solution progress.

Uses one of four adaptation modes (only one active):
1. **phase_based**: Adjust based on optimality gap thresholds
2. **progress_based**: Adjust based on gap improvement rate  
3. **time_balance**: Adjust based on master vs subproblem time ratio
4. **prediction_based**: Use ML to predict proportion of subproblems that will yield cuts

# Fields
- `mode`: Adaptation mode ("phase_based", "progress_based", "time_balance")
- `current_cuts`: Current adaptive limit (mutable)
- `min_score_threshold`: Stop when scenario score falls below threshold
- `iteration_time_limit`: Maximum time per iteration

## Phase-based fields
- `large_gap_threshold`, `medium_gap_threshold`: Gap thresholds for phases
- `early_phase_cuts`, `middle_phase_cuts`, `late_phase_cuts`: Cuts per phase

## Progress-based fields
- `base_cuts`, `min_cuts`, `max_cuts`: Cut limits
- `adaptation_factor`: Multiplicative adjustment factor
- `low_improvement_threshold`, `high_improvement_threshold`: Gap improvement thresholds
- `stagnation_rounds`: Consecutive low improvement rounds before increasing
- `consecutive_low_improvement`: Counter for stagnation detection

## Time-balance fields
- `base_cuts`, `min_cuts`, `max_cuts`: Cut limits
- `master_dominated_threshold`, `subproblem_dominated_threshold`: Time ratio thresholds
- `decrease_factor`, `increase_factor`: Adjustment multipliers
"""
mutable struct AdaptiveCutLimit <: SelectionStrategy
    mode::String
    current_cuts::Int
    min_score_threshold::Float64
    iteration_time_limit::Float64
    
    # Phase-based parameters
    large_gap_threshold::Float64
    medium_gap_threshold::Float64
    early_phase_cuts::Int
    middle_phase_cuts::Int
    late_phase_cuts::Int
    
    # Progress-based parameters
    base_cuts::Int
    min_cuts::Int
    max_cuts::Int
    adaptation_factor::Float64
    low_improvement_threshold::Float64
    high_improvement_threshold::Float64
    stagnation_rounds::Int
    consecutive_low_improvement::Int
    movement_factor::Float64
    stagnation_factor::Float64
    fractional_cuts::Float64  # Track fractional cut limit for stagnation accumulation
    
    # Time-balance parameters
    master_dominated_threshold::Float64
    subproblem_dominated_threshold::Float64
    decrease_factor::Float64
    increase_factor::Float64
    
    # Prediction-based parameters
    proportion_predictor::Union{Nothing,Any}  # ProportionPredictor (avoid circular dependency)
    default_proportion::Float64  # Default proportion when no prediction available (0.0-1.0)
    min_proportion::Float64  # Minimum proportion of subproblems to solve (0.0-1.0)
    max_proportion::Float64  # Maximum proportion of subproblems to solve (0.0-1.0)
    
    function AdaptiveCutLimit(;
        mode="phase_based",
        min_score=-1.0,
        time_limit=-1.0,
        # Phase-based
        large_gap=0.20, medium_gap=0.05,
        early_cuts=1, middle_cuts=5, late_cuts=50,
        # Progress-based
        base=5, min_cuts=1, max_cuts=50, factor=1.5,
        low_imp=0.01, high_imp=0.10, stag_rounds=3,
        movement_factor=0.5, stagnation_factor=1.05,
        # Time-balance
        master_dom=2.0, subproblem_dom=0.5,
        dec_factor=0.8, inc_factor=1.2,
        # Prediction-based
        predictor=nothing, default_prop=0.5, min_prop=0.05, max_prop=1.0)
        
        # Initial cut limit based on mode
        initial_cuts = if mode == "phase_based"
            middle_cuts
        elseif mode == "prediction_based"
            # Start with default_prop until first prediction
            max(1, round(Int, default_prop * 100))  # Assume ~100 scenarios as placeholder
        else
            base
        end
        
        new(mode, initial_cuts, min_score, time_limit,
            # Phase-based
            large_gap, medium_gap, early_cuts, middle_cuts, late_cuts,
            # Progress-based
            base, min_cuts, max_cuts, factor, low_imp, high_imp, stag_rounds, 0,
            movement_factor, stagnation_factor, Float64(initial_cuts),
            # Time-balance
            master_dom, subproblem_dom, dec_factor, inc_factor,
            # Prediction-based
            predictor, default_prop, min_prop, max_prop)
    end
end

"""
    should_stop_solving(strategy, iter_data, current_score) -> Bool

Determine if subproblem solving should stop based on strategy and current state.

# Stopping criteria for StaticCutLimit
1. Cut limit reached (if max_cuts > 0)
2. Consecutive misses (if max_consecutive_misses > 0)
3. Low score threshold (if min_score_threshold > 0 and current_score < threshold)
4. Iteration time limit (if iteration_time_limit > 0)
5. Stabilization rounds: never stop (solve all scenarios)
6. Root node (if within root_node_stabilization limit): never stop (solve all scenarios)
"""
function should_stop_solving(strategy::StaticCutLimit, iter_data::IterationData, current_score::Float64=1.0, root_node_stabilization::Int=0)::Bool
    # Initialization, stabilization, and root node stabilization: never stop, solve all scenarios
    # Root node: check if within iteration limit (0=disabled, -1=unlimited, N>0=first N iterations)
    if iter_data.is_initialization_round || iter_data.is_stabilization_round || 
       (iter_data.is_root_node && root_node_stabilization != 0 && 
        (root_node_stabilization < 0 || iter_data.root_node_iteration < root_node_stabilization))
        return false
    end
    
    # Cut limit criterion
    if strategy.max_cuts > 0 && iter_data.cuts_found_this_iter >= strategy.max_cuts
        #println("Stopping because of cut limit reached")
        return true
    end
    
    # Solve limit criterion (number of subproblems solved)
    if strategy.max_solves > 0 && iter_data.num_solves_this_iter >= strategy.max_solves
        #println("Stopping because of solve limit reached: num_solves_this_iter = $(iter_data.num_solves_this_iter) >= $(strategy.max_solves) = max_solves")
        return true
    end
    
    # Consecutive miss criterion
    if strategy.max_consecutive_misses > 0 && iter_data.consecutive_no_cuts >= strategy.max_consecutive_misses
        #println("Stopping because of consecutive misses")
        return true
    end
    
    # Low score threshold criterion
    if strategy.min_score_threshold > 0.0 && current_score < strategy.min_score_threshold
        #println("Stopping because of low score threshold")
        return true
    end
    
    # Iteration time limit criterion
    if strategy.iteration_time_limit > 0.0
        elapsed = time() - iter_data.iteration_start_time
        if elapsed >= strategy.iteration_time_limit
            return true
        end
    end
    
    return false
end

"""
    should_stop_solving(strategy::NoneSelection, iter_data, current_score) -> Bool

No selection - always returns false to solve all subproblems.
"""
function should_stop_solving(strategy::NoneSelection, iter_data::IterationData, current_score::Float64=1.0, root_node_stabilization::Int=0)::Bool
    return false  # Never stop, always solve all subproblems
end

"""    should_stop_solving(strategy::AdaptiveCutLimit, iter_data, current_score) -> Bool

Adaptive stopping criteria based on current cut limit and other thresholds.
"""
function should_stop_solving(strategy::AdaptiveCutLimit, iter_data::IterationData, current_score::Float64=1.0, root_node_stabilization::Int=0)::Bool
    # Initialization, stabilization, and root node stabilization: never stop, solve all scenarios
    # Root node: check if within iteration limit (0=disabled, -1=unlimited, N>0=first N iterations)
    if iter_data.is_initialization_round || iter_data.is_stabilization_round || 
       (iter_data.is_root_node && root_node_stabilization != 0 && 
        (root_node_stabilization < 0 || iter_data.root_node_iteration < root_node_stabilization))
        return false
    end
    
    # Adaptive cut limit criterion
    # For prediction_based mode, current_cuts is number of scenarios to solve (not cuts to find)
    # For other modes, current_cuts is number of cuts to find
    if strategy.mode == "prediction_based"
        if strategy.current_cuts > 0 && iter_data.num_solves_this_iter >= strategy.current_cuts
            return true
        end
    else
        if strategy.current_cuts > 0 && iter_data.cuts_found_this_iter >= strategy.current_cuts
            return true
        end
    end
    
    # Low score threshold criterion
    if strategy.min_score_threshold > 0.0 && current_score < strategy.min_score_threshold
        return true
    end
    
    # Iteration time limit criterion
    if strategy.iteration_time_limit > 0.0
        elapsed = time() - iter_data.iteration_start_time
        if elapsed >= strategy.iteration_time_limit
            return true
        end
    end
    
    return false
end

"""
    is_stabilization_round(iteration::Int, stabilization_frequency::Int) -> Bool

Check if current iteration is a stabilization round.

Stabilization rounds occur every N iterations (where N = stabilization_frequency).
In stabilization rounds, all stopping criteria are disabled and all scenarios
are examined to ensure no constraint is neglected.

Returns false if stabilization_frequency <= 0 (disabled).
"""
function is_stabilization_round(iteration::Int, stabilization_frequency::Int)::Bool
    if stabilization_frequency <= 0
        return false
    end
    return iteration % stabilization_frequency == 0
end

"""
    update_cut_limit!(strategy, iter_data, prev_iter_data) -> Int

Update adaptive cut limit based on progress between iterations.

Returns the new cut limit for the next iteration.
"""
function update_cut_limit!(strategy::StaticCutLimit, iter_data::IterationData, prev_iter_data::Union{IterationData,Nothing})::Int
    return strategy.max_cuts  # Static strategy never changes
end

"""
    update_cut_limit!(strategy::AdaptiveCutLimit, iter_data, prev_iter_data) -> Int

Update adaptive cut limit based on the selected mode.
Only one adaptation mechanism is active at a time.
"""
function update_cut_limit!(strategy::AdaptiveCutLimit, iter_data::IterationData, prev_iter_data::Union{IterationData,Nothing}, verbose::Bool=false)::Int
    old_limit = strategy.current_cuts
    new_limit = old_limit
    
    if strategy.mode == "phase_based"
        # Phase-based adaptation (gap thresholds)
        new_limit = if iter_data.gap > strategy.large_gap_threshold
            # Early phase: large gap - explore quickly with few cuts
            strategy.early_phase_cuts
        elseif iter_data.gap > strategy.medium_gap_threshold
            # Middle phase: moderate gap - balanced exploration
            strategy.middle_phase_cuts
        else
            # Late phase: small gap - intensive refinement
            strategy.late_phase_cuts
        end
        
    elseif strategy.mode == "progress_based"
        # Progress-based adaptation (dual bound improvement)
        new_limit = old_limit  # Start from current limit
        
        if prev_iter_data !== nothing && prev_iter_data.lb > -Inf && iter_data.lb > -Inf
            # Check if dual bound improved (use relative threshold for numerical stability)
            lb_improvement = iter_data.lb - prev_iter_data.lb
            lb_threshold = max(1e-6, abs(prev_iter_data.lb) * 1e-9)
            
            if lb_improvement > lb_threshold
                # Dual bound increased: apply movement factor (decrease cuts)
                strategy.fractional_cuts = strategy.fractional_cuts * strategy.movement_factor
                new_limit = max(Int(floor(strategy.fractional_cuts)), strategy.min_cuts)
                strategy.consecutive_low_improvement = 0
            else
                # Dual bound stalled: count stagnation
                strategy.consecutive_low_improvement += 1
                if strategy.consecutive_low_improvement >= strategy.stagnation_rounds
                    # Apply stagnation factor (increase cuts slightly) - accumulates fractionally
                    strategy.fractional_cuts = min(strategy.fractional_cuts * strategy.stagnation_factor, strategy.max_cuts)
                    new_limit = min(Int(ceil(strategy.fractional_cuts)), strategy.max_cuts)
                    strategy.consecutive_low_improvement = 0
                else
                    # Keep current limit until stagnation threshold reached
                    new_limit = old_limit
                end
            end
        end
        
    elseif strategy.mode == "time_balance"
        # Time-balance adaptation (master vs subproblem ratio)
        new_limit = old_limit  # Start from current
        
        if iter_data.master_solve_time > 0 && iter_data.subproblem_solve_time > 0
            time_ratio = iter_data.master_solve_time / iter_data.subproblem_solve_time
            
            if time_ratio > strategy.master_dominated_threshold
                # Master is bottleneck: decrease cuts
                new_limit = max(Int(ceil(old_limit * strategy.decrease_factor)), strategy.min_cuts)
            elseif time_ratio < strategy.subproblem_dominated_threshold
                # Subproblems are bottleneck: increase cuts
                new_limit = min(Int(ceil(old_limit * strategy.increase_factor)), strategy.max_cuts)
            end
        end
    elseif strategy.mode == "prediction_based"
        # Prediction-based adaptation: ML predicts proportion of subproblems that will yield cuts
        # Note: This mode does NOT update limits here - the limit is set dynamically 
        # before each iteration based on ML prediction. This function just returns current limit.
        # The actual prediction happens in the Benders callback before scenario solving.
        new_limit = strategy.current_cuts
    end
    
    # Enforce minimum cut limit across all non-prediction modes
    if strategy.mode != "prediction_based"
        new_limit = max(new_limit, strategy.min_cuts)
    end
    
    # Update strategy state
    strategy.current_cuts = new_limit
    
    # Print update information
    if verbose
        if new_limit != old_limit
            println("  [Iter $(iter_data.iteration)] Adaptive cut limit updated: $old_limit → $new_limit (gap: $(round(iter_data.gap*100, digits=2))%, mode: $(strategy.mode))")
        else
            println("  [Iter $(iter_data.iteration)] Adaptive cut limit: $new_limit (gap: $(round(iter_data.gap*100, digits=2))%, mode: $(strategy.mode))")
        end
    elseif new_limit != old_limit
        # Non-verbose mode: only print if changed
        println("  [Iter $(iter_data.iteration)] Adaptive cut limit updated: $old_limit → $new_limit (mode: $(strategy.mode))")
    end
    
    return strategy.current_cuts
end

"""
    order_scenarios(scenarios, scores, ordering::String, random_seed) -> Vector

Order scenarios for solving based on strategy.

# Arguments
- `scenarios`: Vector of OutageScenario
- `scores`: Dict{Int,SubproblemScore} mapping scenario id to score
- `ordering`: Strategy string ("score", "random", "none")
- `random_seed`: Random seed for "random" ordering (nothing for non-deterministic)

# Returns
Ordered vector of scenarios to solve

# TODO: Implement additional ordering strategies
- "violation": Order by historical violation magnitude
- "reliability": Order by cut success rate
- "hybrid": Combine multiple criteria with configurable weights
"""
function order_scenarios(scenarios::Vector, scores::Dict{Int,SubproblemScore}, ordering::String, 
                        random_seed::Union{Int,Nothing}=nothing)
    if ordering == "score" && !isempty(scores)
        # Score-based: sort by descending score
        return sort(scenarios, by=s -> -get(scores, s.id, SubproblemScore()).scaled_score)
    elseif ordering == "random"
        # Random: shuffle with optional seed
        if random_seed !== nothing
            Random.seed!(random_seed)
        end
        return shuffle(copy(scenarios))
    else
        # None: use original order
        return scenarios
    end
end

"""
    collect_callback_data(cb_data, model) -> IterationData

Extract current MIP state from Gurobi callback for adaptive strategies.

# TODO: Implement Gurobi callback data extraction
Query the following attributes during callback:
- GRB_CB_MIP_OBJBST: Best integer objective (upper bound)
- GRB_CB_MIP_OBJBND: Best objective bound (lower bound)
- GRB_CB_MIP_NODCNT: Number of explored nodes
- GRB_CB_MIP_ITRCNT: Total simplex iterations
- Compute gap: (ub - lb) / max(|ub|, 1.0)

This data enables sophisticated adaptive strategies based on MIP solver state.
"""
function collect_callback_data(cb_data, model)::IterationData
    iter_data = IterationData()
    
    # TODO: Extract MIP state from callback
    # Try to query Gurobi-specific attributes
    # Falls back gracefully if not using Gurobi
    
    return iter_data
end
