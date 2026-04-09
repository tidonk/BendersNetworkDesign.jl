using EzXML

"""
Data structures for SNDlib network format
"""

struct Node
    id::String
    x::Union{Float64, Nothing}
    y::Union{Float64, Nothing}
end

struct Link
    id::String
    source::String
    target::String
    routing_cost::Union{Float64, Nothing}
    setup_cost::Union{Float64, Nothing}
    preinstalled_capacity::Union{Float64, Nothing}
    preinstalled_cost::Union{Float64, Nothing}
    additional_modules::Vector{Tuple{Float64, Float64}}  # (capacity, cost)
end

struct Demand
    id::String
    source::String
    target::String
    routing_unit::Union{Int, Nothing}
    demand_value::Float64
    max_path_length::Union{Int, Nothing}
    admissible_paths::Vector{Vector{String}}  # list of paths, each path is list of link IDs
end

struct NetworkStructure
    nodes::Dict{String, Node}
    links::Dict{String, Link}
end

struct Meta
    granularity::Union{String, Nothing}
    time::Union{String, Nothing}
    unit::Union{String, Nothing}
    origin::Union{String, Nothing}
    filename::String  # Original source filename
end

struct SNDlibNetwork
    meta::Union{Meta, Nothing}
    network_structure::NetworkStructure
    demands::Dict{String, Demand}
end

