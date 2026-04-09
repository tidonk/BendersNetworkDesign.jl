"""
Graph connectivity and manipulation utilities for SNDlib networks.

Provides functions to:
- Check graph connectivity and find connected components
- Compute node degrees and identify hub nodes
- Extract connected subgraphs
- Merge multiple networks at strategic connection points
"""

using Random

"""
    compute_node_degrees(network::SNDlibNetwork) -> Dict{String, Int}

Compute the degree (number of incident links) for each node.

# Returns
Dictionary mapping node_id => degree
"""
function compute_node_degrees(network::SNDlibNetwork)::Dict{String, Int}
    degrees = Dict{String, Int}()
    
    # Initialize all nodes with degree 0
    for node_id in keys(network.network_structure.nodes)
        degrees[node_id] = 0
    end
    
    # Count degree for each node (bidirectional links count once)
    for link in values(network.network_structure.links)
        degrees[link.source] = get(degrees, link.source, 0) + 1
        degrees[link.target] = get(degrees, link.target, 0) + 1
    end
    
    return degrees
end

"""
    get_high_degree_nodes(network::SNDlibNetwork, k::Int=5) -> Vector{String}

Get the k nodes with highest degree (most connections).

# Arguments
- `network`: SNDlib network
- `k`: Number of nodes to return (default: 5)

# Returns
Vector of node IDs sorted by degree (highest first), up to k nodes
"""
function get_high_degree_nodes(network::SNDlibNetwork, k::Int=5)::Vector{String}
    degrees = compute_node_degrees(network)
    sorted_nodes = sort(collect(keys(degrees)), by=id -> degrees[id], rev=true)
    return sorted_nodes[1:min(k, length(sorted_nodes))]
end

"""
    is_network_connected(network::SNDlibNetwork) -> Bool

Check if the network is fully connected (all nodes reachable from any node).

Uses BFS to determine connectivity.
"""
function is_network_connected(network::SNDlibNetwork)::Bool
    nodes = collect(keys(network.network_structure.nodes))
    isempty(nodes) && return true
    
    # Build adjacency list
    adjacency = Dict{String, Set{String}}()
    for node_id in nodes
        adjacency[node_id] = Set{String}()
    end
    
    for link in values(network.network_structure.links)
        push!(adjacency[link.source], link.target)
        push!(adjacency[link.target], link.source)
    end
    
    # BFS from first node
    start_node = first(nodes)
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
    
    return length(visited) == length(nodes)
end

"""
    compute_average_degree(network::SNDlibNetwork) -> Float64

Compute the average node degree in the network.
"""
function compute_average_degree(network::SNDlibNetwork)::Float64
    degrees = compute_node_degrees(network)
    isempty(degrees) && return 0.0
    return sum(values(degrees)) / length(degrees)
end

"""
    extract_subgraph(network::SNDlibNetwork, target_nodes::Int; seed::Union{Int,Nothing}=nothing) -> SNDlibNetwork

Extract a random connected subgraph with approximately target_nodes nodes.

Uses BFS starting from a random high-degree node to grow a connected subgraph.

# Arguments
- `network`: Source network
- `target_nodes`: Desired number of nodes in subgraph
- `seed`: Random seed for reproducibility

# Returns
New SNDlibNetwork containing the subgraph
"""
function extract_subgraph(network::SNDlibNetwork, target_nodes::Int; 
                         seed::Union{Int,Nothing}=nothing)::SNDlibNetwork
    if seed !== nothing
        Random.seed!(seed)
    end
    
    all_nodes = collect(keys(network.network_structure.nodes))
    target_nodes = min(target_nodes, length(all_nodes))
    
    # Build adjacency list
    adjacency = Dict{String, Set{String}}()
    for node_id in all_nodes
        adjacency[node_id] = Set{String}()
    end
    
    for link in values(network.network_structure.links)
        push!(adjacency[link.source], link.target)
        push!(adjacency[link.target], link.source)
    end
    
    # Start from a random high-degree node
    degrees = compute_node_degrees(network)
    high_degree_nodes = sort(all_nodes, by=id -> degrees[id], rev=true)
    start_idx = rand(1:min(5, length(high_degree_nodes)))  # Pick from top 5
    start_node = high_degree_nodes[start_idx]
    
    # BFS to grow subgraph
    selected_nodes = Set{String}([start_node])
    queue = [start_node]
    
    while !isempty(queue) && length(selected_nodes) < target_nodes
        node = popfirst!(queue)
        neighbors = collect(adjacency[node])
        shuffle!(neighbors)  # Randomize to avoid bias
        
        for neighbor in neighbors
            if !(neighbor in selected_nodes) && length(selected_nodes) < target_nodes
                push!(selected_nodes, neighbor)
                push!(queue, neighbor)
            end
        end
    end
    
    return extract_network_subset(network, selected_nodes)
