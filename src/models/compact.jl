using JuMP

"""
Two-stage stochastic network design - Compact formulation with modular capacities and outage scenarios

SNDlib formulation:
- First stage: Install capacity modules on links (integer y variables)
- Second stage: Route demands for each outage scenario (continuous flow variables)
- Objective: min module installation costs (no routing costs in SNDlib)
- Constraints: flow conservation, modular capacity limits

Variables:
- y[l,m] ≥ 0 (integer): number of modules of type m installed on link l
- f[s,d,a] ≥ 0: flow of demand d on arc a in outage scenario s

Parameters:
- modules[l] = [(cap_1, cost_1), (cap_2, cost_2), ...]: available modules for link l
- demand_value[d]: demand value for demand d (from network)
- outage_scenarios[s]: outage scenario s with failed link indices

Objective:
- min Σ_l Σ_m cost_m · y[l,m]

Constraints:
- Flow conservation at each node for each demand and outage scenario
- Modular capacity: Σ_d f[s,d,a] ≤ Σ_m cap_m · y[l,m] for each link and scenario (0 if link failed)
"""

"""
    build_compact_model(network; optimizer=nothing, outage_scenarios)

Build the compact formulation for two-stage stochastic network design with outage scenarios.

# Arguments
- `network`: SNDlibNetwork with nodes, links, demands
- `optimizer`: Optimizer function (default: from settings file)
- `outage_scenarios`: Vector{OutageScenario} of outage scenarios to consider

# Returns
- JuMP model

# Notes
Demands are extracted from network.demands. Each outage scenario represents zero or more
simultaneous link failures. Capacity constraints for failed links are set to zero.
"""
function build_compact_model(network::SNDlibNetwork; optimizer=nothing, outage_scenarios::Vector{OutageScenario})::Model
    # Get optimizer function (don't call it - JuMP Model does that)
    settings = read_settings()
    opt_func = isnothing(optimizer) ? settings.optimizer : optimizer
    model = Model(opt_func)
    
    # Set time limit
    set_time_limit_sec(model, settings.time_limit)
    
    nodes = network.network_structure.nodes
    links = network.network_structure.links
    
    # Sets
    N = collect(keys(nodes))
    L = collect(keys(links))
    num_links = length(L)
    S = eachindex(outage_scenarios)
    
    # Arcs: bidirectional (each link can be used in both directions)
    A = vcat([(l, :forward) for l in L], [(l, :backward) for l in L])
    
    # Demands from network
    D = collect(keys(network.demands))
    
    # Build module index for each link
    # modules[l] = [(module_id, capacity, cost), ...]
    link_modules = Dict{String, Vector{Tuple{Int, Float64, Float64}}}()
    for (lid, link) in links
        mods = Tuple{Int, Float64, Float64}[]
        
        # Preinstalled capacity (free, always available)
        if !isnothing(link.preinstalled_capacity) && link.preinstalled_capacity > 0
            push!(mods, (0, link.preinstalled_capacity, 0.0))
        end
        
        # Additional modules
        for (m_idx, (cap, cost)) in enumerate(link.additional_modules)
            push!(mods, (m_idx, cap, cost))
        end
        
        link_modules[lid] = mods
    end
    
    # Variables
    # y[l,m] = number of modules of type m on link l
    @variable(model, y[l in L, m in eachindex(link_modules[l])] >= 0, Int, base_name="y")
    
    # Flow variables: f[s, d, a] for each outage scenario, demand, and arc
    @variable(model, f[s in S, d in D, a in A] >= 0, base_name="f")
    
    # Preinstalled capacity constraint: can use at most 1 unit
    for l in L
        mods = link_modules[l]
        if !isempty(mods) && mods[1][1] == 0  # module 0 is preinstalled
            @constraint(model, y[l, 1] <= 1, base_name="preinstalled")
        end
    end
    
    # Objective: minimize module installation costs
    install_cost = sum(
        link_modules[l][m][3] * y[l, m]  # cost is 3rd element
        for l in L for m in eachindex(link_modules[l])
    )
    @objective(model, Min, install_cost)
    
    # Helper: get arc endpoints
    arc_endpoints(link_id, dir) = begin
        link = links[link_id]
        dir == :forward ? (link.source, link.target) : (link.target, link.source)
    end
    
    # Constraints for each outage scenario
    for s in S
        outage = outage_scenarios[s]
        failed_indices_set = Set(outage.failed_link_indices)
        
        # Determine which arcs are available (not failed)
        available_arcs = filter(a -> !(findfirst(==(a[1]), L) in failed_indices_set), A)
        
        for d in D
            demand = network.demands[d]
            src, tgt = demand.source, demand.target
            demand_val = demand.demand_value
            
            # Flow conservation at each node
            for n in N
                out_arcs = [a for a in available_arcs if arc_endpoints(a[1], a[2])[1] == n]
                in_arcs = [a for a in available_arcs if arc_endpoints(a[1], a[2])[2] == n]
                
                net_flow = sum(f[s,d,a] for a in out_arcs; init=0.0) - 
                          sum(f[s,d,a] for a in in_arcs; init=0.0)
                
                if n == src
                    @constraint(model, net_flow == demand_val, base_name="flow_cons")
                elseif n == tgt
                    @constraint(model, net_flow == -demand_val, base_name="flow_cons")
                else
                    @constraint(model, net_flow == 0, base_name="flow_cons")
                end
            end
        end
        
        # Modular capacity constraints (only for links that haven't failed)
        for (link_idx, l) in enumerate(L)
            link_idx in failed_indices_set && continue  # Skip failed links
            
            mods = link_modules[l]
            total_capacity = sum(mods[m][2] * y[l, m] for m in eachindex(mods))
            
            # Total flow on link l (both directions) must not exceed capacity
            total_flow = sum(f[s,d,(l,:forward)] for d in D; init=0.0) + 
                        sum(f[s,d,(l,:backward)] for d in D; init=0.0)
            
            @constraint(model, total_flow <= total_capacity, base_name="capacity")
        end
    end
    
    return model
end

"""
    solve_compact_model(network; optimizer, outage_scenarios)

Build and solve the compact formulation.

# Returns
Named tuple with objective_value, y_solution, model, status
"""
function solve_compact_model(network::SNDlibNetwork; optimizer, outage_scenarios::Vector{OutageScenario})::NamedTuple
    model = build_compact_model(network; optimizer=optimizer, outage_scenarios=outage_scenarios)
    optimize!(model)
    
    termination_status(model) != OPTIMAL && 
        @warn "Not optimal" termination_status(model)
    
    # Extract solution from SparseAxisArray
    y_sol = Dict()
    y_var = model[:y]
    for idx in eachindex(y_var)
        val = value(y_var[idx])
        if val > 1e-6
            y_sol[idx] = val
        end
    end
    
    return (
        objective_value = objective_value(model),
        y_solution = y_sol,
        model = model,
        status = termination_status(model),
        node_count = MOI.get(model, MOI.NodeCount())
    )
end
