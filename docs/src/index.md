# BendersNetworkDesign.jl

Two-stage stochastic network design solver with Benders decomposition and intelligent subproblem selection strategies.

**Version 0.7.2**

## Overview

BendersNetworkDesign.jl implements a two-stage stochastic network design problem solver with:

- **Benders decomposition** with lazy constraint callbacks
- **Multi-criteria subproblem scoring** for intelligent scenario prioritization
- **Adaptive cut limit strategies** for performance optimization
- **Multiple stopping criteria** for efficient iteration control
- **N-k outage modeling** for multiple simultaneous link failures
- **SNDlib network format** support
- **Gurobi optimization solver**

## Key Features

### Multi-Criteria Subproblem Scoring

The package uses a sophisticated scoring system with six components:

1. **Violation**: Magnitude of constraint violations
2. **Reliability**: Historical success rate of finding cuts (unfiltered)
3. **Filtered Reliability**: Historical rate of cuts added after filtering
4. **Total Share**: Cumulative contribution to objective improvement
5. **Stabilization**: Staleness tracking for scenario diversity
6. **ML Prediction**: Machine learning-based infeasibility prediction (optional)

### Advanced Subproblem Selection

Multiple stopping criteria can be configured:

- Cut limits (absolute or relative to number of scenarios)
- Solve limits (number of subproblems to solve per iteration)
- Consecutive misses (absolute or relative)
- Minimum score threshold
- Iteration time limits
- Adaptive cut limits with three adaptation mechanisms

### Cut Filtering

DBSCAN-based diversity filtering (using `Clustering.jl`) and efficacy-based filtering:

- **Diversity**: Cluster similar cuts and select representative medoids using DBSCAN
- **Efficacy**: Prioritize cuts with highest violation
- **Hybrid**: Combine both strategies

### Machine Learning (Optional)

Online logistic regression for subproblem prioritization:

- Optimized feature engineering with aggregate dual flow features
- Z-score normalization to prevent sigmoid saturation
- Includes solve time as temporal difficulty signal
- Tracks accuracy, precision, recall, and confidence calibration

### Stabilization Rounds

Periodic full scenario solving with score reset ensures robustness and prevents over-specialization.

### Comprehensive Result Tracking

Detailed solve statistics for experimental analysis:

- Branch-and-bound node counts via `MOI.NodeCount()`
- Objective bounds via `JuMP.objective_bound()`
- Timing breakdowns (master, callback, subproblem, ML, DBSCAN)
- Cut filtering effectiveness (cuts found vs cuts added)
- Subproblem solve counts

## Installation

```julia
using Pkg
Pkg.develop(path="path/to/BendersNetworkDesign")
```

## Quick Example

```julia
using BendersNetworkDesign
using Gurobi

# Load network
network = read_sndlib_network("data/sndlib/abilene.xml")

# Generate outage scenarios
scenarios = generate_outage_scenarios(network; include_base_case=false)

# Read settings
settings = read_settings("settings/default.toml")

# Solve
env = Gurobi.Env()
result = solve_benders(network; 
                      optimizer=() -> Gurobi.Optimizer(env),
                      outage_scenarios=scenarios,
                      settings=settings)

println("Objective: ", result.objective_value)
println("Iterations: ", result.iterations)
println("Cuts: ", result.total_cuts_added)
println("Branch-and-bound nodes: ", result.node_count)
```

## Performance

On the Abilene network with 15 single-link outages:

- **Compact MIP**: 438,077 objective in 4.27s
- **Benders (adaptive)**: 438,077 objective in 3.27s (23% faster)

## Contents

```@contents
Pages = ["getting_started.md", "formulation.md", "configuration.md", "ml_methodology.md"]
Depth = 2
```