end

"""
    extract_network_subset(network::SNDlibNetwork, node_ids::Set{String}) -> SNDlibNetwork

Extract a subnetwork containing only the specified nodes and their connecting links.

# Arguments
- `network`: Source network
- `node_ids`: Set of node IDs to include

# Returns
New SNDlibNetwork with only the specified nodes, their links, and demands between them
"""
function extract_network_subset(network::SNDlibNetwork, node_ids::Set{String})::SNDlibNetwork
    # Extract nodes
    new_nodes = Dict{String, Node}()
    for node_id in node_ids
        if haskey(network.network_structure.nodes, node_id)
            new_nodes[node_id] = network.network_structure.nodes[node_id]
        end
    end
    
    # Extract links (both endpoints must be in node_ids)
    new_links = Dict{String, Link}()
    for (link_id, link) in network.network_structure.links
        if link.source in node_ids && link.target in node_ids
            new_links[link_id] = link
        end
    end
    
    # Extract demands (both source and target must be in node_ids)
    new_demands = Dict{String, Demand}()
    for (demand_id, demand) in network.demands
        if demand.source in node_ids && demand.target in node_ids
            new_demands[demand_id] = demand
        end
    end
    
    # Create new network structure
    new_network_structure = NetworkStructure(new_nodes, new_links)
    
    return SNDlibNetwork(
        network.meta,
        new_network_structure,
        new_demands
    )
end

"""
    determine_connection_count(avg_degree1::Float64, avg_degree2::Float64) -> Int

Determine the number of connection points between two networks based on their connectivity.

Networks with higher average degree should be connected at more points to maintain
similar connectivity patterns.

# Arguments
- `avg_degree1`: Average degree of first network
- `avg_degree2`: Average degree of second network

# Returns
Number of connection points (1-5)
"""
function determine_connection_count(avg_degree1::Float64, avg_degree2::Float64)::Int
    avg_connectivity = (avg_degree1 + avg_degree2) / 2.0
    
    # Map average degree to connection count
    if avg_connectivity < 2.5
        return 1  # Sparse networks: single connection
    elseif avg_connectivity < 3.5
        return 2  # Moderate: 2 connections
    elseif avg_connectivity < 4.5
        return 3  # Well-connected: 3 connections
    else
        return 4  # Highly connected: 4 connections
    end
end

"""
    merge_networks(networks::Vector{SNDlibNetwork}, prefixes::Vector{String};
                  connection_points::Union{Int,Nothing}=nothing) -> SNDlibNetwork

Merge multiple networks into a single larger network.

Automatically determines connection points based on network connectivity and selects
high-degree nodes as merge points.

# Arguments
- `networks`: Vector of networks to merge
- `prefixes`: Unique prefixes for node/link/demand IDs in each network
- `connection_points`: Number of connection points (nothing = auto-determine)

# Returns
Merged SNDlibNetwork

# Algorithm
1. Add unique prefixes to all node/link/demand IDs
2. Determine connection points based on average network degree
3. Select high-degree nodes from each network as merge candidates
4. Create new links connecting the networks
5. Merge all nodes, links, and demands
"""
function merge_networks(networks::Vector{SNDlibNetwork}, prefixes::Vector{String};
                       connection_points::Union{Int,Nothing}=nothing)::SNDlibNetwork
    @assert length(networks) >= 2 "Need at least 2 networks to merge"
    @assert length(networks) == length(prefixes) "Must provide one prefix per network"
    @assert allunique(prefixes) "Prefixes must be unique"
    
    # Compute average degrees for connection point determination
    avg_degrees = [compute_average_degree(net) for net in networks]
    
    # Prepare networks with prefixes
    prefixed_networks = []
    for (i, (network, prefix)) in enumerate(zip(networks, prefixes))
        push!(prefixed_networks, add_prefix_to_network(network, prefix))
    end
    
    # Determine connection points between consecutive networks
    merged_network = prefixed_networks[1]
    
    for i in 2:length(prefixed_networks)
        n_connections = if connection_points !== nothing
            connection_points
        else
            determine_connection_count(avg_degrees[i-1], avg_degrees[i])
        end
        
        merged_network = merge_two_networks(merged_network, prefixed_networks[i], n_connections)
    end
    
    return merged_network
