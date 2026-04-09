# Models API

## Main Functions

```@docs
solve_benders
solve_compact_model
```

## Benders Decomposition

### Master Problem

The master problem includes:
- First-stage module installation variables `y[l,m]`
- Base case flow variables `f_base[d,a]`
- Recourse variable `θ` for cut accumulation

### Subproblem

```@docs
build_subproblem
update_subproblem!
reset_subproblem!
```

### Cut Generation

```@docs
build_benders_cut
```

## Solution Structure

Both `solve_benders` and `solve_compact_model` return a named tuple:

```julia
(
    objective_value::Float64,       # Optimal objective value
    y_solution::Dict,               # Module installation decisions
    model::JuMP.Model,              # Solved model
    status::MOI.TerminationStatus,  # Solver termination status
    iterations::Int,                # Number of iterations (Benders only)
    total_cuts_added::Int,          # Total cuts added (Benders only)
    subproblem_time::Float64        # Time in subproblems (Benders only)
)
```

## Example Usage

### Basic Benders Solve

```julia
using BendersNetworkDesign
using Gurobi

network = read_sndlib_network("data/sndlib/abilene.xml")
scenarios = generate_outage_scenarios(network; include_base_case=false)
settings = read_settings("settings/default.toml")

env = Gurobi.Env()
result = solve_benders(
    network;
    optimizer = () -> Gurobi.Optimizer(env),
    outage_scenarios = scenarios,
    settings = settings
)

println("Objective: $(result.objective_value)")
println("Status: $(result.status)")
println("Iterations: $(result.iterations)")
println("Cuts added: $(result.total_cuts_added)")
```

### Compact Model (for validation)

```julia
result_compact = solve_compact_model(
    network;
    optimizer = () -> Gurobi.Optimizer(env),
    outage_scenarios = scenarios,
    settings = settings
)

# Compare with Benders
@assert isapprox(result.objective_value, result_compact.objective_value, rtol=1e-4)
```

### Custom Subproblem Workflow

```julia
# Build once
sp = build_subproblem(network, demands; optimizer)

# Reuse for multiple scenarios
for scenario in scenarios
    y_values = Dict((l,m) => 1.0 for l in links for m in modules)
    failed_indices = Set(scenario.failed_link_indices)
    
    update_subproblem!(sp, y_values, link_modules, failed_indices)
    optimize!(sp.model)
    
    # Process results...
    
    reset_subproblem!(sp)
end
```
