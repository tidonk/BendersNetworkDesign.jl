"""
Subproblem data structures and operations for Benders decomposition.

Handles construction, updating, and cut generation from subproblems.
"""

using JuMP
using Statistics

"""
    SubproblemData

Stores subproblem structure with constraint references for efficient dual extraction.

# Fields
- `model`: JuMP model for the subproblem LP
- `f`: Flow variables indexed by (demand_id, arc_id)
- `flow_conservation`: Flow conservation constraint refs indexed by (demand_id, node_id)
- `capacity_constraints`: Capacity constraint refs indexed by link_id
- `base_capacities`: Backup of capacity RHS values for reset
- `nodes`: List of node IDs
- `links`: List of link IDs  
- `demands`: List of demand IDs
"""
struct SubproblemData
    model::Model
    f::Dict{Tuple{String,String},VariableRef}
    flow_conservation::Dict{Tuple{String,String},ConstraintRef}
    capacity_constraints::Dict{String,ConstraintRef}
    base_capacities::Dict{String,Float64}
    nodes::Vector{String}
    links::Vector{String}
    demands::Vector{String}
end

"""
    build_subproblem(network, demands; optimizer) -> SubproblemData

Construct reusable Benders subproblem LP for routing given fixed capacities.

Configures Gurobi with:
- DualReductions=0: Required for extracting duals/rays from infeasible problems
- InfUnbdInfo=1: Provides information to distinguish infeasible vs unbounded

# Arguments
- `network`: SNDlib network structure
- `demands`: Dict{String,Float64} mapping demand_id to demand_value
- `optimizer`: JuMP optimizer constructor

# Returns
SubproblemData structure containing model, variables, and constraint references
"""
function build_subproblem(network, demands::Dict{String,Float64}; optimizer)::SubproblemData
    nodes = network.network_structure.nodes
    links = network.network_structure.links
    
    N = collect(keys(nodes))
    L = collect(keys(links))
    D = collect(intersect(keys(network.demands), keys(demands)))
    
    model = Model(optimizer)
    
    # Configure Gurobi parameters for Benders subproblem
    # DualReductions must be disabled to extract rays from infeasible problems
    try
        set_attribute(model, "DualReductions", 0)
        set_attribute(model, "InfUnbdInfo", 1)
        #set_attribute(model, "LPWarmStart", 0)
        set_attribute(model, "OutputFlag", 0)  # Disable solver output
    catch
        @warn "Failed to set solver attributes (may not be using Gurobi)"
    end
    
    # Flow variables for each demand on each arc
    f = Dict{Tuple{String,String},VariableRef}()
    for d in D
        for l in L
            f[(d, "$(l)_fwd")] = @variable(model, lower_bound=0, base_name="f")
            f[(d, "$(l)_bwd")] = @variable(model, lower_bound=0, base_name="f")
        end
    end
    
    arc_endpoints(link_id) = begin
        link = links[link_id]
        (link.source, link.target)
    end
    
    # Flow conservation constraints at each node for each demand
    flow_conservation = Dict{Tuple{String,String},ConstraintRef}()
    
    for d in D
        demand = network.demands[d]
        src, tgt = demand.source, demand.target
        demand_val = demands[d]
        
        for n in N
            outgoing = AffExpr(0.0)
            incoming = AffExpr(0.0)
            
            for l in L
                s, t = arc_endpoints(l)
                if s == n
                    add_to_expression!(outgoing, f[(d, "$(l)_fwd")])
                end
                if t == n
                    add_to_expression!(outgoing, f[(d, "$(l)_bwd")])
                end
                if t == n
                    add_to_expression!(incoming, f[(d, "$(l)_fwd")])
                end
                if s == n
                    add_to_expression!(incoming, f[(d, "$(l)_bwd")])
                end
            end
            
            net_flow = outgoing - incoming
            
            if n == src
                flow_conservation[(d, n)] = @constraint(model, net_flow == demand_val, base_name="flow")
            elseif n == tgt
                flow_conservation[(d, n)] = @constraint(model, net_flow == -demand_val, base_name="flow")
            else
                flow_conservation[(d, n)] = @constraint(model, net_flow == 0, base_name="flow")
            end
        end
    end
    
    # Capacity constraints (will be updated with actual capacities)
    capacity_constraints = Dict{String,ConstraintRef}()
    base_capacities = Dict{String,Float64}()
    
    for l in L
        total_flow = sum(f[(d, "$(l)_fwd")] for d in D) + sum(f[(d, "$(l)_bwd")] for d in D)
        capacity_constraints[l] = @constraint(model, total_flow <= 0.0, base_name="capacity")
        base_capacities[l] = 0.0
    end
    
    # Objective: feasibility problem (minimize 0)
    @objective(model, Min, 0.0)
    
    return SubproblemData(model, f, flow_conservation, capacity_constraints, base_capacities, N, L, D)
