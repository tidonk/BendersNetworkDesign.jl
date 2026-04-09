# Benders Testing Framework

This directory contains a framework for testing different Benders decomposition configurations on network design instances.

## Directory Structure

```
check/
├── test_instance.jl           # Script to solve single instance and write CSV results
├── run_cluster_test.sh        # Batch submission script for HTCondor
├── htcondor_template.sub      # HTCondor submission template
├── testset/                   # Test set definitions
│   └── abilene.test          # Example: Abilene instance with multiple configs
├── temp/                      # Generated HTCondor submission files
├── logs/                      # HTCondor job logs
└── results/                   # CSV output files
```

## Configuration Parameters

The framework supports testing:

1. **Cut limits** (`max_cuts_per_iteration`): 
   - `1`, `5`, `10`, `-1` (unlimited)

2. **Subproblem ordering strategies** (`subproblem_ordering`):
   - `"none"`: Original order (no adaptive ordering)
   - `"score"`: Score-based ordering (using violation, reliability, share, staleness)
   - `"random"`: Random order each iteration

3. **Scoring weights** (`scoring_weights`):
   - `[w_violation, w_reliability, w_total_share, w_branch_switching, w_stabilization]`
   - Default: `[0.3, 0.3, 0.3, 0.1, 0.01]`

## Usage

### 1. Create a Settings File

Create TOML files in `../settings/` with your configuration. Example:

```toml
[SOLVER]
    SOLVER = "Gurobi"

[MODEL]
    model_type = "benders"

[BENDERS]
    max_cuts_per_iteration = 1
    subproblem_ordering = "score"
    scoring_weights = [0.3, 0.3, 0.3, 0.1, 0.01]
    num_outage_scenarios = -1
    outage_sampling_seed = 42
    validate_cuts = false
```

### 2. Create a Testset File

Create a file in `testset/` listing instance-config pairs:

```
# testset/my_test.test
# Format: <network_file>;<settings_file>

../../data/sndlib/abilene.xml;../settings/test_cuts1_order_none.toml
../../data/sndlib/abilene.xml;../settings/test_cuts1_order_score.toml
../../data/sndlib/france.xml;../settings/test_cuts1_order_score.toml
```

Paths are relative to the `check/` directory.

### 3. Run the Batch Test

```bash
cd check/
./run_cluster_test.sh testset/my_test.test
```

This will:
- Generate HTCondor submission files in `temp/`
- Submit jobs to HTCondor (if available)
- Write logs to `logs/`
- Append results to `results/<instance>.csv`

### 4. Manual Testing (Single Instance)

To test a single configuration without HTCondor:

```bash
cd check/
julia test_instance.jl ../../data/sndlib/abilene.xml ../settings/test_cuts1_order_score.toml results/test.csv
```

## Output CSV Format

Results are written to CSV with the following columns:

**Instance Information:**
- `instance`: Instance filename
- `num_nodes`: Number of nodes
- `num_links`: Number of links  
- `num_demands`: Number of demands
- `num_scenarios`: Number of outage scenarios

**Configuration:**
- `settings_file`: Settings filename
- `solver`: Solver used (e.g., "Gurobi")
- `model_type`: "benders" or "compact"
- `max_cuts_per_iteration`: Cut limit per iteration
- `subproblem_ordering`: Ordering strategy
- `scoring_weights`: Scoring weights (semicolon-separated)

**Performance Metrics:**
- `total_time`: Total execution time (seconds)
- `solve_time`: Solver time (seconds)
- `master_time`: Time in master problem (seconds)
- `callback_time`: Time in Benders callback (seconds)
- `subproblem_time`: Time solving subproblems (seconds)
- `ml_training_time`: Time training ML model (seconds)
- `dbscan_time`: Time in DBSCAN clustering (seconds)

**Solution Quality:**
- `objective_value`: Objective function value
- `bound`: Best bound from branch-and-bound
- `status`: Termination status (e.g., "OPTIMAL")
- `bb_nodes`: Branch-and-bound nodes explored

**Benders Statistics:**
- `benders_iterations`: Number of Benders iterations
- `benders_cuts`: Number of cuts added (after filtering)
- `benders_cuts_found`: Number of cuts found (before filtering)
- `benders_subproblems_solved`: Total subproblems solved

The detailed metrics enable comprehensive performance analysis of different configurations and filtering strategies.

## HTCondor Management

Monitor jobs:
```bash
condor_q
```

Monitor specific batch:
```bash
condor_q -const 'JobBatchName == "benders-abilene-20251219_122847"'
```

Remove batch:
```bash
condor_rm -const 'JobBatchName == "benders-abilene-20251219_122847"'
```

## File Transfer

The HTCondor template automatically transfers CSV result files back to the submit node:
- **Output files**: All `*.csv` files generated during job execution
- **Destination**: Automatically placed in `results/` directory
- **Transfer trigger**: Files transferred when job exits or is evicted

This ensures results are captured even when jobs run on remote execution nodes without shared filesystems.

## Example: Testing Abilene

The provided `testset/abilene.test` demonstrates testing different configurations:

```bash
cd check/
./run_cluster_test.sh testset/abilene.test
```

This tests:
- Cut limits: 1, 5, unlimited
- Ordering: none, score-based, random
- Total: 7 configurations

Results written to: `results/abilene.csv`

## Notes

- **HTCondor unavailable**: Script will still generate submission files in `temp/` that can be submitted later
- **CSV append mode**: Results append to existing files, allowing incremental testing
- **Job timeout**: Jobs are killed after 10 minutes (600 seconds, configurable in `htcondor_template.sub`)
- **Automatic file transfer**: CSV results automatically transferred back to `results/` directory
- **Julia execution**: Uses direct Julia binary instead of juliaup launcher for HTCondor compatibility
