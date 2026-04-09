# Configuration

Configuration is managed through TOML files. The package always loads `settings/default.toml` first, then merges any user-specified overrides.

## Configuration Structure

### Solver Settings

```toml
[solver]
solver = "Gurobi"       # Only Gurobi is supported
time_limit = 3600       # Solver time limit in seconds
```

### Subproblem Selection

```toml
[subproblem_selection]
ordering = "score"      # Options: "none", "score", "random"
scoring_random_seed = 42
```

#### Scoring Weights

```toml
[BENDERS.SUBPROBLEM_SCORING]
weights = [0.05, 0.0, 0.8, 0.05, 0.1, 0.0]  # [violation, reliability, filtered_reliability, total_share, stabilization, ml_prediction]
```

The six scoring components:

1. **Violation** (default: 0.05): Magnitude of constraint violations
2. **Reliability** (default: 0.0): Historical rate of finding cuts (unfiltered)
3. **Filtered Reliability** (default: 0.8): Historical rate of cuts actually added after filtering
4. **Total Share** (default: 0.05): Cumulative objective contribution
5. **Stabilization** (default: 0.1): Staleness penalty (rounds since solved)
6. **ML Prediction** (default: 0.0): Machine learning-based infeasibility prediction

**Note**: When ML weight is 0.0, the ML model is completely disabled (no initialization or training overhead).

### Stopping Criteria

#### Consecutive Miss Limit

Stop solving subproblems after consecutive failures to find cuts:

```toml
[subproblem_selection.consecutive_miss]
mode = "absolute"       # "absolute" or "relative"
absolute = 5            # Stop after 5 consecutive misses
relative = 0.2          # Stop after 20% of scenarios miss (if mode="relative")
```

#### Minimum Score Threshold

Stop when scenario scores drop below threshold:

```toml
[subproblem_selection.min_score_threshold]
enabled = false
threshold = 0.1
```

#### Iteration Time Limit

Stop after a time budget per iteration:

```toml
[subproblem_selection.iteration_time_limit]
enabled = false
time_seconds = 60.0
```

### Cut Limits

#### Static Cut Limit

```toml
[subproblem_selection.cut_limit]
mode = "static"
static = -1             # -1 = unlimited, or specify limit (e.g., 5, 10)
```

#### Adaptive Cut Limit

Dynamically adjust cut limits based on solution progress:

```toml
[subproblem_selection.cut_limit]
mode = "adaptive"

[subproblem_selection.cut_limit.adaptive]
initial_cuts = 10
min_cuts = 3
max_cuts = 20

# Phase-based adaptation
phase_early_iterations = 10
phase_early_multiplier = 1.5
phase_late_iterations = 50
phase_late_multiplier = 0.5

# Progress-based adaptation
progress_enabled = true
progress_stall_threshold = 0.01
progress_stall_penalty = 0.8

# Time-balanced adaptation
time_enabled = true
time_target_ratio = 0.3
time_adjustment_rate = 0.1
```

**Adaptation Mechanisms:**

1. **Phase-based**: Higher limits early, lower limits late
2. **Progress-based**: Reduce limits when objective improvement stalls
3. **Time-balanced**: Adjust based on subproblem vs total time ratio

### Cut Filtering

Filter cuts based on diversity or efficacy before adding to master problem:

```toml
[BENDERS.CUT_FILTERING]
strategy = "diversity"   # Options: "none", "diversity", "efficacy", "hybrid"
max_cuts = 5             # Maximum cuts to add per iteration
diversity_threshold = 0.2  # Minimum Jaccard distance for DBSCAN (default: 0.2)
```

**Filtering Strategies:**

1. **None**: Add all cuts without filtering
2. **Diversity**: DBSCAN clustering (via `Clustering.jl`) with medoid selection (maximizes cut variety)
3. **Efficacy**: Select cuts with highest violation (maximizes immediate impact)
4. **Hybrid**: Combine diversity and efficacy criteria