end

"""
    update_subproblem!(sp::SubproblemData, y_values, link_modules, failed_link_indices)

Update subproblem capacity constraints for a specific failure scenario.

# Arguments
- `sp`: Subproblem data structure
- `y_values`: Current master problem y solution (module installations)
- `link_modules`: Module specifications for each link
- `failed_link_indices`: Set of failed link indices (empty for base case)

Sets capacity to 0 for failed links, computes capacity from y_values for other links.
"""
function update_subproblem!(sp::SubproblemData, 
                           y_values::Dict{Tuple{String,Int},Float64}, 
                           link_modules::Dict{String,Vector{Tuple{Int,Float64,Float64}}}, 
                           failed_link_indices::Set{Int}=Set{Int}())::Nothing
    for (idx, l) in enumerate(sp.links)
        if idx in failed_link_indices
            # Failed link has zero capacity
            set_normalized_rhs(sp.capacity_constraints[l], 0.0)
        else
            # Compute total capacity from module installations
            mods = link_modules[l]
            total_capacity = sum(mods[m][2] * get(y_values, (l, m), 0.0) for m in eachindex(mods))
            set_normalized_rhs(sp.capacity_constraints[l], total_capacity)
            sp.base_capacities[l] = total_capacity
        end
    end
    return nothing
end

"""
    reset_subproblem!(sp::SubproblemData)

Reset subproblem to base state (restore capacities from last update).
"""
function reset_subproblem!(sp::SubproblemData)::Nothing
    for l in sp.links
        set_normalized_rhs(sp.capacity_constraints[l], sp.base_capacities[l])
    end
    return nothing
end

"""
    build_benders_cut(y_var, θ_var, link_modules, links, failed_link_indices, sp, network, demands)

Build complete Benders feasibility cut from subproblem duals.

Extracts Farkas duals from infeasible subproblem and constructs complete cut expression.
Returns (cut_lhs, cut_rhs) where the cut is: cut_lhs >= cut_rhs.

# Arguments
- `y_var`: Master problem y variables
- `θ_var`: Master problem theta variable
- `link_modules`: Module specifications
- `links`: List of link IDs
- `failed_link_indices`: Set of failed link indices
- `sp`: SubproblemData with solved infeasible subproblem
- `network`: SNDlibNetwork structure
- `demands`: Demand dictionary

# Returns
Tuple of (cut_lhs::AffExpr, cut_rhs::Float64) where cut_lhs >= cut_rhs is the cut
"""
function build_benders_cut(y_var, 
                          θ_var::VariableRef, 
                          link_modules::Dict{String,Vector{Tuple{Int,Float64,Float64}}}, 
                          links::Vector{String}, 
                          failed_link_indices::Set{Int},
                          sp::SubproblemData,
                          network::SNDlibNetwork,
                          demands::Dict{String,Float64})::Tuple{AffExpr, Float64}
    
    # Extract Farkas duals (capacity constraints)
    capacity_duals = Dict{String,Float64}()
    for (idx, l) in enumerate(links)
        if idx in failed_link_indices
            capacity_duals[l] = 0.0  # Failed links have zero capacity, dual doesn't matter
        else
            capacity_duals[l] = dual(sp.capacity_constraints[l])
        end
    end
    
    # Build LHS: π^T * capacity(y)
    cut_lhs = AffExpr(0.0)
    for (idx, l) in enumerate(links)
        idx in failed_link_indices && continue
        
        mods = link_modules[l]
        capacity_expr = sum(mods[m][2] * y_var[l,m] for m in eachindex(mods))
        add_to_expression!(cut_lhs, capacity_duals[l], capacity_expr)
    end
    
    # Build RHS: σ^T * demand_RHS
    # Flow conservation constraints have RHS = +demand at source, -demand at dest, 0 elsewhere
    # We need to extract the dual and multiply by the constraint RHS
    cut_rhs = 0.0
    for ((d, n), constraint) in sp.flow_conservation
        flow_dual = dual(constraint)
        rhs_value = normalized_rhs(constraint)
        cut_rhs += flow_dual * rhs_value
    end
    
    # Farkas cut: π^T * capacity(y) + σ^T * demand_RHS ≥ 0
    # Rearranged: π^T * capacity(y) ≥ -σ^T * demand_RHS
    cut_rhs = -cut_rhs
    
    return (cut_lhs, cut_rhs)
end
