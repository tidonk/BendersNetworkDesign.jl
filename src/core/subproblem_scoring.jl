"""
Subproblem scoring mechanisms for adaptive Benders decomposition.

Implements multi-criteria scoring to prioritize which subproblems to solve.
"""

using Statistics

"""
    SubproblemScore

Tracks scoring components for each subproblem to guide solving order.

Score components:
- violation: average violation when cut was added
- reliability: fraction of times subproblem generated a cut (before filtering)
- reliability_filtered: fraction of times subproblem produced a cut that passed filtering
- total_cut_share: fraction of all cuts produced by this subproblem
- stabilization: rounds since last solved
- ml_prediction: ML-predicted probability that subproblem will yield a cut
"""
mutable struct SubproblemScore
    # History tracking (cumulative)
    times_solved::Int
    times_cut_generated::Int   # Cuts generated (before filtering)
    times_cut_added::Int       # Cuts added (after filtering)
    total_violations::Float64
    total_cuts_produced::Int
    rounds_since_solved::Int
    total_solve_time::Float64  # Cumulative solve time in seconds
    
    # Exponentially weighted statistics (for depreciation)
    weighted_times_solved::Float64
    weighted_times_cut_generated::Float64
    weighted_times_cut_added::Float64
    weighted_total_violations::Float64
    weighted_total_cuts_produced::Float64
    
    # Score components (cached)
    r_violation::Float64              # r_v: average violation
    r_reliability::Float64            # r_r: cut generation rate (before filtering)
    r_reliability_filtered::Float64   # r_rf: cut success rate (after filtering)
    r_total_share::Float64            # r_t: share of all cuts
    r_stabilization::Float64          # r_z: staleness penalty
    r_ml_prediction::Float64          # r_ml: ML-predicted probability of infeasibility
    
    # Final scaled score
    scaled_score::Float64
    
    SubproblemScore() = new(0, 0, 0, 0.0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
end

"""
    update_subproblem_score!(score::SubproblemScore, cut_generated::Bool, cut_added::Bool, violation::Float64, total_cuts_all::Int, solve_time::Float64=0.0)

Update score components after solving a subproblem.

# Arguments
- `score`: SubproblemScore to update
- `cut_generated`: Whether a cut was generated (before filtering)
- `cut_added`: Whether a cut was added (after filtering)
- `violation`: Violation amount (if cut was added)
- `total_cuts_all`: Total cuts across all subproblems (for share calculation)
- `solve_time`: Time taken to solve this subproblem (seconds)
"""
function update_subproblem_score!(score::SubproblemScore, 
                                  cut_generated::Bool, 
                                  cut_added::Bool, 
                                  violation::Float64, 
                                  total_cuts_all::Int,
                                  solve_time::Float64=0.0)::Nothing
    # Update cumulative counters
    score.times_solved += 1
    score.rounds_since_solved = 0  # Reset staleness
    score.total_solve_time += solve_time
    
    # Update weighted statistics (recent events get full weight)
    score.weighted_times_solved += 1.0
    
    if cut_generated
        score.times_cut_generated += 1
        score.weighted_times_cut_generated += 1.0
    end
    
    if cut_added
        score.times_cut_added += 1
        score.total_violations += violation
        score.total_cuts_produced += 1
        score.weighted_total_violations += violation
        score.weighted_total_cuts_produced += 1.0
    end
    
    # Update score components (use cumulative statistics; weighted statistics are for ML only)
    # r_v: average violation
    score.r_violation = score.times_cut_added > 0 ? score.total_violations / score.times_cut_added : 0.0
    
    # r_r: reliability (cut generation rate, before filtering)
    score.r_reliability = score.times_solved > 0 ? score.times_cut_generated / score.times_solved : 0.0
    
    # r_rf: filtered reliability (cut success rate, after filtering)
    score.r_reliability_filtered = score.times_solved > 0 ? score.times_cut_added / score.times_solved : 0.0
    
    # r_t: total cut share
    score.r_total_share = total_cuts_all > 0 ? score.total_cuts_produced / total_cuts_all : 0.0
    
    # r_z: stabilization (staleness) - will be updated when NOT solved
    score.r_stabilization = Float64(score.rounds_since_solved)
    
    return nothing
end

"""
    increment_staleness!(scores::Dict{Int,SubproblemScore}; decay_factor::Float64=0.9)

Increment staleness counter for all subproblems (called at start of each iteration).

Applies exponential decay to weighted statistics so that historical events
gradually lose influence. With decay_factor=0.9, after 10 rounds the weight
is ~0.35, and after 22 rounds it's ~0.1.

# Arguments
- `scores`: Dictionary of subproblem scores
- `decay_factor`: Exponential decay factor in (0, 1), default 0.9
"""
function increment_staleness!(scores::Dict{Int,SubproblemScore}; decay_factor::Float64=0.9)::Nothing
    @assert 0.0 < decay_factor < 1.0 "Decay factor must be in (0, 1), got $decay_factor"
    
    for score in values(scores)
        score.rounds_since_solved += 1
        score.r_stabilization = Float64(score.rounds_since_solved)
        
        # Apply exponential decay to weighted statistics
        score.weighted_times_solved *= decay_factor
        score.weighted_times_cut_generated *= decay_factor
        score.weighted_times_cut_added *= decay_factor
        score.weighted_total_violations *= decay_factor
        score.weighted_total_cuts_produced *= decay_factor
    end
    return nothing
end

"""
    compute_scaled_scores!(scores::Dict{Int,SubproblemScore}; weights::Vector{Float64}, scale::Bool=true)

Compute raw and scaled scores for all subproblems.

Default weights: [w_v, w_r, w_rf, w_t, w_z, w_ml]
- w_v: violation weight
- w_r: reliability weight (before filtering)
- w_rf: filtered reliability weight (after filtering)
- w_t: total share weight
- w_z: stabilization weight
- w_ml: ML prediction weight

# TODO: Implement adaptive weight tuning
Learning-based approaches to tune weights during solution process based on:
- Instance characteristics (network size, density, demand patterns)
- Solution phase (early iterations vs late iterations)
- Recent performance metrics (gap improvement, cut quality)

# Arguments
- `scores`: Dictionary of scenario scores (modified in-place)
- `weights`: Weight vector with exactly 6 components:
  - [1] violation: Recent constraint violation
  - [2] reliability: Frequency of cuts from this subproblem
  - [3] reliability_filtered: Filtered reliability (discounting old iterations)
  - [4] total_share: Importance of this scenario in overall network
  - [5] stabilization: Similarity to current master solution
  - [6] ml_prediction: ML model prediction of infeasibility
- `scale`: If true, apply min-max scaling to scale scores to [0,1]

# TODO: Implement phase-dependent scoring
Different score components may matter more in different phases:
- Early phase: emphasize reliability and staleness to explore
- Middle phase: balance violation and total share
- Late phase: focus on violation to finish convergence
"""
function compute_scaled_scores!(scores::Dict{Int,SubproblemScore}; 
                               weights::Vector{Float64}=[0.05, 0.0, 0.8, 0.05, 0.1, 0.0],
                               scale::Bool=true)::Nothing
    # Validate weight vector length
    @assert length(weights) == 6 "Weight vector must have exactly 6 components: [violation, reliability, reliability_filtered, total_share, stabilization, ml_prediction]. Got $(length(weights)) components."
    
    # Extract weights (6 components)
    w_v = weights[1]   # Violation
    w_r = weights[2]   # Reliability
    w_rf = weights[3]  # Reliability filtered
    w_t = weights[4]   # Total share
    w_z = weights[5]   # Stabilization
    w_ml = weights[6]  # ML prediction
    
    # Compute raw scores
    raw_scores = Dict{Int,Float64}()
    for (id, score) in scores
        raw_scores[id] = w_v * score.r_violation + 
                        w_r * score.r_reliability + 
                        w_rf * score.r_reliability_filtered +
                        w_t * score.r_total_share + 
                        w_z * score.r_stabilization +
                        w_ml * score.r_ml_prediction
    end
    
    # Apply min-max scaling if enabled
    if scale && !isempty(raw_scores)
        # When using ML-only scoring (w_ml > 0 and all other weights are 0),
        # exclude scenarios with r_ml_prediction = 0.0 from min/max calculation
        # since these are typically scenarios without failures that weren't predicted
        ml_only = (w_ml > 0.0) && (w_v == 0.0) && (w_r == 0.0) && (w_rf == 0.0) && (w_t == 0.0) && (w_z == 0.0)
        
        scores_for_scaling = if ml_only
            # Filter out scenarios with ML prediction = 0.0
            [rs for (id, rs) in raw_scores if get(scores, id, SubproblemScore()).r_ml_prediction > 1e-10]
        else
            collect(values(raw_scores))
        end
        
        if !isempty(scores_for_scaling) && (maximum(scores_for_scaling) - minimum(scores_for_scaling) > 1e-10)
            # Scale to [0, 1] range using min-max scaling
            min_score = minimum(scores_for_scaling)
            max_score = maximum(scores_for_scaling)
            
            for (id, score) in scores
                score.scaled_score = (raw_scores[id] - min_score) / (max_score - min_score)
            end
        else
            # All scores equal - assign uniform score
            for score in values(scores)
                score.scaled_score = 0.5
            end
        end
    else
        # No scaling - use raw scores directly
        for (id, score) in scores
            score.scaled_score = raw_scores[id]
        end
    end
    
    return nothing
end

"""
    reset_all_scores!(scores::Dict{Int,SubproblemScore})

Reset all subproblem scores to initial state.

Used during stabilization rounds to ensure fresh scoring in next phase.
All history and score components are cleared.
"""
function reset_all_scores!(scores::Dict{Int,SubproblemScore})::Nothing
    for score in values(scores)
        score.times_solved = 0
        score.times_cut_generated = 0
        score.times_cut_added = 0
        score.total_violations = 0.0
        score.total_cuts_produced = 0
        score.rounds_since_solved = 0
        # Note: weighted_* fields are NOT reset - they persist for ML model use
        score.r_violation = 0.0
        score.r_reliability = 0.0
        score.r_reliability_filtered = 0.0
        score.r_total_share = 0.0
        score.r_stabilization = 0.0
        score.r_ml_prediction = 0.0
        score.scaled_score = 0.0
    end
    return nothing
end
