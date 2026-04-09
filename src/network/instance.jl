"""
Instance generation utilities for creating larger test networks.

Provides high-level functions to:
- Load and combine multiple SNDlib instances
- Scale demands and capacities
- Generate synthetic large-scale instances
"""

using CSV
using DataFrames

"""
    combine_sndlib_instances(file_paths::Vector{String}, prefixes::Vector{String};
                            target_sizes::Union{Vector{Int},Nothing}=nothing,
                            connection_points::Union{Int,Nothing}=nothing,
                            seed::Union{Int,Nothing}=nothing) -> SNDlibNetwork

Combine multiple SNDlib network files into a single larger instance.

# Arguments
- `file_paths`: Paths to SNDlib XML files
- `prefixes`: Unique prefixes for each network (e.g., ["A_", "B_", "C_"])
- `target_sizes`: If provided, extract subgraphs of these sizes (nothing = use full networks)
- `connection_points`: Number of inter-network connections (nothing = auto-determine)
- `seed`: Random seed for reproducibility (affects subgraph extraction)

# Returns
Combined SNDlibNetwork

# Examples
```julia
# Combine full abilene and atlanta networks
network = combine_sndlib_instances(
    ["data/sndlib/abilene.xml", "data/sndlib/atlanta.xml"],
    ["abilene_", "atlanta_"]
)

# Combine subgraphs of specific sizes
network = combine_sndlib_instances(
    ["data/sndlib/abilene.xml", "data/sndlib/atlanta.xml"],
    ["A_", "B_"],
    target_sizes=[8, 10],
    seed=42
)
```
"""
function combine_sndlib_instances(file_paths::Vector{String}, prefixes::Vector{String};
                                 target_sizes::Union{Vector{Int},Nothing}=nothing,
                                 connection_points::Union{Int,Nothing}=nothing,
                                 seed::Union{Int,Nothing}=nothing)::SNDlibNetwork
    @assert length(file_paths) >= 2 "Need at least 2 networks to combine"
    @assert length(file_paths) == length(prefixes) "Must provide one prefix per network"
    
    if target_sizes !== nothing
        @assert length(target_sizes) == length(file_paths) "Must provide one target size per network"
    end
    
    # Load networks
    networks = SNDlibNetwork[]
    for (i, file_path) in enumerate(file_paths)
        network = read_sndlib_network(file_path)
        
        # Extract subgraph if target size specified
        if target_sizes !== nothing
            # Use seed + index for deterministic but different subgraphs
            subgraph_seed = seed === nothing ? nothing : seed + i
            network = extract_subgraph(network, target_sizes[i]; seed=subgraph_seed)
        end
        
        push!(networks, network)
    end
    
    # Merge networks
    return merge_networks(networks, prefixes; connection_points=connection_points)
end

"""
    scale_network_demands(network::SNDlibNetwork, scale_factor::Float64) -> SNDlibNetwork

Scale all demand values in a network by a constant factor.

# Arguments
- `network`: Source network
- `scale_factor`: Multiplicative factor for demands (e.g., 2.0 doubles all demands)

# Returns
New network with scaled demands
"""
function scale_network_demands(network::SNDlibNetwork, scale_factor::Float64)::SNDlibNetwork
    new_demands = Dict{String, Demand}()
    
    for (demand_id, demand) in network.demands
        new_demands[demand_id] = Demand(
            demand.id,
            demand.source,
            demand.target,
            demand.routing_unit,
            demand.demand_value * scale_factor,  # Scale demand
            demand.max_path_length,
            demand.admissible_paths
        )
    end
    
    return SNDlibNetwork(
        network.meta,
        network.network_structure,
        new_demands
    )
end