The diversity strategy uses DBSCAN from the `Clustering.jl` library to cluster similar cuts (based on Jaccard distance of coefficient support) and selects the medoid (most representative cut) from each cluster. The `diversity_threshold` parameter controls the DBSCAN epsilon (minimum distance between clusters).

### Stabilization

The package provides three orthogonal stabilization mechanisms that can be combined:

#### 1. Score Initialization

```toml
[BENDERS.SUBPROBLEM_SELECTION]
score_initialization_enabled = true  # Solve all scenarios in first iteration
```

When enabled, the first Benders iteration solves all scenarios regardless of selection strategy, providing an unbiased initial ranking.

#### 2. Periodic Stabilization

```toml
[BENDERS.SUBPROBLEM_SELECTION]
stabilization_frequency = 200  # Solve all scenarios every N iterations (0 to disable)
```

Periodic stabilization rounds ensure:
- All scenarios are periodically revisited
- Scores don't become overly specialized
- Robustness against local optima
- Score history is reset after each stabilization round

#### 3. Root Node Stabilization

```toml
[BENDERS.SUBPROBLEM_SELECTION]
root_node_stabilization = 0  # Control solving at root node
```

**Values:**
- `0`: Disabled (default) - normal selection strategy applies at root node
- `N > 0`: First N Benders iterations at root node solve all scenarios
- `-1`: Unlimited - always solve all scenarios while at root node (until branching)

**Purpose:** Ensures strong initial cuts before branch-and-bound tree exploration begins. This can:
- Improve initial dual bound
- Reduce overall tree size
- Provide comprehensive scenario coverage early

**Implementation:** Uses Gurobi callback (`GRB_CB_MIPSOL_NODCNT`) to detect root node (node_count = 0). Tracks iterations spent at root via `root_node_iteration` counter.

**Example Combinations:**
```toml
# Strong initial relaxation, then selective
[BENDERS.SUBPROBLEM_SELECTION]
score_initialization_enabled = true
stabilization_frequency = 0
root_node_stabilization = 3  # First 3 iterations at root

# Continuous exploration + periodic refresh
[BENDERS.SUBPROBLEM_SELECTION]
score_initialization_enabled = false
stabilization_frequency = 50  # Every 50 iterations
root_node_stabilization = -1  # All iterations at root
```

**Note:** These mechanisms are completely independent:
- Initialization: First iteration only (regardless of node)
- Periodic: Every N iterations (regardless of node)
- Root node: First N iterations while at root node (before branching)

### Output Control

```toml
[output]
validate_cuts = false                   # Validate cuts before adding (debug)
subproblem_verbose = false              # Print per-subproblem details
subproblem_verbose_cuts_only = false    # Only print subproblems with cuts
```

## Example Configurations

### High Performance

```toml
[subproblem_selection]
ordering = "score"
scoring_weights = [0.4, 0.3, 0.2, 0.1]

[subproblem_selection.cut_limit]
mode = "static"
static = 5

[subproblem_selection.consecutive_miss]
mode = "absolute"
absolute = 3
```

### Thorough Search

```toml
[subproblem_selection]
ordering = "score"

[subproblem_selection.cut_limit]
mode = "static"
static = -1  # Unlimited

[subproblem_selection.consecutive_miss]
mode = "absolute"
absolute = 10
```

### Adaptive Strategy

```toml
[subproblem_selection.cut_limit]
mode = "adaptive"

[subproblem_selection.cut_limit.adaptive]
initial_cuts = 15
min_cuts = 5
max_cuts = 25
progress_enabled = true
time_enabled = true
```

## Validation

The configuration system validates:
- Unknown keys are reported with helpful error messages
- All required fields must be present in `default.toml`
- Nested structures follow TOML format requirements

## Complete Parameter Reference

### Solver Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SOLVER.SOLVER` | String | `"Gurobi"` | Optimization solver (only `"Gurobi"` is supported) |
| `SOLVER.time_limit` | Float | `10800` | Global solver time limit in seconds |

