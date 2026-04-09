# Getting Started

## Installation

Clone the repository and activate the project:

```bash
git clone <repository-url>
cd benders-subproblem-filtering/code
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

## Basic Usage

### Running the Main Solver

```julia
using BendersNetworkDesign

# Solve Abilene network with default settings
main("../data/sndlib/abilene.xml", "settings/default.toml")
```

### Custom Configuration

Create a custom settings file:

```toml
# my_settings.toml
[solver]
solver = "Gurobi"
time_limit = 1800

[subproblem_selection]
ordering = "score"
scoring_weights = [0.4, 0.3, 0.2, 0.1]
```

Then use it:

```julia
main("../data/sndlib/abilene.xml", "my_settings.toml")
```

## Running Tests

The package includes a comprehensive test suite with organized settings:

```bash
# Run all tests
julia --project=. test/runtests.jl

# Or using Pkg
julia --project=. -e 'using Pkg; Pkg.test()'
```

### Test Organization

Tests are organized in `test/` with shared utilities in `test/common.jl`:

- **Unit tests**: `test_settings.jl`, `test_sndlib.jl`
- **Model tests**: `test_benders.jl`, `test_benders_vs_compact.jl`
- **Feature tests**: `test_diversity_filtering.jl`, `test_ml_scoring.jl`, `test_ml_train_and_test.jl`
- **Validation tests**: `test_known_objectives.jl`, `test_france_optimal.jl`

### Test Settings

Test configurations are stored in `settings/test/`:

- **Basic tests**: `test_static.toml`, `test_unlimited.toml`, `test_adaptive.toml`
- **ML tests**: `ml_train.toml`, `ml_inference.toml`
- **Feature tests**: `test_diversity.toml`, `test_ml_scoring.toml`

All test files use predefined settings files (no temporary TOML generation).

### Cluster Experiments

For batch testing on HTCondor clusters, see `check/`:

```bash
cd check
./run_cluster_test.sh testset/abilene.test
```

Results are written to CSV files in `check/results/` with comprehensive metrics.

## Available Networks

The package includes several SNDlib networks in `data/sndlib/`:

- `abilene.xml` - 12 nodes, 15 links
- `atlanta.xml` - 15 nodes, 22 links
- `geant.xml` - 22 nodes, 36 links
- `nobel-germany.xml` - 17 nodes, 26 links
- And more...

## Next Steps

- Learn about the [Problem Formulation](formulation.md)
- Explore [Configuration Options](configuration.md)
- Check the [API Reference](api/models.md)
