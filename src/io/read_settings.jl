using TOML
using JuMP

# Optional solver imports
const GUROBI_AVAILABLE = try
    using Gurobi
    true
catch
    false
end

"""
    Limit

Represents a limit parameter that can be absolute or relative.

# Fields
- `mode`: "absolute" or "relative"
- `absolute`: Fixed integer value (used when mode="absolute")
- `relative`: Fraction of total (used when mode="relative")
"""
struct Limit
    mode::String
    absolute::Int
    relative::Float64
end

"""
    Settings

Configuration settings loaded from TOML file.
"""
struct Settings
    solver::Symbol
    optimizer
    model_type::String
    # Scenario generation
    num_outage_scenarios::Int
    outage_sampling_seed::Union{Int,Nothing}
    contingency_k::Int
    time_limit::Float64
    # Subproblem scoring
    subproblem_ordering::String
    scoring_weights::Vector{Float64}
    scoring_random_seed::Union{Int,Nothing}
    scale_score::Bool
    max_fractional_iterations_at_root::Int
    # Subproblem selection - static
    selection_strategy::String
    cut_limit::Limit
    solve_limit::Limit
    consecutive_miss::Limit
    min_score_threshold::Float64
    iteration_time_limit::Float64
    score_initialization_enabled::Bool
    stabilization_frequency::Int
    root_node_stabilization::Int
    # Subproblem selection - oracle
    oracle_mode::String
    oracle_filepath::String
    # Subproblem selection - adaptive
    adaptive_mode::String
    # Phase-based
    adaptive_phase_large_gap::Float64
    adaptive_phase_medium_gap::Float64
    adaptive_phase_early_cuts::Int
    adaptive_phase_middle_cuts::Int
    adaptive_phase_late_cuts::Int
    # Progress-based
    adaptive_progress_base_cuts::Int
    adaptive_progress_min_cuts::Int
    adaptive_progress_max_cuts::Int
    adaptive_progress_factor::Float64
    adaptive_progress_low_threshold::Float64
    adaptive_progress_high_threshold::Float64
    adaptive_progress_stagnation_rounds::Int
    adaptive_progress_movement_factor::Float64
    adaptive_progress_stagnation_factor::Float64
    # Time-balance
    adaptive_time_base_cuts::Int
    adaptive_time_min_cuts::Int
    adaptive_time_max_cuts::Int
    adaptive_time_master_threshold::Float64
    adaptive_time_subproblem_threshold::Float64
    adaptive_time_decrease_factor::Float64
    adaptive_time_increase_factor::Float64
    # Prediction-based
    adaptive_prediction_learning_rate::Float64
    adaptive_prediction_regularization::Float64
    adaptive_prediction_history_decay::Float64
    adaptive_prediction_default_proportion::Float64
    adaptive_prediction_min_proportion::Float64
    adaptive_prediction_max_proportion::Float64
    adaptive_prediction_min_training_rate::Float64
    # Machine Learning
    ml_mode::String  # "single" or "multi"
    ml_khop_distance::Int  # k-hop neighborhood radius for multi-regressor features
    ml_learning_rate::Float64
    ml_regularization::Float64
    ml_decision_threshold::Float64  # Classification threshold (lower = higher recall, default 0.3)
    ml_positive_class_weight::Float64  # Positive class weight in loss (higher = higher recall, default 3.0)
    # Cut filtering
    cut_filtering_strategy::String
    cut_filtering_max_cuts::Int
    cut_filtering_efficacy_norm::String
    cut_filtering_diversity_threshold::Float64
    cut_filtering_hybrid_weights::Vector{Float64}
    # Logging
    statistics::Bool
    ml_statistics::Bool
    subproblem_log::Bool
    subproblem_log_success::Bool
    print_solution::Bool
    # Debug
    validate_cuts::Bool
    # ML model persistence
    ml_model_write::Bool
    ml_model_read::Bool
end

"""
    read_settings(filepath::String)

Read settings from a TOML file using template-based loading.

Loads default.toml as template with all parameters, then merges
user-specified overrides from the provided filepath.

Parameters:
- filepath: Path to the TOML settings file (overrides)

Returns:
- Settings struct with parsed configuration

Throws:
- ErrorException if an unknown setting key is found in the user file
"""
function read_settings(filepath::String)::Settings
    # First, load the default template
    this_dir = @__DIR__
    default_file = joinpath(dirname(dirname(this_dir)), "settings", "default.toml")
    
    if !isfile(default_file)
        error("Default settings template not found: $default_file")
    end
    
    # Parse default config as template
    config = TOML.parsefile(default_file)
    
    # Merge user overrides if file exists and is different from default
    if isfile(filepath) && abspath(filepath) != abspath(default_file)
        if !isfile(filepath)
            error("Settings file not found: $filepath")
        end
        
        user_config = TOML.parsefile(filepath)
        merge_configs!(config, user_config, filepath)
    end
    
    return parse_settings(config)