"""
    read_sndlib_network(filepath::String) -> SNDlibNetwork

Read an SNDlib network XML file and return a structured representation.
"""
function read_sndlib_network(filepath::String)::SNDlibNetwork
    doc = readxml(filepath)
    root = doc.root
    
    # Parse meta information (optional)
    meta = nothing
    meta_elem = findfirst("//x:meta", root, ["x" => namespace(root)])
    if meta_elem !== nothing
        granularity = nothing
        time = nothing
        unit = nothing
        origin = nothing
        
        gran_elem = findfirst("x:granularity", meta_elem, ["x" => namespace(root)])
        gran_elem !== nothing && (granularity = nodecontent(gran_elem))
        
        time_elem = findfirst("x:time", meta_elem, ["x" => namespace(root)])
        time_elem !== nothing && (time = nodecontent(time_elem))
        
        unit_elem = findfirst("x:unit", meta_elem, ["x" => namespace(root)])
        unit_elem !== nothing && (unit = nodecontent(unit_elem))
        
        origin_elem = findfirst("x:origin", meta_elem, ["x" => namespace(root)])
        origin_elem !== nothing && (origin = nodecontent(origin_elem))
        
        meta = Meta(granularity, time, unit, origin, basename(filepath))
    else
        # If no meta element in XML, create one with just the filename
        meta = Meta(nothing, nothing, nothing, nothing, basename(filepath))
    end
    
    # Parse network structure
    network_structure_elem = findfirst("//x:networkStructure", root, ["x" => namespace(root)])
    
    # Parse nodes
    nodes = Dict{String, Node}()
    nodes_elem = findfirst("x:nodes", network_structure_elem, ["x" => namespace(root)])
    for node_elem in findall("x:node", nodes_elem, ["x" => namespace(root)])
        node_id = node_elem["id"]
        
        x = nothing
        y = nothing
        coords_elem = findfirst("x:coordinates", node_elem, ["x" => namespace(root)])
        if coords_elem !== nothing
            x_elem = findfirst("x:x", coords_elem, ["x" => namespace(root)])
            y_elem = findfirst("x:y", coords_elem, ["x" => namespace(root)])
            x_elem !== nothing && (x = parse(Float64, nodecontent(x_elem)))
            y_elem !== nothing && (y = parse(Float64, nodecontent(y_elem)))
        end
        
        nodes[node_id] = Node(node_id, x, y)
    end
    
    # Parse links
    links = Dict{String, Link}()
    links_elem = findfirst("x:links", network_structure_elem, ["x" => namespace(root)])
    for link_elem in findall("x:link", links_elem, ["x" => namespace(root)])
        link_id = link_elem["id"]
        
        source = nodecontent(findfirst("x:source", link_elem, ["x" => namespace(root)]))
        target = nodecontent(findfirst("x:target", link_elem, ["x" => namespace(root)]))
        
        routing_cost = nothing
        rc_elem = findfirst("x:routingCost", link_elem, ["x" => namespace(root)])
        rc_elem !== nothing && (routing_cost = parse(Float64, nodecontent(rc_elem)))
        
        setup_cost = nothing
        sc_elem = findfirst("x:setupCost", link_elem, ["x" => namespace(root)])
        sc_elem !== nothing && (setup_cost = parse(Float64, nodecontent(sc_elem)))
        
        preinstalled_capacity = nothing
        preinstalled_cost = nothing
        preinstalled_elem = findfirst("x:preInstalledModule", link_elem, ["x" => namespace(root)])
        if preinstalled_elem !== nothing
            cap_elem = findfirst("x:capacity", preinstalled_elem, ["x" => namespace(root)])
            cost_elem = findfirst("x:cost", preinstalled_elem, ["x" => namespace(root)])
            cap_elem !== nothing && (preinstalled_capacity = parse(Float64, nodecontent(cap_elem)))
            cost_elem !== nothing && (preinstalled_cost = parse(Float64, nodecontent(cost_elem)))
        end
        
        additional_modules = Tuple{Float64, Float64}[]
        add_modules_elem = findfirst("x:additionalModules", link_elem, ["x" => namespace(root)])
        if add_modules_elem !== nothing
            for module_elem in findall("x:addModule", add_modules_elem, ["x" => namespace(root)])
                cap = parse(Float64, nodecontent(findfirst("x:capacity", module_elem, ["x" => namespace(root)])))
                cost = parse(Float64, nodecontent(findfirst("x:cost", module_elem, ["x" => namespace(root)])))
                push!(additional_modules, (cap, cost))
            end
        end
        
        links[link_id] = Link(link_id, source, target, routing_cost, setup_cost, 
                             preinstalled_capacity, preinstalled_cost, additional_modules)
    end
    
    network_structure = NetworkStructure(nodes, links)
    
    # Parse demands
    demands = Dict{String, Demand}()
    demands_elem = findfirst("//x:demands", root, ["x" => namespace(root)])
    for demand_elem in findall("x:demand", demands_elem, ["x" => namespace(root)])
        demand_id = demand_elem["id"]
        
        source = nodecontent(findfirst("x:source", demand_elem, ["x" => namespace(root)]))
        target = nodecontent(findfirst("x:target", demand_elem, ["x" => namespace(root)]))
        demand_value = parse(Float64, nodecontent(findfirst("x:demandValue", demand_elem, ["x" => namespace(root)])))
        
        routing_unit = nothing
        ru_elem = findfirst("x:routingUnit", demand_elem, ["x" => namespace(root)])
        ru_elem !== nothing && (routing_unit = parse(Int, nodecontent(ru_elem)))
        
        max_path_length = nothing
        mpl_elem = findfirst("x:maxPathLength", demand_elem, ["x" => namespace(root)])
        mpl_elem !== nothing && (max_path_length = parse(Int, nodecontent(mpl_elem)))
        
        admissible_paths = Vector{String}[]
        adm_paths_elem = findfirst("x:admissiblePaths", demand_elem, ["x" => namespace(root)])
        if adm_paths_elem !== nothing
            for path_elem in findall("x:admissiblePath", adm_paths_elem, ["x" => namespace(root)])
                path = String[]
                for link_id_elem in findall("x:linkId", path_elem, ["x" => namespace(root)])
                    push!(path, nodecontent(link_id_elem))
                end
                push!(admissible_paths, path)
            end
        end
        
        demands[demand_id] = Demand(demand_id, source, target, routing_unit, 
                                    demand_value, max_path_length, admissible_paths)
    end
    
    return SNDlibNetwork(meta, network_structure, demands)
end