"""
    scale_network_capacities(network::SNDlibNetwork, scale_factor::Float64) -> SNDlibNetwork

Scale all module capacities in a network by a constant factor.

# Arguments
- `network`: Source network
- `scale_factor`: Multiplicative factor for module capacities

# Returns
New network with scaled link capacities
"""
function scale_network_capacities(network::SNDlibNetwork, scale_factor::Float64)::SNDlibNetwork
    new_links = Dict{String, Link}()
    
    for (link_id, link) in network.network_structure.links
        # Scale module capacities
        scaled_modules = [(cap * scale_factor, cost) for (cap, cost) in link.additional_modules]
        
        new_links[link_id] = Link(
            link.id,
            link.source,
            link.target,
            link.routing_cost,
            link.setup_cost,
            link.preinstalled_capacity === nothing ? nothing : link.preinstalled_capacity * scale_factor,
            link.preinstalled_cost,
            scaled_modules
        )
    end
    
    new_network_structure = NetworkStructure(network.network_structure.nodes, new_links)
    
    return SNDlibNetwork(
        network.meta,
        new_network_structure,
        network.demands
    )
end

"""
    normalize_network(network::SNDlibNetwork; target_avg_demand::Float64=10.0) -> SNDlibNetwork

Normalize demands so that the average demand value matches target_avg_demand.

Useful when combining networks with different demand scales.

# Arguments
- `network`: Source network
- `target_avg_demand`: Desired average demand value (default: 10.0)

# Returns
New network with normalized demands
"""
function normalize_network(network::SNDlibNetwork; target_avg_demand::Float64=10.0)::SNDlibNetwork
    isempty(network.demands) && return network
    
    # Compute current average demand
    current_avg = sum(d.demand_value for d in values(network.demands)) / length(network.demands)
    
    # Avoid division by zero
    if current_avg < 1e-10
        @warn "Network has zero or near-zero demands, cannot normalize"
        return network
    end
    
    # Compute scale factor
    scale_factor = target_avg_demand / current_avg
    
    return scale_network_demands(network, scale_factor)
end

"""
    balance_combined_network(network::SNDlibNetwork) -> SNDlibNetwork

Balance demands and capacities in a combined network.

Ensures that total capacity (if all modules installed) significantly exceeds total demand.
Aims for a capacity/demand ratio of approximately 2.0 for reasonable problem difficulty.

# Arguments
- `network`: Combined network (potentially unbalanced)

# Returns
Network with balanced demands and capacities
"""
function balance_combined_network(network::SNDlibNetwork)::SNDlibNetwork
    # Compute total demand
    total_demand = sum(d.demand_value for d in values(network.demands))
    
    # Compute total potential capacity (all modules on all links)
    # Assume each link can have at most 10 modules (heuristic)
    max_modules_per_link = 10
    total_capacity = sum(
        begin
            # Get the largest module capacity for this link
            if !isempty(link.additional_modules)
                maximum(m[1] for m in link.additional_modules) * max_modules_per_link
            else
                0.0
            end
        end
        for link in values(network.network_structure.links)
    )
    
    # If capacity is too high relative to demand, scale down capacities
    # If capacity is too low, scale up capacities
    capacity_demand_ratio = total_capacity / max(total_demand, 1.0)
    target_ratio = 2.0  # Target: total capacity ≈ 2x total demand
    
    if capacity_demand_ratio > target_ratio * 1.5
        # Capacity too high - scale down
        scale_factor = target_ratio / capacity_demand_ratio
        @info "Balancing network: scaling capacities by $scale_factor"
        return scale_network_capacities(network, scale_factor)
    elseif capacity_demand_ratio < target_ratio * 0.5
        # Capacity too low - scale up
        scale_factor = target_ratio / capacity_demand_ratio
        @info "Balancing network: scaling capacities by $scale_factor"
        return scale_network_capacities(network, scale_factor)
    else
        # Ratio is acceptable
        return network
    end
end