end

"""
    merge_configs!(base::Dict, override::Dict, filepath::String)

Recursively merge override config into base config.

Throws an error if any key in override is not present in base (unknown setting).

Parameters:
- base: Base configuration (from default.toml)
- override: Override configuration (from user file)
- filepath: Path to user file (for error messages)
"""
function merge_configs!(base::Dict, override::Dict, filepath::String)
    for (key, value) in override
        if !haskey(base, key)
            error("Unknown setting key '$key' in file: $filepath\nValid keys at this level: $(join(sort(collect(keys(base))), ", "))")
        end
        
        if isa(base[key], Dict) && isa(value, Dict)
            merge_configs!(base[key], value, filepath)
        else
            base[key] = value
        end
    end
end

"""
    parse_settings(config::Dict) -> Settings

Parse TOML config dictionary into Settings struct.

Assumes config is complete (all keys present from default.toml).
No default values are provided here.
"""
function parse_settings(config::Dict)::Settings
    # Parse solver
    solver_str = config["SOLVER"]["SOLVER"]
    solver = Symbol(solver_str)
    optimizer = get_optimizer(solver)
    
    # Parse model type
    model_config = config["MODEL"]
    model_type = model_config["model_type"]
    
    # Parse scenarios
    scenarios = config["SCENARIOS"]
    num_outages = scenarios["num_outage_scenarios"]
    seed_value = scenarios["outage_sampling_seed"]
    seed = (seed_value === nothing || seed_value == "nothing") ? nothing : seed_value
    contingency_k = get(scenarios, "contingency_k", 1)
    
    # Parse solver parameters
    solver_config = config["SOLVER"]
    time_limit = solver_config["time_limit"]
    
    # Parse Benders decomposition settings
    benders = config["BENDERS"]
    
    # Subproblem scoring
    scoring = benders["SUBPROBLEM_SCORING"]
    ordering = scoring["ordering"]
    max_fractional_iterations_at_root = get(scoring, "max_fractional_iterations_at_root", 5)
    
    # Get strategy-specific parameters
    score_config = scoring["score"]
    weights = score_config["weights"]
    scale_score = get(score_config, "scale_score", true)
    
    random_config = scoring["random"]
    random_seed_value = random_config["seed"]
    random_seed = (random_seed_value === nothing || random_seed_value == "nothing") ? nothing : random_seed_value
    
    # Subproblem selection
    selection = benders["SUBPROBLEM_SELECTION"]
    selection_strategy = selection["strategy"]
    score_init_enabled = selection["score_initialization_enabled"]
    stab_freq = selection["stabilization_frequency"]
    root_node_stab = get(selection, "root_node_stabilization", 0)
    
    # Get static strategy parameters
    static_config = selection["static"]
    
    # Parse cut limit
    cut_limit_config = static_config["cut_limit"]
    cut_limit = Limit(
        cut_limit_config["mode"],
        cut_limit_config["absolute"],
        cut_limit_config["relative"]
    )
    
    # Parse solve limit
    solve_limit_config = static_config["solve_limit"]
    solve_limit = Limit(
        solve_limit_config["mode"],
        solve_limit_config["absolute"],
        solve_limit_config["relative"]
    )
    
    # Parse consecutive miss limit
    miss_config = static_config["consecutive_miss"]
    consecutive_miss = Limit(
        miss_config["mode"],
        miss_config["absolute"],
        miss_config["relative"]
    )
    
    min_score = static_config["min_score_threshold"]
    iter_time_limit = static_config["iteration_time_limit"]
    
    # Parse oracle strategy parameters
    oracle_config = selection["oracle"]
    oracle_mode = oracle_config["mode"]
    # Default filepath: check/oracle/<instance_name>.csv (set later when network is loaded)
    oracle_filepath = get(oracle_config, "filepath", "")
    
    # Parse adaptive strategy parameters
    adaptive_config = selection["adaptive"]
    adaptive_mode = adaptive_config["mode"]
    
    # Phase-based parameters
    phase_config = adaptive_config["phase_based"]
    adaptive_phase_large_gap = phase_config["large_gap_threshold"]
    adaptive_phase_medium_gap = phase_config["medium_gap_threshold"]
    adaptive_phase_early_cuts = phase_config["early_phase_cuts"]
    adaptive_phase_middle_cuts = phase_config["middle_phase_cuts"]
    adaptive_phase_late_cuts = phase_config["late_phase_cuts"]
    
    # Progress-based parameters
    progress_config = adaptive_config["progress_based"]
    adaptive_progress_base = progress_config["base_cuts"]
    adaptive_progress_min = progress_config["min_cuts"]
    adaptive_progress_max = progress_config["max_cuts"]
    adaptive_progress_factor = progress_config["adaptation_factor"]
    adaptive_progress_low = progress_config["low_improvement_threshold"]
    adaptive_progress_high = progress_config["high_improvement_threshold"]
    adaptive_progress_stag = progress_config["stagnation_rounds"]
    adaptive_progress_movement = progress_config["movement_factor"]
    adaptive_progress_stagnation_factor = progress_config["stagnation_factor"]
    
    # Time-balance parameters
    time_config = adaptive_config["time_balance"]
    adaptive_time_base = time_config["base_cuts"]
    adaptive_time_min = time_config["min_cuts"]
    adaptive_time_max = time_config["max_cuts"]
    adaptive_time_master = time_config["master_dominated_threshold"]
    adaptive_time_subproblem = time_config["subproblem_dominated_threshold"]
    adaptive_time_decrease = time_config["decrease_factor"]
    adaptive_time_increase = time_config["increase_factor"]
    
    # Prediction-based parameters
    prediction_config = adaptive_config["prediction_based"]
    adaptive_prediction_lr = prediction_config["learning_rate"]
    adaptive_prediction_reg = prediction_config["regularization"]
    adaptive_prediction_decay = prediction_config["history_decay"]
    adaptive_prediction_default = prediction_config["default_proportion"]
    adaptive_prediction_min = prediction_config["min_proportion"]
    adaptive_prediction_max = prediction_config["max_proportion"]
    adaptive_prediction_min_train = prediction_config["min_training_rate"]
    
    # === Machine Learning ===
    ml_config = get(benders, "ML", Dict())
    ml_mode = get(ml_config, "mode", "single")
    ml_khop_distance = get(ml_config, "khop_distance", 2)
    ml_learning_rate = get(ml_config, "learning_rate", 0.02)
    ml_regularization = get(ml_config, "regularization", 0.001)
    ml_decision_threshold = get(ml_config, "decision_threshold", 0.3)  # Lower = higher recall
    ml_positive_class_weight = get(ml_config, "positive_class_weight", 3.0)  # Higher = higher recall
    
    # === Cut Filtering ===
    filtering = benders["CUT_FILTERING"]
    filtering_strategy = filtering["strategy"]
    filtering_max_cuts = filtering["max_cuts"]
    efficacy_norm = filtering["efficacy_norm"]
    diversity_threshold = filtering["diversity_threshold"]
    hybrid_weights = filtering["hybrid_weights"]
    
    # === Logging ===
    logging = config["LOGGING"]
    
    # === Debug ===
    debug = get(benders, "DEBUG", Dict())
    
    return Settings(
        solver, optimizer, model_type,
        num_outages, seed, contingency_k, time_limit,
        ordering, weights, random_seed, scale_score, max_fractional_iterations_at_root,
        selection_strategy, cut_limit, solve_limit, consecutive_miss, min_score, iter_time_limit, score_init_enabled, stab_freq, root_node_stab,
        oracle_mode, oracle_filepath,
        adaptive_mode,
        adaptive_phase_large_gap, adaptive_phase_medium_gap,
        adaptive_phase_early_cuts, adaptive_phase_middle_cuts, adaptive_phase_late_cuts,
        adaptive_progress_base, adaptive_progress_min, adaptive_progress_max, adaptive_progress_factor,
        adaptive_progress_low, adaptive_progress_high, adaptive_progress_stag,
        adaptive_progress_movement, adaptive_progress_stagnation_factor,
        adaptive_time_base, adaptive_time_min, adaptive_time_max,
        adaptive_time_master, adaptive_time_subproblem, adaptive_time_decrease, adaptive_time_increase,
        adaptive_prediction_lr, adaptive_prediction_reg, adaptive_prediction_decay,
        adaptive_prediction_default, adaptive_prediction_min, adaptive_prediction_max, adaptive_prediction_min_train,
        ml_mode, ml_khop_distance, ml_learning_rate, ml_regularization, ml_decision_threshold, ml_positive_class_weight,
        filtering_strategy, filtering_max_cuts, efficacy_norm, diversity_threshold, hybrid_weights,
        # Logging
        get(logging, "statistics", true),
        get(logging, "ml_statistics", true),
        get(logging, "subproblem_log", false),
        get(logging, "subproblem_log_success", false),
        get(logging, "print_solution", false),
        # Debug
        get(debug, "validate_cuts", false),
        # ML persistence
        get(get(benders, "ML", Dict()), "model_write", false),
        get(get(benders, "ML", Dict()), "model_read", false)
    )
