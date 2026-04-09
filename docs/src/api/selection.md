# Subproblem Selection API

## Scoring System

```@docs
SubproblemScore
update_subproblem_score!
compute_scaled_scores!
increment_staleness!
reset_all_scores!
```

## Scenario Ordering

```@docs
order_scenarios
```

### Ordering Strategies

The `ordering` parameter accepts three values:

- **`"none"`**: Original scenario order (ID-ascending)
- **`"score"`**: Descending by scaled score (highest priority first)
- **`"random"`**: Random permutation with seed

## Stopping Criteria

```@docs
should_stop_solving
```

### Consecutive Miss Limit

Stops when consecutive subproblems fail to produce cuts.

**Absolute mode**: Stop after fixed number of consecutive misses
```julia
Limit(mode="absolute", absolute=5, relative=0.0)
```

**Relative mode**: Stop after percentage of total scenarios
```julia
Limit(mode="relative", absolute=0, relative=0.2)  # 20% of scenarios
```

### Score Threshold

Stops when scenario score drops below threshold:
```julia
ScoreThreshold(enabled=true, threshold=0.1)
```

### Iteration Time Limit

Stops after time budget per iteration:
```julia
IterationTimeLimit(enabled=true, time_seconds=60.0)
```

## Adaptive Cut Limits

```@docs
AdaptiveCutLimit
```

### Adaptation Mechanisms

#### Phase-Based

Higher limits early in solving, lower limits later:

```julia
adaptive = AdaptiveCutLimit(
    initial_cuts = 10,
    min_cuts = 3,
    max_cuts = 20,
    phase_early_iterations = 10,
    phase_early_multiplier = 1.5,
    phase_late_iterations = 50,
    phase_late_multiplier = 0.5,
    ...
)
```

#### Progress-Based

Reduces limit when objective improvement stalls:

```julia
adaptive = AdaptiveCutLimit(
    progress_enabled = true,
    progress_stall_threshold = 0.01,  # 1% improvement threshold
    progress_stall_penalty = 0.8,     # Reduce by 20% on stall
    ...
)
```

#### Time-Balanced

Adjusts based on subproblem vs total time ratio:

```julia
adaptive = AdaptiveCutLimit(
    time_enabled = true,
    time_target_ratio = 0.3,      # Target 30% time in subproblems
    time_adjustment_rate = 0.1,   # Adjust by 10% per iteration
    ...
)
```

## Selection Strategy

```@docs
SelectionStrategy
create_selection_strategy
```

## Iteration Data

```@docs
IterationData
```

The `IterationData` struct tracks state during iteration:

- `iteration`: Current iteration number
- `cuts_added_this_iter`: Cuts found so far this iteration
- `consecutive_no_cuts`: Consecutive subproblems without cuts
- `iteration_start_time`: Timestamp when iteration started
- `is_stabilization_round`: Whether this is a stabilization round

## Stabilization

```@docs
is_stabilization_round
```

Stabilization rounds occur every `N` iterations (configurable):

- Solves **all** scenarios regardless of scores
- Resets all scores to initial state
- Prevents over-specialization
- Ensures robustness

Example:
```julia
# Check if iteration 200 is stabilization round with frequency=200
if is_stabilization_round(200, 200)
    reset_all_scores!(subproblem_scores)
    # Solve all scenarios...
end
```

## Example: Custom Scoring

```julia
using BendersNetworkDesign

# Initialize scores
scores = Dict{Int,SubproblemScore}()
for scenario in scenarios
    scores[scenario.id] = SubproblemScore()
end

# Simulate solving scenarios
for scenario in scenarios
    # ... solve subproblem ...
    
    if infeasible
        violation = compute_violation(...)
        update_subproblem_score!(scores[scenario.id], true, violation, total_cuts)
    else
        update_subproblem_score!(scores[scenario.id], false, 0.0, total_cuts)
    end
end

# Compute scaled scores
compute_scaled_scores!(scores; weights=[0.3, 0.3, 0.3, 0.1])

# Order by priority
ordered = order_scenarios(scenarios, scores, "score", 42)

# Check top priority
top_scenario = ordered[1]
println("Top score: $(scores[top_scenario.id].scaled_score)")
```
