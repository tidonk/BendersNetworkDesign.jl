# Changelog

All notable changes to BendersNetworkDesign.jl.

## [0.10.0] - 2026-01-26

### Added
- Oracle selection strategy: records which scenarios yield cuts (write mode), then replays them (read mode) for perfect information baseline
- `OracleData` struct stores iteration→scenarios mappings using failed_link_indices (not IDs)
- `OracleError` exception for validation failures
- Special "*" marker in CSV for iterations with no cuts (must solve all scenarios to verify solution)
- `run_oracle.jl` convenience script for two-phase experiments

### Changed
- Removed `DelimitedFiles` dependency (manual CSV parsing)
- Oracle write mode uses `NoneSelection` internally, only records data

### Fixed
- Oracle validation skips no-cut iterations (expect_no_cuts flag)

## [0.9.0] - 2026-01-23

### Added
- **Multi-regressor ML scoring**: One regressor per scenario for improved recall
  - `ml_mode` setting: "single" (default) or "multi" for multi-regressor mode
  - Scenario-specific pattern learning improves cut prediction accuracy
  - k-hop neighborhood features: capacity/flow/utilization stats in 2-hop radius
  - Flexible feature system via `FeatureConfig` for easy feature selection
  - Aggregated metrics across all regressors for performance tracking
- **Locality features**: k-hop neighborhood statistics for multi-regressor
  - Configurable `ml_khop_distance` (default: 2)
  - avg/std/min/max statistics for capacity, flow, utilization in k-hop neighborhood
  - 21 total features with all groups enabled (3+1+12+5)
- `test_ml_multi_regressor.jl`: Comprehensive tests for multi-regressor functionality

### Changed
- ML configuration moved to `[BENDERS.ML]` section in settings with learning rate and regularization
- `OnlineLogisticRegression` initialization now uses settings parameters instead of hardcoded values
- Multi-dispatch for `update_ml_predictions!()` and `train_ml_on_subproblem!()` to support both modes

## [0.8.0] - 2026-01-22

### Added
- ML proportion predictor: Online logistic regression predicts how many subproblems will yield cuts per iteration
- 8 aggregated features: min/max/avg/std of scores and link utilizations
- `prediction_based` mode in adaptive selection with recall bias protection (min training sample rate)
- Helper functions `predict_ml_selection_limit!()` and `train_ml_selection!()` for cleaner callback code
- Centered bar visualization for ML weights display (matches scoring weights format)

### Changed
- Simplified feature set from 32 to 8 features with explicit unpacking
- AdaptiveCutLimit now supports 4 modes: phase_based, progress_based, time_balance, prediction_based
- Settings struct extended with prediction-based parameters

### Fixed
- Handle `nothing` values in `preinstalled_capacity` during utilization feature extraction

## [0.7.2] - 2026-01-20

### Added
- **N-k outage functionality**: Support for multiple simultaneous link failures
  - `k_failures` parameter in settings to specify number of concurrent failures (default: 1)
  - Generate scenarios with k random link failures using combinations
  - Extended `generate_outage_scenarios()` to support N-k failures
  - Added `k_failures` field to `OutageScenario` struct
- **Subproblem solving limit**: New stopping criterion based on number of subproblems solved
  - `solve_limit` parameter with absolute/relative modes in `StaticCutLimit`
  - `num_solves_this_iter` counter in `IterationData` to track solved subproblems per iteration
  - Independent of cut limits - controls exploration vs exploitation trade-off
- **Enhanced ML feature engineering**: Improved subproblem scoring features
  - Aggregate dual flow feature replacing individual dual flow components
  - More compact and efficient feature representation
  - Better feature normalization and scaling
- **Performance improvements**: Faster ML online training
  - Optimized feature extraction and normalization
  - Reduced computational overhead in scoring updates
- **Primal-Dual integral plotter**: New evaluation tool for solution quality over time
  - Track primal and dual bounds throughout solution process
  - Compute and visualize PD integral metric
  - Added to experiment analysis framework