end

"""
    get_optimizer(solver::Symbol)

Get the optimizer constructor function for the specified solver.

Parameters:
- solver: Solver symbol (:Gurobi)

Returns:
- Function that creates a configured optimizer instance
"""
function get_optimizer(solver::Symbol)::Function
    if solver == :Gurobi
        if !GUROBI_AVAILABLE
            error("Gurobi not available. Please install Gurobi.jl and ensure you have a valid license.")
        else
            # Return function that creates Gurobi optimizer with settings
            return () -> begin
                env = Gurobi.Env()
                Gurobi.Optimizer(env)
            end
        end
    else
        error("Unsupported solver: $solver. Only :Gurobi is supported.")
    end
end

"""
    read_settings()

Read settings from the default location (settings/default.toml).

Returns:
- Settings struct with parsed configuration
"""
function read_settings()::Settings
    # Try to find settings file relative to the project root
    this_dir = @__DIR__
    # Go up from src/io to project root, then to settings
    settings_file = joinpath(dirname(dirname(this_dir)), "settings", "default.toml")
    return read_settings(settings_file)
end

"""
    print_settings(settings)

Print settings in a formatted, human-readable way.
"""
function print_settings(settings::Settings)
    println("\n╔════════════════════════════════════════════════════════════════════════╗")
    println("║                        BENDERS ALGORITHM SETTINGS                      ║")
    println("╠════════════════════════════════════════════════════════════════════════╣")
    
    # Subproblem Scoring
    println("║ SUBPROBLEM SCORING                                                     ║")
    println("║ ──────────────────────────────────────────────────────────────────── ║")
    println("║   Ordering Strategy: $(rpad(settings.subproblem_ordering, 44))║")
    
    if settings.subproblem_ordering == "score"
        w = settings.scoring_weights
        println("║   Scoring Weights:                                                     ║")
        if length(w) >= 1
            println("║     - Violation (w_v):           $(rpad(string(w[1]), 33))║")
        end
        if length(w) >= 2
            println("║     - Reliability (w_r):         $(rpad(string(w[2]), 33))║")
        end
        if length(w) >= 3
            println("║     - Reliability Filt. (w_rf):  $(rpad(string(w[3]), 33))║")
        end
        if length(w) >= 4
            println("║     - Total Share (w_t):         $(rpad(string(w[4]), 33))║")
        end
        if length(w) >= 5
            println("║     - Stabilization (w_z):       $(rpad(string(w[5]), 33))║")
        end
        if length(w) >= 6
            println("║     - ML Prediction (w_ml):      $(rpad(string(w[6]), 33))║")
        end
        println("║   Scale Score: $(rpad(string(settings.scale_score), 52))║")
    elseif settings.subproblem_ordering == "random"
        seed_str = isnothing(settings.scoring_random_seed) ? "None (non-deterministic)" : string(settings.scoring_random_seed)
        println("║   Random Seed: $(rpad(seed_str, 52))║")
    end
    
    println("╠════════════════════════════════════════════════════════════════════════╣")
    
    # Subproblem Selection
    println("║ SUBPROBLEM SELECTION                                                   ║")
    println("║ ──────────────────────────────────────────────────────────────────── ║")
    
    if settings.selection_strategy == "adaptive"
        println("║   Strategy: Adaptive ($(settings.adaptive_mode))                                   ║")
        println("║                                                                        ║")
        
        if settings.adaptive_mode == "phase_based"
            println("║   Phase-Based Adaptation:                                              ║")
            println("║     - Large gap threshold:  $(rpad(string(settings.adaptive_phase_large_gap), 37))║")
            println("║     - Medium gap threshold: $(rpad(string(settings.adaptive_phase_medium_gap), 37))║")
            println("║     - Early phase cuts:     $(rpad(string(settings.adaptive_phase_early_cuts), 37))║")
            println("║     - Middle phase cuts:    $(rpad(string(settings.adaptive_phase_middle_cuts), 37))║")
            println("║     - Late phase cuts:      $(rpad(string(settings.adaptive_phase_late_cuts), 37))║")
        elseif settings.adaptive_mode == "progress_based"
            println("║   Progress-Based Adaptation:                                           ║")
            println("║     - Base cuts:            $(rpad(string(settings.adaptive_progress_base_cuts), 37))║")
            println("║     - Min/Max cuts:         $(rpad(string(settings.adaptive_progress_min_cuts) * "/" * string(settings.adaptive_progress_max_cuts), 37))║")
            println("║     - Adaptation factor:    $(rpad(string(settings.adaptive_progress_factor), 37))║")
            println("║     - Low imp. threshold:   $(rpad(string(settings.adaptive_progress_low_threshold), 37))║")
            println("║     - High imp. threshold:  $(rpad(string(settings.adaptive_progress_high_threshold), 37))║")
            println("║     - Stagnation rounds:    $(rpad(string(settings.adaptive_progress_stagnation_rounds), 37))║")
        elseif settings.adaptive_mode == "time_balance"
            println("║   Time-Balance Adaptation:                                             ║")
            println("║     - Base cuts:            $(rpad(string(settings.adaptive_time_base_cuts), 37))║")
            println("║     - Min/Max cuts:         $(rpad(string(settings.adaptive_time_min_cuts) * "/" * string(settings.adaptive_time_max_cuts), 37))║")
            println("║     - Master threshold:     $(rpad(string(settings.adaptive_time_master_threshold), 37))║")
            println("║     - Subproblem threshold: $(rpad(string(settings.adaptive_time_subproblem_threshold), 37))║")
            println("║     - Decrease factor:      $(rpad(string(settings.adaptive_time_decrease_factor), 37))║")
            println("║     - Increase factor:      $(rpad(string(settings.adaptive_time_increase_factor), 37))║")
        end
        println("║                                                                        ║")
        println("║   Score Threshold: $(rpad(string(settings.min_score_threshold), 46))║")
        println("║   Iteration Time Limit: $(rpad(string(settings.iteration_time_limit) * " seconds", 41))║")
        println("║   Stabilization Frequency: $(rpad(string(settings.stabilization_frequency) * " iterations", 38))║")
    else
        println("║   Strategy: Static Limits                                              ║")
        println("║                                                                        ║")
        println("║   Cut Limit:                                                           ║")
        println("║     - Mode:      $(rpad(settings.cut_limit.mode, 52))║")
        println("║     - Absolute:  $(rpad(string(settings.cut_limit.absolute), 52))║")
        println("║     - Relative:  $(rpad(string(settings.cut_limit.relative), 52))║")
        println("║                                                                        ║")
        println("║   Consecutive Miss Limit:                                              ║")
        println("║     - Mode:      $(rpad(settings.consecutive_miss.mode, 52))║")
        println("║     - Absolute:  $(rpad(string(settings.consecutive_miss.absolute), 52))║")
        println("║     - Relative:  $(rpad(string(settings.consecutive_miss.relative), 52))║")
        println("║                                                                        ║")
        println("║   Score Threshold: $(rpad(string(settings.min_score_threshold), 46))║")
        println("║   Iteration Time Limit: $(rpad(string(settings.iteration_time_limit) * " seconds", 41))║")
        println("║   Stabilization Frequency: $(rpad(string(settings.stabilization_frequency) * " iterations", 38))║")
    end
    
    println("╠════════════════════════════════════════════════════════════════════════╣")
    
    # Cut Filtering
    println("║ CUT FILTERING                                                          ║")
    println("║ ──────────────────────────────────────────────────────────────────── ║")
    println("║   Strategy: $(rpad(settings.cut_filtering_strategy, 57))║")
    
    println("╠════════════════════════════════════════════════════════════════════════╣")
    
    # Solver and Validation
    println("║ SOLVER AND VALIDATION                                                  ║")
    println("║ ──────────────────────────────────────────────────────────────────── ║")
    println("║   Optimizer: $(rpad(string(settings.solver), 54))║")
    println("║   Validate Cuts: $(rpad(string(settings.validate_cuts), 50))║")
    
    println("╚════════════════════════════════════════════════════════════════════════╝\n")
end
