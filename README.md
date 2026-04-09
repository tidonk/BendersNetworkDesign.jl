# BendersNetworkDesign.jl

[![Pipeline Status](https://git.or.rwth-aachen.de/benders-subproblem-selection/BendersNetworkDesign.jl/badges/main/pipeline.svg)](https://git.or.rwth-aachen.de/benders-subproblem-selection/BendersNetworkDesign.jl/-/commits/main)
[![Coverage](https://git.or.rwth-aachen.de/benders-subproblem-selection/BendersNetworkDesign.jl/badges/main/coverage.svg)](https://git.or.rwth-aachen.de/benders-subproblem-selection/BendersNetworkDesign.jl/-/commits/main)
[![Documentation](https://img.shields.io/badge/docs-latest-blue.svg)](https://git.or.rwth-aachen.de/pages/benders-subproblem-selection/BendersNetworkDesign.jl/)

Benders decomposition for survivable network design with scenario prioritization.

---

## Problem

Two-stage stochastic program:
- **Stage 1:** Install capacity modules (integer decisions)
- **Stage 2:** Route demands under link failure scenarios (LP subproblems)
- **Objective:** Min cost to satisfy demands under all scenarios

---

## Feature Overview

- SNDlib format support (reading/writing)
- **Instance Generation** 
    - Plug together multiple SNDlib instances to generate random new networks
- **Subproblem Scoring**
    - Weighted linear combination
    - Online regression model (single-regressor)
    - Online regression model (multi-regressor with k-hop neighborhood features)
- **Subproblem Selection**
    - Partial subproblem solving based on
        - Number of cuts found
        - Number of consecutive misses (subproblems that did not yield a cut)
        - Elapsed iteration time
        - Proportion of subproblems
        - Score
    - Oracle strategy for perfect information baseline
    - Stabilization rounds
    - [Experimental] Adaptive solve limits (phase/progress/time-based/prediction-based)
- **Cut filtering**
    - DBSCAN cut filtering for diversity
- Documentation

## Repository Structure
TODO: add a graph overview of the directories

---

## Quick Start

```bash
git clone https://git.or.rwth-aachen.de/benders-subproblem-selection/BendersNetworkDesign.jl.git
cd BendersNetworkDesign.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. Main.jl
```

## Configuration

Settings in `settings/*.toml`:

```toml
[BENDERS.SUBPROBLEM_SCORING]
    ordering = "score"
    [BENDERS.SUBPROBLEM_SCORING.score]
        weights = [0.05, 0.0, 0.8, 0.05, 0.1, 0.0]  # violation, reliability, etc.

[BENDERS.SUBPROBLEM_SELECTION]
    strategy = "static"  # or "adaptive", "oracle"
    
[BENDERS.CUT_FILTERING]
    strategy = "diversity"
    max_cuts = 5
```

## Oracle Mode

Records which scenarios yield cuts (write), then replays (read) for baseline:

```bash
julia --project=. examples/run_oracle.jl
```

Oracle data defaults to `check/oracle/<instance_name>.csv` or can be specified in settings.

See [documentation](https://git.or.rwth-aachen.de/pages/benders-subproblem-selection/BendersNetworkDesign.jl/) for all options including ML configuration (with exponential decay for weighted statistics), solver settings, stopping criteria, and adaptive strategies.

## Examples

The `examples/` directory contains standalone scripts for common workflows:

- **`run_oracle.jl`**: Two-phase oracle experiments (write perfect information, then replay)
- **`run_comparison.jl`**: Compare multiple strategies (standard vs ML-based scoring)
- **`run_train_and_test_ml.jl`**: Train and test ML models for subproblem prediction
- **`run_instance_generation.jl`**: Generate test instance suites

These scripts can be run directly or used as templates for custom experiments.

## Usage Example

```julia
using BendersNetworkDesign
using Gurobi

# Load network
network = read_sndlib_network("data/sndlib/abilene.xml")

# Generate outage scenarios (all single-link failures)
scenarios = generate_outage_scenarios(network; include_base_case=false)

# Read settings
settings = read_settings("settings/default.toml")

# Solve with Benders
env = Gurobi.Env()
result = solve_benders(network; 
                      optimizer=() -> Gurobi.Optimizer(env),
                      outage_scenarios=scenarios,
                      settings=settings)

println("Objective: ", result.objective_value)
println("Iterations: ", result.iterations)
println("Cuts added: ", result.total_cuts_added)
println("Branch-and-bound nodes: ", result.node_count)
```

## Instance Generation

Generate test instances:

```bash
julia --project=. examples/run_instance_generation.jl

# Quick test suite (5 instances)
files = generate_quick_test_suite(base_seed=42)

# Varied suite: 2-5 networks, proportions 0.3-0.7 (30 instances)
files = generate_varied_suite(base_seed=800, num_instances=30)

# Spanning suite: proportions 0.1 to 1.0 (50 instances)
files = generate_spanning_suite(base_seed=100, num_instances=50)

# Custom suite
files = BendersNetworkDesign.generate_instance_suite(
    num_instances=20,
    base_seed=42,
    num_networks_range=[3, 4, 5],  # Combine 3-5 networks
    proportion_range=[0.5, 1.0],    # 50% or full networks
    cost_scale_factors=[0.1],
    output_dir="../data/generated/custom",
    manifest_file="instance_manifest.md"
)
```

**Features:**
- Proportion-based sizing: `proportion=0.5` extracts 50% of each network
- Automatic cost scaling (default 0.1) keeps objectives < 1e6
- Markdown manifests with formatted tables
- Generation metadata tracking (source networks, seeds, proportions)

**Available base networks:** 26 SNDlib instances from 10 nodes (dfn-bwin) to 161 nodes (brain)

---

## Performance Results

> *Pending...*


## Testing

Run the complete test suite:

```bash
julia --project=. test/runtests.jl
```

Or use the Julia package manager:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Run specific test files:

```bash
julia --project=. -e 'using Pkg; Pkg.test("BendersNetworkDesign"; test_args=["settings"])'
```

### Test Coverage

The package includes comprehensive tests covering:

- Settings: Configuration loading, validation, solver detection
- SNDlib Reader: Data structures, network parsing, demand handling
- Model Units: Single link, parallel paths, capacity constraints
- Integration: Full problem instances with multiple solvers
- Validation: Formulation correctness against literature
- ML Scoring: Feature extraction, normalization, online training, n-hop neighborhoods

Formulation correctness is verified against standard literature references (Birge & Louveaux).

## API Reference

### Exports
Key exports:
- `solve_benders(network, outage_scenarios, settings; optimizer)` - Main solver
- `solve_compact_model(network, scenarios; kwargs...)` - Compact formulation
- `read_sndlib_network(filepath)` - Parse SNDlib XML
- `write_sndlib_network(network, filepath)` - Export to SNDlib XML
- `read_settings(filepath)` - Load configuration
- `generate_outage_scenarios(network; include_base_case)` - Create scenarios
- `generate_single_instance(instance_id, base_seed; kwargs...)` - Generate single combined instance
- `generate_instance_suite(; kwargs...)` - Generate test suite with parameter variation
- `combine_sndlib_instances(file_paths, prefixes; kwargs...)` - Combine multiple networks

Data structures: `Settings`, `SNDlibNetwork`, `OutageScenario`, `SubproblemScore`

See [API documentation](https://git.or.rwth-aachen.de/pages/benders-subproblem-selection/BendersNetworkDesign.jl/) for complete reference.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the [Creative Commons Attribution 4.0 International License (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/). See [LICENSE](LICENSE) for details.

## Citation

If you use this software in your research, please cite:

```bibtex
@article{benders-subproblem-selection,
  author = {TODO: Add author names},
  title = {Adaptive Subproblem Selection for Benders Decomposition in Survivable Network Design},
  journal = {TODO: Add journal name},
  year = {2026},
  url = {https://git.or.rwth-aachen.de/benders-subproblem-selection/BendersNetworkDesign.jl}
}
```

See [CITATION.bib](CITATION.bib) for the complete BibTeX entry.