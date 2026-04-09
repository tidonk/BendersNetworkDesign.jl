# Machine Learning for Subproblem Selection

BendersNetworkDesign.jl includes an optional ML-based component for predicting subproblem infeasibility. This helps prioritize scenarios most likely to yield Benders cuts.

## Overview

The ML model uses online logistic regression to predict the probability that a scenario will generate a cut. Key features:

- **9 deterministic input features** (as of v0.7.1) capturing network topology and traffic patterns
- **Online learning** that adapts during the solve
- **Feature normalization** using z-scores to prevent sigmoid saturation
- **Low overhead** training that doesn't slow down the solver
- **Fully reproducible** results given the same random seed

### v0.7.1: Nondeterminism Bugfix

**Previous versions (≤0.7.0)** included 14 features, some of which caused nondeterministic behavior:
- ❌ Average solve time (hardware/timing-dependent)
- ❌ Iteration number (not intrinsic to solution state)
- ❌ Gap magnitude (solver-dependent bounds)
- ❌ Cumulative cuts added (history-dependent)

**Current version (≥0.7.1)** uses only 9 deterministic features:
- ✓ 4 failed link features (capacity, flows, utilization)
- ✓ 5 weighted score statistics (times solved, cuts generated/added, violations, cuts produced)
- ✓ Fully reproducible given same random seed and instance

## Enabling ML Scoring

Set the ML prediction weight to non-zero in your configuration:

```toml
[BENDERS.SUBPROBLEM_SCORING]
weights = [0.05, 0.0, 0.8, 0.05, 0.1, 0.05]  # Last weight is ML prediction
#          ^viol ^rel  ^filt ^share ^stale ^ML
```

When the ML weight is 0.0, ML prediction is disabled entirely (no model initialization or training).

## Feature Engineering

### Graph-Based N-Hop Neighborhoods

The model uses **topology-aware neighborhood features** rather than global or demand-based statistics:

**N-Hop Neighborhood Definition:**
1. Build link adjacency graph (links are adjacent if they share a node)
2. Use BFS to find all links within n hops (default: 2) of the failed link
3. Compute statistics using ALL demands' traffic on neighborhood links

**Benefits:**
- **Topology-aware**: Neighborhood size varies by link position (central vs peripheral)
- **Traffic-aware**: Captures actual utilization from all demands
- **Scenario-specific**: Each failure location has different context

**Example:**
```
Network:
  N1---[L1]---N2---[L2]---N3
   |           |           |
  [L5]        [L3]        [L4]
   |           |           |
  N5---[L6]---N4---[L7]---N6

When L2 (N2_N3) fails:
  2-hop neighbors: {L1, L3, L4, L5, L6, L7} (6 links)

When L5 (N1_N5) fails (peripheral):
  2-hop neighbors: {L1, L2, L3, L6, L7} (5 links)

✓ Central links have larger neighborhoods
✓ All demands contribute to neighborhood statistics
```

### Complete Feature List (9 deterministic features)

**Failed Link Characteristics (4 features):**
1. Installed capacity (from master solution y-values)
2. Forward flow (base case from master)
3. Backward flow (base case from master)
4. Utilization ratio (flow / capacity)

**Weighted Score Statistics (5 features):**
5. `weighted_times_solved` - Exponentially weighted solve count
6. `weighted_times_cut_generated` - Cuts generated (before filtering)
7. `weighted_times_cut_added` - Cuts added (after filtering)
8. `weighted_total_violations` - Cumulative violation magnitude
9. `weighted_total_cuts_produced` - Total cuts from this scenario

**Removed features (as of v0.7.1):**
- ❌ N-hop neighborhood statistics (10 features) - removed in v0.6.0
- ❌ Average solve time - hardware/timing-dependent
- ❌ Iteration number - not intrinsic to solution state
- ❌ Gap magnitude - solver-dependent bounds
- ❌ Cumulative cuts added - history-dependent

### Weighted Statistics for ML Features

