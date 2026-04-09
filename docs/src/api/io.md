# I/O Functions API

## Network Loading

```@docs
read_sndlib_network
```

### Network Structure

The `SNDlibNetwork` struct contains:

```julia
struct SNDlibNetwork
    network_structure::NetworkStructure
    demands::Dict{String, Demand}
end

struct NetworkStructure
    nodes::Dict{String, Node}
    links::Dict{String, Link}
end

struct Node
    id::String
    x_coord::Union{Float64, Nothing}
    y_coord::Union{Float64, Nothing}
end

struct Link
    id::String
    source::String
    target::String
    preinstalled_capacity::Union{Float64, Nothing}
    additional_modules::Vector{Tuple{Float64, Float64}}  # (capacity, cost)
    setup_cost::Float64
    routing_cost::Float64
end

struct Demand
    id::String
    source::String
    target::String
    demand_value::Float64
end
```

## Scenario Generation

```@docs
generate_outage_scenarios
OutageScenario
```

### Example: Generate Scenarios

```julia
# Load network
network = read_sndlib_network("data/sndlib/abilene.xml")

# All single-link failures (include base case)
scenarios_all = generate_outage_scenarios(network; 
                                         num_scenarios=-1, 
                                         include_base_case=true)
println("Total scenarios: $(length(scenarios_all))")  # 16 for abilene (15 links + base)

# Sample 5 random failures (no base case)
scenarios_sample = generate_outage_scenarios(network;
                                            num_scenarios=5,
                                            include_base_case=false,
                                            seed=42)

# Custom scenarios
custom = [
    OutageScenario(1, [1, 3]),      # Links 1 and 3 fail
    OutageScenario(2, [2]),         # Only link 2 fails
    OutageScenario(3, Int[])        # Base case (no failures)
]
```

## Settings

```@docs
read_settings
Settings
```

### Settings Structure

```julia
struct Settings
    # Solver
    solver::String
    time_limit::Int
    
    # Subproblem selection
    subproblem_ordering::String
    scoring_weights::Vector{Float64}
    scoring_random_seed::Int
    consecutive_miss::Limit
    min_score_threshold::ScoreThreshold
    iteration_time_limit::IterationTimeLimit
    cut_limit::CutLimit
    
    # Stabilization
    stabilization_frequency::Int
    
    # Output
    validate_cuts::Bool
    subproblem_verbose::Bool
    subproblem_verbose_cuts_only::Bool
end

struct Limit
    mode::String        # "absolute" or "relative"
    absolute::Int
    relative::Float64
end

struct ScoreThreshold
    enabled::Bool
    threshold::Float64
end

struct IterationTimeLimit
    enabled::Bool
    time_seconds::Float64
end

struct CutLimit
    mode::String        # "static" or "adaptive"
    static::Int
    adaptive::AdaptiveParams
end
```

### Configuration Loading

The configuration system:

1. Always loads `settings/default.toml` first
2. Merges user-specified settings on top
3. Validates all keys (reports unknown parameters)
4. Returns complete `Settings` struct

```julia
# Use defaults
settings = read_settings()

# Override with custom file
settings = read_settings("my_settings.toml")

# Access settings
println("Solver: $(settings.solver)")
println("Cut limit: $(settings.cut_limit.static)")
println("Scoring weights: $(settings.scoring_weights)")
```

## Solver Configuration

```@docs
get_optimizer
```

### Supported Solvers

- **Gurobi**: Commercial solver with excellent performance (required)

```julia
# Using Gurobi
using Gurobi
env = Gurobi.Env()
optimizer = () -> Gurobi.Optimizer(env)

# From settings
settings = read_settings("settings/default.toml")
optimizer = get_optimizer(settings)
```

## Example: Complete Workflow

```julia
using BendersNetworkDesign

# 1. Load network
network = read_sndlib_network("data/sndlib/abilene.xml")
println("Nodes: $(length(network.network_structure.nodes))")
println("Links: $(length(network.network_structure.links))")
println("Demands: $(length(network.demands))")

# 2. Generate scenarios
scenarios = generate_outage_scenarios(network; 
                                     num_scenarios=-1,
                                     include_base_case=false)
println("Scenarios: $(length(scenarios))")

# 3. Load settings
settings = read_settings("settings/default.toml")

# 4. Get optimizer
optimizer = get_optimizer(settings)

# 5. Solve
result = solve_benders(network;
                      optimizer=optimizer,
                      outage_scenarios=scenarios,
                      settings=settings)

# 6. Display results
println("Objective: $(result.objective_value)")
println("Status: $(result.status)")
println("Iterations: $(result.iterations)")
println("Cuts: $(result.total_cuts_added)")
println("Subproblem time: $(result.subproblem_time)s")
```