"""
    export_network_to_csv(network::SNDlibNetwork, output_dir::String; prefix::String="network")

Export a network to CSV files for nodes, links, and demands.

Creates three CSV files in the specified directory:
- `{prefix}_nodes.csv`: Node information (id, x, y coordinates)
- `{prefix}_links.csv`: Link information (id, source, target, costs, capacities, modules)
- `{prefix}_demands.csv`: Demand information (id, source, target, value)

# Arguments
- `network`: SNDlibNetwork to export
- `output_dir`: Directory to write CSV files
- `prefix`: Filename prefix (default: "network")

# Example
```julia
combined = combine_sndlib_instances([...], [...])
export_network_to_csv(combined, "output", prefix="combined_network")
```
"""
function export_network_to_csv(network::SNDlibNetwork, output_dir::String; prefix::String="network")::Nothing
    # Create output directory if it doesn't exist
    mkpath(output_dir)
    
    # Export nodes
    nodes_data = DataFrame(
        id = String[],
        x = Union{Float64,Missing}[],
        y = Union{Float64,Missing}[]
    )
    
    for (node_id, node) in network.network_structure.nodes
        push!(nodes_data, (
            id = node_id,
            x = node.x === nothing ? missing : node.x,
            y = node.y === nothing ? missing : node.y
        ))
    end
    
    CSV.write(joinpath(output_dir, "$(prefix)_nodes.csv"), nodes_data)
    
    # Export links
    links_data = DataFrame(
        id = String[],
        source = String[],
        target = String[],
        routing_cost = Union{Float64,Missing}[],
        setup_cost = Union{Float64,Missing}[],
        preinstalled_capacity = Union{Float64,Missing}[],
        preinstalled_cost = Union{Float64,Missing}[],
        num_module_types = Int[],
        modules = String[]  # JSON-like string representation
    )
    
    for (link_id, link) in network.network_structure.links
        modules_str = join(["($(m[1]),$(m[2]))" for m in link.additional_modules], ";")
        
        push!(links_data, (
            id = link_id,
            source = link.source,
            target = link.target,
            routing_cost = link.routing_cost === nothing ? missing : link.routing_cost,
            setup_cost = link.setup_cost === nothing ? missing : link.setup_cost,
            preinstalled_capacity = link.preinstalled_capacity === nothing ? missing : link.preinstalled_capacity,
            preinstalled_cost = link.preinstalled_cost === nothing ? missing : link.preinstalled_cost,
            num_module_types = length(link.additional_modules),
            modules = modules_str
        ))
    end
    
    CSV.write(joinpath(output_dir, "$(prefix)_links.csv"), links_data)
    
    # Export demands
    demands_data = DataFrame(
        id = String[],
        source = String[],
        target = String[],
        value = Float64[]
    )
    
    for (demand_id, demand) in network.demands
        push!(demands_data, (
            id = demand_id,
            source = demand.source,
            target = demand.target,
            value = demand.demand_value
        ))
    end
    
    CSV.write(joinpath(output_dir, "$(prefix)_demands.csv"), demands_data)
    
    @info "Exported network to CSV files in $output_dir with prefix '$prefix'"
    @info "  Nodes: $(nrow(nodes_data)) rows"
    @info "  Links: $(nrow(links_data)) rows"
    @info "  Demands: $(nrow(demands_data)) rows"
    
    return nothing
end

"""
List of available base networks from SNDlib.
"""
const SNDLIB_NETWORKS = [
    "abilene", "atlanta", "brain", "cost266", "dfn-bwin", "dfn-gwin", 
    "di-yuan", "france", "geant", "germany50", "giul39", "india35", 
    "janos-us", "janos-us-ca", "newyork", "nobel-eu", "nobel-germany",
    "nobel-us", "norway", "pdh", "pioro40", "polska", "sun", "ta1", "ta2",
    "zib54"
]

"""
Network sizes (number of nodes) for SNDlib networks.
"""
const NETWORK_SIZES = Dict(
    "abilene" => 12, "atlanta" => 15, "brain" => 161, "cost266" => 37,
    "dfn-bwin" => 10, "dfn-gwin" => 11, "di-yuan" => 11, "france" => 25, 
    "geant" => 22, "germany50" => 50, "giul39" => 39, "india35" => 35, 
    "janos-us" => 26, "janos-us-ca" => 39, "newyork" => 16, "nobel-eu" => 28,
    "nobel-germany" => 17, "nobel-us" => 14, "norway" => 27, "pdh" => 11,
    "pioro40" => 40, "polska" => 12, "sun" => 27, "ta1" => 24, "ta2" => 65,
    "zib54" => 54
)