**Important**: As of v0.6.0, ML features use **exponentially weighted statistics** while regular scoring components use cumulative counts. This provides the ML model with depreciation of historical events while keeping scoring stable.

**Weighted Statistics with Exponential Decay:**
- Each iteration, all weighted values are multiplied by decay factor (default 0.9)
- Recent events get full weight (1.0), older events decay exponentially
- After 10 rounds: ~35% impact remaining
- After 22 rounds: ~10% impact remaining

**Example:**
```julia
# Iteration 1: Scenario generates a cut
weighted_times_cut_generated = 1.0

# Iteration 2: No solve (staleness increases)
weighted_times_cut_generated *= 0.9  # = 0.9

# Iteration 3: No solve
weighted_times_cut_generated *= 0.9  # = 0.81

# Iteration 11: Historical event has ~35% weight
weighted_times_cut_generated ≈ 0.35
```

**Benefits:**
- ML model focuses on recent behavior (recent cuts more predictive)
- Adapts to changing solution phase (early vs late game different patterns)
- Prevents ancient history from dominating predictions
- Weighted stats persist across stabilization rounds (long-term learning)

## Feature Normalization

### The Problem: Binary Predictions

Without normalization, features with vastly different scales cause sigmoid saturation:
- Capacity: ~100s
- Flow: ~50-80
- Utilization: 0-1
- Solve time: 0.001-0.01 seconds

This leads to `w·x` becoming very large/small, causing predictions to saturate at 0.0 or 1.0.

### The Solution: Z-Score Normalization

The model applies **online standardization** using Welford's algorithm:

```julia
normalized[i] = (features[i] - mean[i]) / std[i]
```

**Benefits:**
- All features on similar scale
- Prevents weight explosion during training
- Sigmoid operates in sensitive range (-3 to +3)
- Enables continuous probability predictions for ranking

**Implementation:**
- Running mean and std tracked per feature
- Updated incrementally with each training example
- Applied before both prediction and training

### Hyperparameter Tuning

Optimized for stable online learning:

- **Learning rate**: 0.005 (prevents oscillation)
- **Regularization**: 0.01 (prevents overfitting)
- **Number of features**: 9 (deterministic, as of v0.7.1)

## Deterministic Features

All features are **fully deterministic** given the same:
- Random seed (`outage_sampling_seed`)
- Network instance
- Solver configuration

**Key properties:**
- **Master solution**: Capacity installations and flows are deterministic
- **Weighted statistics**: Exponentially decayed but deterministic sequence
- **No timing**: Solve times removed to eliminate hardware variance
- **No phase indicators**: Iteration number removed to focus on solution state

This ensures reproducible results across runs, critical for:
- Experimental comparisons
- Debugging and validation
- Fair benchmarking

## Training Strategy

### Online Learning

The model trains **after each subproblem solve**:

1. Extract features from current master solution
2. Make prediction (if iteration > 1)
3. Solve subproblem
4. Observe label: `cut_generated` (true/false)
5. Update model weights using gradient descent

### Prediction Workflow

**Predictions updated before scenario ordering:**
1. Extract base case flows from master solution
2. For each scenario:
   - Extract 9 deterministic features
   - Normalize using current statistics
   - Predict probability via sigmoid
3. Use prediction as 6th scoring component

## Performance Metrics

The solver tracks ML performance:

```
╔══════════════════════════════════════════════════════╗
║          ML Model Performance Summary                ║
╠══════════════════════════════════════════════════════╣
║  Total Predictions:      1234                        ║
║  Training Updates:       856                         ║
╠══════════════════════════════════════════════════════╣
║  Accuracy:               67.23%                      ║
║  Precision:              72.45%                      ║
║  Recall:                 61.89%                      ║
║  F1-Score:               66.78%                      ║
╚══════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════╗
║     Predictions by Confidence (Cut Generation)       ║
╠═══════════╦══════════╦═══════════╦══════════════════╣
║  Bin      ║  Count   ║  Cut      ║  No Cut          ║
╠═══════════╬══════════╬═══════════╬══════════════════╣
║  0.0-0.2  ║    245   ║      12   ║     233          ║
║  0.2-0.4  ║    356   ║      89   ║     267          ║
║  0.4-0.6  ║    298   ║     145   ║     153          ║
║  0.6-0.8  ║    219   ║     167   ║      52          ║
║  0.8-1.0  ║    116   ║     103   ║      13          ║
╚═══════════╩══════════╩═══════════╩══════════════════╝
```