### Changed
- **LP warm start disabled**: Removed LP warm start from subproblem solving for better numerical stability
  - Disabled `set_start_value()` calls for subproblem flow variables
  - Improves convergence reliability across different instances
- ML feature count reduced from 17 to more compact representation
- Updated plotter functionality for enhanced result visualization
- Improved solve time reporting accuracy

### Fixed
- Corrected solving time reporting to accurately reflect callback and subproblem times
- Improved numerical stability in subproblem solving without warm start

## [0.7.1] - 2026-01-17

### Fixed
- **Nondeterminism in ML predictor**: Removed timing and solver-dependent features that caused nondeterministic behavior:
  - Removed `average_solve_time` (hardware/timing-dependent)
  - Removed `iteration_number` (phase indicator, not intrinsic to solution)
  - Removed `gap_magnitude` (solver-dependent bounds)
  - Removed `cumulative_cuts_added` (history-dependent)
- ML model now uses only 9 deterministic features: 4 failed link features + 5 weighted score statistics
- Results are now fully reproducible given the same random seed and network instance

### Changed
- ML feature count reduced from 14 to 9 features
- Updated documentation to reflect deterministic feature set

## [0.7.0] - 2026-01-16

### Added
- **Instance Generation Framework**: Systematic generation of test instances from SNDlib base networks
- `generate_single_instance()`: Generate combined instances from randomly selected base networks
- `generate_instance_suite()`: Generate test suites with systematic parameter variation
- Proportion-based sizing: Scale networks by proportion (0 < p ≤ 1.0, where 1.0 = full networks)
- Four convenience generation functions:
  - `generate_quick_test_suite()`: 5 instances for quick testing
  - `generate_large_suite()`: 50 diverse instances for comprehensive testing
  - `generate_spanning_suite()`: Instances spanning proportions 0.1 to 1.0
  - `generate_varied_suite()`: 2-5 networks with proportions 0.3-0.7
- `GenerateInstances.jl`: High-level script with generation wrappers
- `SNDLIB_NETWORKS` and `NETWORK_SIZES` constants for all 26 base networks
- Markdown manifest generation: `instance_manifest.md` with formatted tables
- Automatic cost scaling (default 0.1) to keep objectives < 1e6
- XML export with generation metadata tracking source networks, proportions, seeds

### Changed
- Instance generation functions moved from script to `src/network/instance.jl`
- Core generation logic now part of package API
- Manifest format changed from plain text to Markdown with tables
- Default manifest filename changed from `instance_manifest.txt` to `instance_manifest.md`