"""
    generate_single_instance(instance_id::Int, base_seed::Int;
                            num_networks_range::Vector{Int}=[3, 4, 5],
                            proportion_range::Vector{Float64}=[0.3, 0.5, 0.7, 1.0],
                            cost_scale_factors::Vector{Float64}=[0.1],
                            output_dir::String="../data/generated",
                            sndlib_dir::String="../data/sndlib") -> String

Generate a single combined instance from randomly selected base networks.

# Arguments
- `instance_id`: Unique instance identifier
- `base_seed`: Base random seed (instance seed = base_seed + instance_id)
- `num_networks_range`: Pool of network counts to sample from
- `proportion_range`: Pool of proportions to sample from
- `cost_scale_factors`: Pool of cost scales to sample from
- `output_dir`: Output directory
- `sndlib_dir`: Directory containing base SNDlib networks

# Returns
Path to generated XML file
"""
function generate_single_instance(instance_id::Int, base_seed::Int;
                                 num_networks_range::Vector{Int}=[3, 4, 5],
                                 proportion_range::Vector{Float64}=[0.3, 0.5, 0.7, 1.0],
                                 cost_scale_factors::Vector{Float64}=[0.1],
                                 output_dir::String="../data/generated",
                                 sndlib_dir::String="../data/sndlib")::String
    # Set seed for this instance
    seed = base_seed + instance_id
    Random.seed!(seed)
    
    # Sample parameters
    num_networks = rand(num_networks_range)
    proportion = rand(proportion_range)
    cost_scale = rand(cost_scale_factors)
    
    # Select random base networks (without replacement)
    selected_networks = String[]
    while length(selected_networks) < num_networks
        net = rand(SNDLIB_NETWORKS)
        if !(net in selected_networks)
            push!(selected_networks, net)
        end
    end
    sort!(selected_networks)  # For deterministic ordering
    
    # Load and combine networks
    file_paths = [joinpath(sndlib_dir, "$net.xml") for net in selected_networks]
    prefixes = ["n$(i)_" for i in 1:num_networks]
    
    # Calculate target sizes based on proportion
    target_sizes = [max(3, floor(Int, NETWORK_SIZES[net] * proportion)) for net in selected_networks]
    
    # Combine networks
    combined = combine_sndlib_instances(
        file_paths, prefixes;
        target_sizes=target_sizes,
        seed=seed
    )
    
    # Scale costs
    if cost_scale != 1.0
        new_links = Dict{String, Link}()
        for (link_id, link) in combined.network_structure.links
            scaled_modules = [(cap, cost * cost_scale) for (cap, cost) in link.additional_modules]
            new_links[link_id] = Link(
                link.id, link.source, link.target,
                link.routing_cost === nothing ? nothing : link.routing_cost * cost_scale,
                link.setup_cost === nothing ? nothing : link.setup_cost * cost_scale,
                link.preinstalled_capacity,
                link.preinstalled_cost === nothing ? nothing : link.preinstalled_cost * cost_scale,
                scaled_modules
            )
        end
        combined = SNDlibNetwork(
            combined.meta,
            NetworkStructure(combined.network_structure.nodes, new_links),
            combined.demands
        )
    end
    
    # Generate output filename
    num_nodes = length(combined.network_structure.nodes)
    num_links = length(combined.network_structure.links)
    filename = "instance_$(lpad(instance_id, 4, '0'))_n$(num_networks)_s$(num_links)_seed$(seed).xml"
    output_path = joinpath(output_dir, filename)
    
    # Write to XML with metadata
    mkpath(output_dir)
    write_sndlib_network(combined, output_path)
    
    # Log generation
    println("Generated instance $(lpad(instance_id, 4, '0')): $filename")
    println("  Networks: $(join(selected_networks, ", "))")
    println("  Proportion: $(round(proportion, digits=2))")
    println("  Target sizes: $(join(target_sizes, ", "))")
    println("  Actual size: $num_nodes nodes, $num_links links")
    println("  Cost scale: $cost_scale")
    
    return output_path
end