Metrics include:
- **Accuracy**: Overall prediction correctness
- **Precision**: Of predicted cuts, how many were correct
- **Recall**: Of actual cuts, how many were predicted
- **Confidence bins**: Distribution showing model calibration

## Implementation Details

### Key Functions

**Feature Extraction:**
```julia
extract_subproblem_features(y_values, link_modules, failed_link_idx, 
                           f_base_values, links, scenario_id, subproblem_scores)
```

**Prediction:**
```julia
predict_subproblem_infeasibility(ml_model, y_values, link_modules, failed_link_idx,
                                f_base_values, links, scenario_id, subproblem_scores)
```

**Training:**
```julia
train_subproblem_model!(ml_model, y_values, link_modules, failed_link_idx,
                       f_base_values, links, scenario_id, cut_found, subproblem_scores)
```

### Files

- `src/core/subproblem_scoring_ml.jl`: Feature extraction, model, training
- `src/core/subproblem_scoring_ml_metrics.jl`: Performance metrics and reporting
- `src/models/benders.jl`: Integration with solver

### Graph Construction

Link adjacency is built by parsing link IDs:
```julia
# Link ID format: "nodeA_nodeB"
function build_link_adjacency(links::Vector{String})
    adj = Dict{String, Set{String}}()
    for link in links
        parts = split(link, "_")
        node_a, node_b = parts[1], parts[2]
        # Add all links incident to node_a or node_b
        ...
    end
    return adj
end
```

This supports n-hop BFS traversal for neighborhood computation.

## Expected Impact

### Before Normalization:
```
Predictions: [1.0, 0.0, 1.0, 0.0, 1.0, ...]  # Binary, no ranking ability
```

### After Normalization:
```
Predictions: [0.73, 0.34, 0.89, 0.12, 0.56, ...]  # Continuous, useful for prioritization
```

### Why This Works:
- Normalization keeps `z = w·x` in range [-3, 3]
- Sigmoid transformation:
  - σ(-3) ≈ 0.05
  - σ(0) = 0.50
  - σ(3) ≈ 0.95
- Full probability range accessible for ranking

## Configuration Tips

### High ML Weight
Use when:
- Large number of scenarios (100+)
- Expensive subproblem solves
- Clear patterns in cut generation

```toml
weights = [0.05, 0.0, 0.5, 0.05, 0.1, 0.3]  # 30% ML weight
```

### Low/Zero ML Weight
Use when:
- Small number of scenarios (<20)
- Fast subproblem solves
- Highly variable cut patterns
- Initial exploration

```toml
weights = [0.2, 0.0, 0.6, 0.1, 0.1, 0.0]  # ML disabled
```

### Balanced Approach
Default configuration:
```toml
weights = [0.05, 0.0, 0.8, 0.05, 0.1, 0.0]  # Start without ML, add if needed
```

## Debugging

Enable verbose output to see per-iteration predictions:

```toml
[output]
subproblem_verbose = true
```

Output includes ML predictions for each scenario:
```
 Iter | Scenario | Score     | ML Pred  | Time(s)  | Cut
    5 |       13 |  0.947380 | 0.703403 |   0.0246 | X
    5 |        6 |  0.943101 | 0.696820 |   0.0223 | X
```

## Future Enhancements

Potential improvements:
- Configurable n-hop neighborhood size
- Weighted neighborhood (closer links weighted more)
- Additional temporal features (time since last cut)
- Batch normalization updates
- Model persistence across solves