### Fixed
- Proportional sizing now caps allocations at original network sizes (can't extract more nodes than exist)
- Added missing `Dates` import to `src/network/instance.jl`

## [0.6.1] - 2026-01-16

### Added
- Root node stabilization feature: `root_node_stabilization` parameter to control subproblem solving at the root node of the branch-and-bound tree
- Node count tracking via Gurobi callback (`GRB_CB_MIPSOL_NODCNT`) to detect root node
- `root_node_iteration` counter in `IterationData` to track iterations spent at root node
- `is_root_node` flag in `IterationData` to indicate current node status
- `get_node_count()` function in benders.jl to query Gurobi's node count
- Support for three stabilization modes:
  - `0`: Disabled (default) - normal selection strategy applies at root
  - `N > 0`: First N iterations at root solve all scenarios
  - `-1`: Unlimited - always solve all scenarios while at root node

### Changed
- `should_stop_solving()` now checks root node iteration count against `root_node_stabilization` limit
- Root node iteration counter increments while at root node, resets when branching begins
- Updated selection strategy logic to respect root node stabilization alongside initialization and periodic stabilization

### Fixed
- Better separation of concerns: initialization (first iteration), periodic stabilization (every N iterations), and root node stabilization (first N at root) are now fully orthogonal

## [0.6.0] - 2026-01-15

### Added
- Exponential decay mechanism for subproblem scoring with configurable decay factor (default 0.9)
- Weighted statistics tracking in `SubproblemScore` for temporal depreciation
- `exponential_decay_factor` parameter in settings (controls historical event influence)
- Separate weighted statistics exclusively for ML model feature engineering
- Test settings directory (`settings/test/`) for organized test configuration files
- `SETTINGS_DIR` constant in test suite common.jl

### Changed
- **Breaking**: Subproblem scoring now uses exponentially weighted statistics for ML features only
- Score components (violation, reliability, total_share) now use cumulative statistics (not weighted)
- ML features leverage weighted statistics with ~35% impact after 10 rounds, ~10% after 22 rounds
- Weighted statistics persist across stabilization rounds (no reset)
- Test suite refactored: all test settings moved to `settings/test/` subdirectory
- Test files no longer write temporary TOML files (use pre-configured settings)
- ML training/inference tests use dedicated `ml_train.toml` and `ml_inference.toml` settings

### Fixed
- `settings` undefined error in `extract_subproblem_features()` (removed conditional check)
- All test file paths updated to use `settings/test/` directory
- Improved code quality across test suite with consistent path handling

## [0.5.1] - 2026-01-07

### Added
- CSV export: Branch-and-bound node count (`bb_nodes`) via `MOI.NodeCount()`
- CSV export: Objective bound tracking via `JuMP.objective_bound()`
- CSV export: Detailed timing breakdowns (master, callback, subproblem, ML training, DBSCAN)
- CSV export: Cut filtering effectiveness metrics (`benders_cuts_found` vs `benders_cuts_added`)
- CSV export: Subproblem solve count (`benders_subproblems_solved`)
- Comprehensive solve statistics for cluster experiment analysis
- Exported `compute_effective_limit` and `create_selection_strategy` functions for advanced usage

### Changed
- DBSCAN clustering: Replaced 73-line manual implementation with `Clustering.jl` library
- Default diversity threshold: Reduced from 0.3 to 0.2 for more permissive clustering
- Cut filtering: Now uses standardized `dbscan()` function with precomputed distance matrix
- Code quality: Reduced `select_cuts_dbscan()` from 73 to 48 lines
- Subproblem selection: Improved adaptive cut limit strategy implementation
- Settings: Enhanced configuration handling for adaptive strategies

### Fixed
- Critical bug: Benders callback now exits if not in MIPSOL node
- DBSCAN implementation: Eliminated potential bugs by using well-tested library code

## [0.5.0] - 2026-01-06

### Added
- Machine learning-based subproblem prioritization (optional, 6th scoring component)
- 17-feature ML model with online logistic regression
- Graph-based n-hop neighborhood feature extraction (topology-aware)
- Feature normalization using z-scores (Welford's online algorithm)
- Average solve time as 17th feature (temporal difficulty signal)
- ML performance metrics tracking (accuracy, precision, recall, F1-score)
- Confidence bin analysis for prediction calibration
- Comprehensive ML methodology documentation

### Changed
- Scoring system expanded to 6 components (added ML prediction)
- ML model uses feature normalization to prevent sigmoid saturation
- Reduced learning rate from 0.01 to 0.005 for stability
- Increased regularization from 0.001 to 0.01 to prevent overfitting
- `SubproblemScore` now tracks `total_solve_time` for ML features
- `update_subproblem_score!()` accepts solve_time parameter
- Feature extraction uses n-hop neighborhoods instead of demand-based zones

### Fixed
- Binary ML predictions (0 or 1) resolved via feature normalization
- Feature scale mismatch causing sigmoid saturation

## [0.4.0] - 2025-12-29

### Added
- DBSCAN-based cut filtering with diversity selection using medoids
- Filtered reliability scoring component (tracks cuts actually added vs generated)
- Distance matrix computation using Jaccard distance on coefficient support
- Timing output for DBSCAN clustering operations

### Changed
- Scoring system expanded to 5 components: violation, reliability, filtered_reliability, total_share, stabilization
- Default scoring weights: [0.05, 0.0, 0.8, 0.05, 0.1] (prioritizes filtered reliability)
- Cut filtering strategies: NoFiltering, DiversityFiltering, EfficacyFiltering, HybridFiltering

### Dependencies
- Added Clustering.jl v0.15.8 for DBSCAN implementation
- Added Distances.jl v0.10.12 for distance metrics

## [0.3.1] - 2025-12-28

### Fixed
- Package test suite now compatible with `Pkg.test()` for GitLab CI pipeline
- Test suite uses Settings structure correctly (removed deprecated `max_cuts_per_iteration` parameter)

### Changed
- Disabled `test_benders_cut_limit.jl` (requires refactoring for new settings API)

## [0.3.0] - 2025-12-28

### Added
- Multi-criteria subproblem scoring with 4 components (violation, reliability, total_share, stabilization)
- Advanced subproblem selection with multiple stopping criteria (consecutive misses, score threshold, time limits)
- Nested `Limit` structs for cleaner settings API
- Template-based configuration loading with validation for unknown keys
- Verbose per-subproblem output with accuracy metrics
- Stabilization rounds with configurable frequency

### Changed
- Settings always load `default.toml` first, then merge user overrides
- Scoring updates consolidated into `update_scores_for_iteration!()` function
- Improved verbose output formatting with consistent indentation

### Fixed
- Critical bug: stopping criteria now only apply after at least one cut per iteration (prevents premature termination)
- TOML parsing: simple parameters must precede nested tables
- Missing `compute_scaled_scores!()` call before scenario ordering

### Removed
- Deprecated `r_branch_switch` scoring component
- Legacy settings fields (`subproblem_selection`, `cut_selection`, `cut_selection_k`, `cut_selection_threshold`)

## [0.2.2] - 2025-12-20

### Added
- CSV compilation tool `compile_instance_csv.sh` to merge multiple configuration results per instance

### Fixed
- HTCondor job execution by using direct Julia binary instead of bash wrapper (fixes empty .out/.err files)
- Solve time measurement now uses `JuMP.solve_time()` directly

### Changed
- Improved `test_instance.jl` code style with proper Julia function signatures and docstrings
- Enabled automatic CSV file transfer in HTCondor template

## [0.2.1] - 2025-12-19

### Added
- HTCondor testing framework in `check/` directory with batch submission and CSV output
- Subproblem ordering strategies: `"none"`, `"score"`, and `"random"`
- Configurable `scoring_weights` parameter (default: `[0.3, 0.3, 0.3, 0.1, 0.01]`)
- Eight pre-configured test settings files for different cut limits and ordering strategies

### Changed
- Replaced `use_subproblem_ordering` boolean with `subproblem_ordering` string enum
- Updated `solve_benders()` and `compute_scaled_scores!()` signatures for new parameters

### Fixed
- `Package Pkg not found` error in test common utilities

## [0.2.0] - 2025-12-17

### Added
- Adaptive subproblem ordering with score-based prioritization
- `max_cuts_per_iteration` parameter to limit cuts per iteration
- `test_cut_limit_comparison.jl` for performance benchmarking
- `SubproblemScore` struct for tracking scoring metrics
- REPL-friendly tests with `isdefined` guards

### Changed
- Cut limit enforcement now applies per-iteration instead of globally
- All tests updated for REPL compatibility
- Updated README with performance benchmarks

### Fixed
- Base case scenario bug (empty array vs `[OutageScenario(0, Int[])]`)
- `SubproblemScore` dictionary key types (String to Int)
- Scenario generation to support `-1` for all single-link outages
- Constant redefinition protection for REPL usage

### Performance
- Discovered optimal `max_cuts_per_iteration=5` provides 23% speedup over compact formulation
- Abilene benchmark: Benders(5) at 3.27s vs Compact at 4.27s

## [0.1.0] - 2025-12-17

### Added
- Initial Benders decomposition implementation for survivable network design
- SNDlib network format parsing
- Outage scenario generation and sampling
- Compact MIP formulation for validation
- Farkas feasibility cuts using capacity and flow conservation duals
- TOML configuration file support
- Test suite comparing Benders and compact models
- **Cut Validation**: Optional validation of feasibility cuts before adding to master problem

### Verified
- All models produce identical optimal solutions
- Tested with 0, 1, 3, and 10 outage scenarios on abilene network
- Correct handling of infeasible subproblems via Farkas duals