end

"""
    add_prefix_to_network(network::SNDlibNetwork, prefix::String) -> SNDlibNetwork

Add a prefix to all node, link, and demand IDs in a network.

# Arguments
- `network`: Source network
- `prefix`: Prefix to add (e.g., "A_", "B_")

# Returns
New network with prefixed IDs
"""
function add_prefix_to_network(network::SNDlibNetwork, prefix::String)::SNDlibNetwork
    # Prefix nodes
    new_nodes = Dict{String, Node}()
    for (node_id, node) in network.network_structure.nodes
        new_id = prefix * node_id
        new_nodes[new_id] = Node(new_id, node.x, node.y)
    end
    
    # Prefix links
    new_links = Dict{String, Link}()
    for (link_id, link) in network.network_structure.links
        new_id = prefix * link_id
        new_source = prefix * link.source
        new_target = prefix * link.target
        new_links[new_id] = Link(
            new_id, new_source, new_target,
            link.routing_cost, link.setup_cost,
            link.preinstalled_capacity, link.preinstalled_cost,
            link.additional_modules
        )
    end
    
    # Prefix demands
    new_demands = Dict{String, Demand}()
    for (demand_id, demand) in network.demands
        new_id = prefix * demand_id
        new_source = prefix * demand.source
        new_target = prefix * demand.target
        new_demands[new_id] = Demand(
            new_id, new_source, new_target,
            demand.routing_unit, demand.demand_value, demand.max_path_length,
            demand.admissible_paths
        )
    end
    
    new_network_structure = NetworkStructure(new_nodes, new_links)
    
    return SNDlibNetwork(
        network.meta,
        new_network_structure,
        new_demands
    )
end

"""
    merge_two_networks(net1::SNDlibNetwork, net2::SNDlibNetwork, n_connections::Int) -> SNDlibNetwork

Merge two networks by connecting them at n_connections points.

Selects high-degree nodes from each network and creates bidirectional links between them.

# Arguments
- `net1`: First network
- `net2`: Second network  
- `n_connections`: Number of connection points

# Returns
Merged network with interconnection links
"""
function merge_two_networks(net1::SNDlibNetwork, net2::SNDlibNetwork, n_connections::Int)::SNDlibNetwork
    # Get high-degree nodes from each network
    hubs1 = get_high_degree_nodes(net1, n_connections)
    hubs2 = get_high_degree_nodes(net2, n_connections)
    
    # Adjust if fewer nodes available
    n_actual = min(n_connections, length(hubs1), length(hubs2))
    hubs1 = hubs1[1:n_actual]
    hubs2 = hubs2[1:n_actual]
    
    # Merge all nodes
    merged_nodes = Dict{String, Node}()
    merge!(merged_nodes, net1.network_structure.nodes)
    merge!(merged_nodes, net2.network_structure.nodes)
    
    # Merge all links
    merged_links = Dict{String, Link}()
    merge!(merged_links, net1.network_structure.links)
    merge!(merged_links, net2.network_structure.links)
    
    # Create interconnection links
    # Use the module characteristics from the first network as template
    template_link = first(values(net1.network_structure.links))
    
    for i in 1:n_actual
        node1 = hubs1[i]
        node2 = hubs2[i]
        
        # Create bidirectional link IDs
        link_id_fwd = "inter_$(node1)_$(node2)"
        link_id_bwd = "inter_$(node2)_$(node1)"
        
        # Forward link
        merged_links[link_id_fwd] = Link(
            link_id_fwd, node1, node2,
            template_link.routing_cost,
            template_link.setup_cost,
            nothing,  # No preinstalled capacity
            nothing,  # No preinstalled cost
            template_link.additional_modules
        )
        
        # Backward link
        merged_links[link_id_bwd] = Link(
            link_id_bwd, node2, node1,
            template_link.routing_cost,
            template_link.setup_cost,
            nothing,
            nothing,
            template_link.additional_modules
        )
    end
    
    # Merge demands
    merged_demands = Dict{String, Demand}()
    merge!(merged_demands, net1.demands)
    merge!(merged_demands, net2.demands)
    
    merged_network_structure = NetworkStructure(merged_nodes, merged_links)
    
    return SNDlibNetwork(
        nothing,  # No meta for merged network
        merged_network_structure,
        merged_demands
    )
end