"""
    generate_instance_suite(; num_instances::Int=30,
                           base_seed::Int=800,
                           num_networks_range::Vector{Int}=[2, 3, 4, 5],
                           proportion_range::Union{Vector{Float64},Nothing}=nothing,
                           cost_scale_factors::Vector{Float64}=[0.1],
                           output_dir::String="../data/generated",
                           sndlib_dir::String="../data/sndlib",
                           manifest_file::String="instance_manifest.md") -> Vector{String}

Generate a suite of test instances by systematically cycling through parameters.

# Arguments
- `num_instances`: Number of instances to generate
- `base_seed`: Base random seed (instance seed = base_seed + instance_id)
- `num_networks_range`: Network counts to cycle through
- `proportion_range`: Proportions to cycle through (nothing = use [0.3, 0.5, 0.7])
- `cost_scale_factors`: Cost scales to cycle through
- `output_dir`: Output directory
- `sndlib_dir`: Directory containing base SNDlib networks
- `manifest_file`: Name of manifest file (markdown format)

# Returns
Vector of generated file paths

# Example
```julia
files = generate_instance_suite(
    num_instances=50,
    base_seed=900,
    num_networks_range=[3, 4, 5],
    proportion_range=collect(range(0.45, 0.65, length=10)),
    output_dir="../data/generated/experiment5"
)
```
"""
function generate_instance_suite(; num_instances::Int=30,
                                 base_seed::Int=800,
                                 num_networks_range::Vector{Int}=[2, 3, 4, 5],
                                 proportion_range::Union{Vector{Float64},Nothing}=nothing,
                                 cost_scale_factors::Vector{Float64}=[0.1],
                                 output_dir::String="../data/generated",
                                 sndlib_dir::String="../data/sndlib",
                                 manifest_file::String="instance_manifest.md")::Vector{String}
    
    # Default proportions if not specified
    if proportion_range === nothing
        proportion_range = [0.3, 0.5, 0.7]
    end
    
    # Create parameter cycling
    params = []
    for num_nets in num_networks_range
        for prop in proportion_range
            for cost_scale in cost_scale_factors
                push!(params, (num_nets, prop, cost_scale))
            end
        end
    end
    
    # Ensure output directory exists
    mkpath(output_dir)
    
    # Generate instances
    generated_files = String[]
    manifest_lines = String[]
    
    push!(manifest_lines, "# Generated Instance Manifest")
    push!(manifest_lines, "")
    push!(manifest_lines, "Generated: $(Dates.now())")
    push!(manifest_lines, "Base seed: $base_seed")
    push!(manifest_lines, "Number of instances: $num_instances")
    push!(manifest_lines, "")
    push!(manifest_lines, "| Instance | Networks | Proportion | Cost Scale | Nodes | Links | Seed |")
    push!(manifest_lines, "|----------|----------|------------|------------|-------|-------|------|")
    
    for i in 1:num_instances
        # Cycle through parameters
        param_idx = ((i - 1) % length(params)) + 1
        (num_nets, prop, cost_scale) = params[param_idx]
        
        # Set seed for network selection
        seed = base_seed + i
        Random.seed!(seed)
        
        # Select random base networks
        selected_networks = String[]
        while length(selected_networks) < num_nets
            net = rand(SNDLIB_NETWORKS)
            if !(net in selected_networks)
                push!(selected_networks, net)
            end
        end
        sort!(selected_networks)
        
        # Calculate target sizes
        target_sizes = [max(3, floor(Int, NETWORK_SIZES[net] * prop)) for net in selected_networks]
        
        # Generate instance
        file_path = generate_single_instance(
            i, base_seed;
            num_networks_range=[num_nets],
            proportion_range=[prop],
            cost_scale_factors=[cost_scale],
            output_dir=output_dir,
            sndlib_dir=sndlib_dir
        )
        
        push!(generated_files, file_path)
        
        # Parse generated filename to get actual stats
        filename = basename(file_path)
        if occursin(r"instance_(\d+)_n(\d+)_s(\d+)_seed(\d+)", filename)
            m = match(r"instance_(\d+)_n(\d+)_s(\d+)_seed(\d+)", filename)
            inst_num, num_n, num_s, inst_seed = m.captures
            # Get node count from file
            net = read_sndlib_network(file_path)
            num_nodes = length(net.network_structure.nodes)
            
            # Add to manifest
            push!(manifest_lines, "| $filename | $num_n | $(round(prop, digits=2)) | $cost_scale | $num_nodes | $num_s | $inst_seed |")
        end
    end
    
    # Write manifest
    manifest_path = joinpath(output_dir, manifest_file)
    open(manifest_path, "w") do io
        for line in manifest_lines
            println(io, line)
        end
    end
    
    println("\nGeneration complete!")
    println("Manifest written to: $manifest_path")
    
    return generated_files
end