### Model Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `MODEL.model_type` | String | `"benders"` | Model type (`"benders"` or `"compact"`) |

### Scenario Generation

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SCENARIOS.num_outage_scenarios` | Int | `-1` | Number of scenarios to generate (`-1` = all single-link failures) |
| `SCENARIOS.outage_sampling_seed` | Int/Nothing | `42` | Random seed for scenario sampling (`nothing` for random) |
| `SCENARIOS.k_failures` | Int | `1` | Number of simultaneous link failures (N-k outages) |

**N-k Outage Modeling:**
- `k_failures = 1`: Single link failures (default)
- `k_failures = 2`: All pairs of simultaneous link failures
- `k_failures = k`: All combinations of k simultaneous failures

For a network with n links, the number of scenarios is C(n, k) = n!/(k!(n-k)!). Example: 20 links with k=2 produces 190 scenarios.

### Subproblem Scoring

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `BENDERS.SUBPROBLEM_SCORING.score.ordering` | String | `"score"` | Scenario ordering (`"none"`, `"score"`, `"random"`) |
| `BENDERS.SUBPROBLEM_SCORING.score.weights` | Vector{Float64} | `[0.05, 0.0, 0.8, 0.05, 0.1, 0.0]` | Weights for 6 score components |
| `BENDERS.SUBPROBLEM_SCORING.score.scale_score` | Bool | `true` | Apply min-max scaling to scores |
| `BENDERS.SUBPROBLEM_SCORING.score.exponential_decay_factor` | Float | `0.9` | Decay factor for weighted statistics (0-1) |
| `BENDERS.SUBPROBLEM_SCORING.random.seed` | Int/Nothing | `nothing` | Random seed for random ordering |

**Score Component Weights:**
1. **Violation**: Average violation magnitude when cut was added
2. **Reliability**: Cut generation rate (before filtering)
3. **Filtered Reliability**: Cut success rate (after filtering) 
4. **Total Share**: Fraction of all cuts produced by this subproblem
5. **Stabilization**: Staleness penalty (rounds since last solved)
6. **ML Prediction**: ML-predicted probability of infeasibility

### Subproblem Selection

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `BENDERS.SUBPROBLEM_SELECTION.strategy` | String | `"static"` | Selection strategy (`"none"`, `"static"`, `"adaptive"`) |
| `BENDERS.SUBPROBLEM_SELECTION.score_initialization_enabled` | Bool | `true` | Solve all scenarios in first iteration |
| `BENDERS.SUBPROBLEM_SELECTION.stabilization_frequency` | Int | `200` | Solve all scenarios every N iterations (0=disabled) |
| `BENDERS.SUBPROBLEM_SELECTION.root_node_stabilization` | Int | `0` | Max iterations to solve all at root (0=disabled, -1=unlimited) |

#### Static Selection Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `BENDERS.SUBPROBLEM_SELECTION.static.min_score_threshold` | Float | `0.7` | Stop when score falls below threshold (-1=disabled) |
| `BENDERS.SUBPROBLEM_SELECTION.static.iteration_time_limit` | Float | `-1.0` | Max time per iteration in seconds (-1=disabled) |
| `BENDERS.SUBPROBLEM_SELECTION.static.cut_limit.mode` | String | `"absolute"` | Limit mode (`"absolute"` or `"relative"`) |
| `BENDERS.SUBPROBLEM_SELECTION.static.cut_limit.absolute` | Int | `-1` | Absolute cut limit (-1=unlimited) |
| `BENDERS.SUBPROBLEM_SELECTION.static.cut_limit.relative` | Float | `0.1` | Relative cut limit (fraction of scenarios) |
| `BENDERS.SUBPROBLEM_SELECTION.static.solve_limit.mode` | String | `"absolute"` | Solve limit mode (`"absolute"` or `"relative"`) |
| `BENDERS.SUBPROBLEM_SELECTION.static.solve_limit.absolute` | Int | `-1` | Max subproblems to solve per iteration (-1=unlimited) |
| `BENDERS.SUBPROBLEM_SELECTION.static.solve_limit.relative` | Float | `0.3` | Relative solve limit (proportion of scenarios) |
| `BENDERS.SUBPROBLEM_SELECTION.static.consecutive_miss.mode` | String | `"absolute"` | Miss limit mode |
| `BENDERS.SUBPROBLEM_SELECTION.static.consecutive_miss.absolute` | Int | `100` | Max consecutive no-cut subproblems |
| `BENDERS.SUBPROBLEM_SELECTION.static.consecutive_miss.relative` | Float | `0.5` | Relative miss limit |

**Solve Limit vs Cut Limit:**
- **Cut limit**: Stop after finding N cuts (controls solution quality per iteration)
- **Solve limit**: Stop after solving N subproblems (controls computational effort per iteration)
- These are independent: solve_limit can be hit before cut_limit if many subproblems don't generate cuts

#### Adaptive Selection Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `BENDERS.SUBPROBLEM_SELECTION.adaptive.mode` | String | `"phase_based"` | Adaptation mode (`"phase_based"`, `"progress_based"`, `"time_balance"`, `"prediction_based"`) |
| `BENDERS.SUBPROBLEM_SELECTION.adaptive.min_score_threshold` | Float | `-1.0` | Min score threshold |
| `BENDERS.SUBPROBLEM_SELECTION.adaptive.iteration_time_limit` | Float | `-1.0` | Time limit per iteration |

**Phase-based parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `adaptive.phase_based.large_gap_threshold` | Float | `0.20` | Gap threshold for early phase |
| `adaptive.phase_based.medium_gap_threshold` | Float | `0.05` | Gap threshold for middle phase |
| `adaptive.phase_based.early_phase_cuts` | Int | `1` | Cuts in early phase (large gap) |
| `adaptive.phase_based.middle_phase_cuts` | Int | `5` | Cuts in middle phase |
| `adaptive.phase_based.late_phase_cuts` | Int | `50` | Cuts in late phase (small gap) |

**Progress-based parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `adaptive.progress_based.base_cuts` | Int | `5` | Initial cut limit |
| `adaptive.progress_based.min_cuts` | Int | `1` | Minimum cut limit |
| `adaptive.progress_based.max_cuts` | Int | `50` | Maximum cut limit |
| `adaptive.progress_based.factor` | Float | `1.5` | Adjustment multiplier |
| `adaptive.progress_based.low_threshold` | Float | `0.01` | Low improvement threshold |
| `adaptive.progress_based.high_threshold` | Float | `0.10` | High improvement threshold |
| `adaptive.progress_based.stagnation_rounds` | Int | `3` | Rounds before stagnation penalty |
| `adaptive.progress_based.movement_factor` | Float | `0.5` | Decrease factor on improvement |
| `adaptive.progress_based.stagnation_factor` | Float | `1.05` | Increase factor on stagnation |

**Time-balance parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `adaptive.time_balance.base_cuts` | Int | `5` | Initial cut limit |
| `adaptive.time_balance.min_cuts` | Int | `1` | Minimum cut limit |
| `adaptive.time_balance.max_cuts` | Int | `50` | Maximum cut limit |
| `adaptive.time_balance.master_threshold` | Float | `2.0` | Master-dominated time ratio |
| `adaptive.time_balance.subproblem_threshold` | Float | `0.5` | Subproblem-dominated ratio |
| `adaptive.time_balance.decrease_factor` | Float | `0.8` | Decrease multiplier |
| `adaptive.time_balance.increase_factor` | Float | `1.2` | Increase multiplier |

**Prediction-based parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `adaptive.prediction_based.learning_rate` | Float | `0.01` | Online learning rate |
| `adaptive.prediction_based.regularization` | Float | `0.01` | L2 regularization strength |
| `adaptive.prediction_based.history_decay` | Float | `0.9` | Exponential decay for performance history |
| `adaptive.prediction_based.default_proportion` | Float | `0.5` | Default proportion before training |
| `adaptive.prediction_based.min_proportion` | Float | `0.05` | Minimum proportion to solve (5%) |
| `adaptive.prediction_based.max_proportion` | Float | `1.0` | Maximum proportion to solve (100%) |
| `adaptive.prediction_based.min_training_rate` | Float | `0.5` | Minimum sample rate for training (50%) |

**Prediction-based Mode:**

The `prediction_based` mode uses online machine learning to predict what proportion of subproblems will yield cuts in each iteration. The model:
- Uses 8 features: min/max/avg/std of subproblem scores and link utilizations
- Predicts before each iteration how many subproblems to solve
- Trains after each iteration on actual outcomes
- Dynamically adjusts solving effort based on expected cut production

**Min Training Rate (Recall Bias Protection):**

The `min_training_rate` parameter prevents **recall bias** - a critical problem when training on incomplete samples:

**Problem:** If the model predicts to solve only 30% of scenarios and all yield cuts, it never learns about the other 70% that might not produce cuts. This creates positive feedback where the model incorrectly believes most scenarios yield cuts.

**Solution:** Skip training if sample rate < min_training_rate (default 50%). This ensures:
- Model only trains when it has seen a representative sample
- No bias toward scenarios that were selected
- More reliable predictions over time

**Example:** With min_training_rate = 0.5, if only 10 out of 50 scenarios were solved (20%), training is skipped for that iteration since 20% < 50%.

### Cut Filtering

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `BENDERS.CUT_FILTERING.strategy` | String | `"none"` | Filtering strategy (`"none"`, `"diversity"`, `"efficacy"`, `"hybrid"`) |
| `BENDERS.CUT_FILTERING.diversity.max_cuts` | Int | `5` | Max cuts to add per iteration |
| `BENDERS.CUT_FILTERING.diversity.diversity_threshold` | Float | `0.2` | Min Jaccard distance for DBSCAN |
| `BENDERS.CUT_FILTERING.efficacy.max_cuts` | Int | `5` | Max cuts to add |
| `BENDERS.CUT_FILTERING.efficacy.norm_type` | String | `"l2"` | Norm type (`"l1"`, `"l2"`, `"linf"`) |
| `BENDERS.CUT_FILTERING.hybrid.max_cuts` | Int | `5` | Max cuts to add |
| `BENDERS.CUT_FILTERING.hybrid.weights` | Vector{Float64} | `[0.5, 0.3, 0.2]` | Weights: [violation, efficacy, diversity] |

### Machine Learning

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `BENDERS.ML.model_write` | Bool | `false` | Export trained model to `check/models/trained_model_INSTANCENAME.jls` |
| `BENDERS.ML.model_read` | Bool | `false` | Load pre-trained model from `check/models/trained_model_INSTANCENAME.jls` |

**Note:** ML is only active when the 6th score component weight > 0. Models are automatically saved/loaded from the `check/models/` directory using the instance filename.

### Logging

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `LOGGING.statistics` | Bool | `true` | Print solution statistics |
| `LOGGING.ml_statistics` | Bool | `true` | Print ML model statistics |
| `LOGGING.subproblem_log` | Bool | `false` | Print per-subproblem details |
| `LOGGING.subproblem_log_success` | Bool | `false` | Print only successful subproblems |
| `LOGGING.print_solution` | Bool | `false` | Print final solution values |

### Debug

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `BENDERS.DEBUG.validate_cuts` | Bool | `false` | Validate cuts before adding (debug mode) |

## Best Practices

1. **Start with default.toml**: Copy and modify rather than creating from scratch
2. **Test incrementally**: Change one parameter at a time to understand impact
3. **Monitor accuracy**: Use `subproblem_verbose = true` to see cut production rates
4. **Balance speed vs quality**: Lower cut limits generally faster but may need more iterations
5. **Use root node stabilization**: Set `root_node_stabilization = 2-5` for strong initial cuts
6. **Combine stabilization methods**: Use initialization + root node for best early-phase performance
