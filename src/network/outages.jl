"""
Outage scenario generation for network survivability analysis.

An outage scenario represents one or more simultaneous link failures in the network.
Only outages that don't disconnect demand nodes are included.
"""

using Combinatorics

"""
    OutageScenario

Represents a network outage scenario with one or more simultaneous link failures.

# Fields
- `id::Int`: Unique identifier for this scenario
- `failed_link_indices::Vector{Int}`: Indices of failed links (empty vector for base case)
"""
struct OutageScenario
    id::Int
    failed_link_indices::Vector{Int}
end

"""
    is_connected(network::SNDlibNetwork, failed_link_indices::Vector{Int}, demand_nodes::Set{String}) -> Bool

Check if all demand nodes remain connected when specified links fail.

Uses breadth-first search to determine if all nodes with demands can reach each other
through the network with the specified links removed.

# Arguments
- `network`: The network structure
- `failed_link_indices`: Indices of failed links (1-based, corresponding to link order)
- `demand_nodes`: Set of node IDs that have demands (sources or targets)

# Returns
- `true` if all demand nodes remain connected, `false` otherwise
"""
function is_connected(network::SNDlibNetwork, failed_link_indices::Vector{Int}, demand_nodes::Set{String})::Bool
    isempty(demand_nodes) && return true
    
    links = network.network_structure.links
    link_list = collect(keys(links))
    failed_link_ids = Set(link_list[i] for i in failed_link_indices if 1 <= i <= length(link_list))
    
    # Build adjacency list excluding the failed links
    adjacency = Dict{String, Set{String}}()
    for node_id in keys(network.network_structure.nodes)
        adjacency[node_id] = Set{String}()
    end
    
    for (link_id, link) in links
        link_id in failed_link_ids && continue
        push!(adjacency[link.source], link.target)
        push!(adjacency[link.target], link.source)
    end
    
    # BFS from an arbitrary demand node to check reachability
    start_node = first(demand_nodes)
    visited = Set{String}([start_node])
    queue = [start_node]
    
    while !isempty(queue)
        node = popfirst!(queue)
        for neighbor in adjacency[node]
            if !(neighbor in visited)
                push!(visited, neighbor)
                push!(queue, neighbor)
            end
        end
    end
    
    # Check if all demand nodes are reachable
    return all(node in visited for node in demand_nodes)
end

"""
    generate_outage_scenarios(network::SNDlibNetwork; include_base_case::Bool=true, k::Int=1) -> Vector{OutageScenario}

Generate all valid k-link outage scenarios for the network.

Creates scenarios for all k-link failures (N-k contingencies), filtering out failures
that would disconnect nodes with demands. Nodes without demands may be disconnected.

# Arguments
- `network`: The SNDlib network structure
- `include_base_case`: If true, include scenario with no failures (default: true)
- `k`: Number of simultaneous link failures (default: 1)

# Returns
Vector of `OutageScenario` objects. Base case (if included) is first with id=0.

# Performance Note
Number of scenarios grows as C(n,k) where n is number of links:
- k=1: n scenarios (linear)
- k=2: n*(n-1)/2 scenarios (quadratic)
- k=3: n*(n-1)*(n-2)/6 scenarios (cubic)
For large networks with k>2, consider using sample_outage_scenarios instead.
"""
function generate_outage_scenarios(network::SNDlibNetwork; include_base_case::Bool=true, k::Int=1)::Vector{OutageScenario}
    @assert k >= 1 "k must be at least 1"
    
    # Collect all nodes that have demands (either as source or target)
    demand_nodes = Set{String}()
    for demand in values(network.demands)
        push!(demand_nodes, demand.source)
        push!(demand_nodes, demand.target)
    end
    
    scenarios = OutageScenario[]
    scenario_id = 0
    
    # Add base case (no failures)
    if include_base_case
        push!(scenarios, OutageScenario(scenario_id, Int[]))
        scenario_id += 1
    end
    
    # Generate all k-link failure combinations
    num_links = length(network.network_structure.links)
    
    if k > num_links
        @warn "k=$k exceeds number of links ($num_links), no k-contingencies possible"
        return scenarios
    end
    
    # Generate all k-link failure combinations
    for failed_indices in combinations(1:num_links, k)
        if is_connected(network, collect(failed_indices), demand_nodes)
            push!(scenarios, OutageScenario(scenario_id, collect(failed_indices)))
            scenario_id += 1
        else
            @debug "Excluding outage scenario: link indices $failed_indices (disconnects demand nodes)"
        end
    end
    
    return scenarios
end

"""
    sample_outage_scenarios(network::SNDlibNetwork, num_samples::Int; seed::Union{Int,Nothing}=nothing, include_base_case::Bool=true, k::Int=1) -> Vector{OutageScenario}

Randomly sample outage scenarios from all valid k-link failures.

# Arguments
- `network`: The SNDlib network structure
- `num_samples`: Number of scenarios to sample (excluding base case if included)
- `seed`: Random seed for reproducibility (default: nothing)
- `include_base_case`: If true, always include base case as first scenario (default: true)
- `k`: Number of simultaneous link failures (default: 1)

# Returns
Vector of `OutageScenario` objects. If `include_base_case=true`, base case is first (id=0),
followed by `num_samples` randomly selected k-link failures.

# Notes
If `num_samples` exceeds the number of valid scenarios, all valid scenarios are returned.
"""
function sample_outage_scenarios(network::SNDlibNetwork, num_samples::Int; 
                                 seed::Union{Int,Nothing}=nothing, 
                                 include_base_case::Bool=true,
                                 k::Int=1)::Vector{OutageScenario}
    # Generate all valid scenarios
    all_scenarios = generate_outage_scenarios(network; include_base_case=false, k=k)
    
    # Set random seed if provided
    if seed !== nothing
        Random.seed!(seed)
    end
    
    # Sample scenarios (without replacement)
    n_available = length(all_scenarios)
    n_to_sample = min(num_samples, n_available)
    
    if n_to_sample < num_samples
        @warn "Requested $num_samples scenarios but only $n_available valid scenarios available"
    end
    
    sampled_indices = randperm(n_available)[1:n_to_sample]
    sampled_scenarios = all_scenarios[sampled_indices]
    
    # Reassign IDs
    result = OutageScenario[]
    scenario_id = 0
    
    if include_base_case
        push!(result, OutageScenario(scenario_id, Int[]))
        scenario_id += 1
    end
    
    for scenario in sampled_scenarios
        push!(result, OutageScenario(scenario_id, scenario.failed_link_indices))
        scenario_id += 1
    end
    
    return result
end
