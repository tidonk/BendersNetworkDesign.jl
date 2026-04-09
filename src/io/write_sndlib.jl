"""
SNDlib XML network writer.

Exports networks to SNDlib XML format for use with standard solvers and tools.
"""

using EzXML

"""
    write_sndlib_network(network::SNDlibNetwork, filepath::String)

Write a network to an SNDlib XML file.

Creates properly formatted XML with line breaks and indentation for readability.
The output is compatible with the SNDlib format and can be read back using
`read_sndlib_network`.

# Arguments
- `network`: SNDlibNetwork to export
- `filepath`: Path to write the XML file

# Example
```julia
combined = combine_sndlib_instances([...], [...])
write_sndlib_network(combined, "data/generated/combined_network.xml")
```
"""
function write_sndlib_network(network::SNDlibNetwork, filepath::String)::Nothing
    # Create output directory if it doesn't exist
    mkpath(dirname(filepath))
    
    # Create XML document
    doc = XMLDocument()
    
    # Create root element with namespace
    root = ElementNode("network")
    root["xmlns"] = "http://sndlib.zib.de/network"
    root["xmlns:xsi"] = "http://www.w3.org/2001/XMLSchema-instance"
    root["xsi:schemaLocation"] = "http://sndlib.zib.de/network http://sndlib.zib.de/sndlib/network/network.xsd"
    setroot!(doc, root)
    
    # Add meta information
    if network.meta !== nothing
        meta_elem = addelement!(root, "meta")
        network.meta.granularity !== nothing && addelement!(meta_elem, "granularity", network.meta.granularity)
        network.meta.time !== nothing && addelement!(meta_elem, "time", network.meta.time)
        network.meta.unit !== nothing && addelement!(meta_elem, "unit", network.meta.unit)
        network.meta.origin !== nothing && addelement!(meta_elem, "origin", network.meta.origin)
    end
    
    # Add network structure
    network_structure_elem = addelement!(root, "networkStructure")
    
    # Add nodes
    nodes_elem = addelement!(network_structure_elem, "nodes")
    for (node_id, node) in sort(collect(network.network_structure.nodes), by=x->x[1])
        node_elem = addelement!(nodes_elem, "node")
        node_elem["id"] = node_id
        
        if node.x !== nothing && node.y !== nothing
            coords_elem = addelement!(node_elem, "coordinates")
            addelement!(coords_elem, "x", string(node.x))
            addelement!(coords_elem, "y", string(node.y))
        end
    end
    
    # Add links
    links_elem = addelement!(network_structure_elem, "links")
    for (link_id, link) in sort(collect(network.network_structure.links), by=x->x[1])
        link_elem = addelement!(links_elem, "link")
        link_elem["id"] = link_id
        
        addelement!(link_elem, "source", link.source)
        addelement!(link_elem, "target", link.target)
        
        # Add preinstalled module if present
        if link.preinstalled_capacity !== nothing
            preinstalled_elem = addelement!(link_elem, "preInstalledModule")
            addelement!(preinstalled_elem, "capacity", string(link.preinstalled_capacity))
            if link.preinstalled_cost !== nothing
                addelement!(preinstalled_elem, "cost", string(link.preinstalled_cost))
            end
        end
        
        # Add routing cost if present
        link.routing_cost !== nothing && addelement!(link_elem, "routingCost", string(link.routing_cost))
        
        # Add setup cost if present
        link.setup_cost !== nothing && addelement!(link_elem, "setupCost", string(link.setup_cost))
        
        # Add additional modules
        if !isempty(link.additional_modules)
            add_modules_elem = addelement!(link_elem, "additionalModules")
            for (capacity, cost) in link.additional_modules
                module_elem = addelement!(add_modules_elem, "addModule")
                addelement!(module_elem, "capacity", string(capacity))
                addelement!(module_elem, "cost", string(cost))
            end
        end
    end
    
    # Add demands
    demands_elem = addelement!(root, "demands")
    for (demand_id, demand) in sort(collect(network.demands), by=x->x[1])
        demand_elem = addelement!(demands_elem, "demand")
        demand_elem["id"] = demand_id
        
        addelement!(demand_elem, "source", demand.source)
        addelement!(demand_elem, "target", demand.target)
        addelement!(demand_elem, "demandValue", string(demand.demand_value))
        
        # Add routing unit if present
        demand.routing_unit !== nothing && addelement!(demand_elem, "routingUnit", string(demand.routing_unit))
        
        # Add max path length if present
        demand.max_path_length !== nothing && addelement!(demand_elem, "maxPathLength", string(demand.max_path_length))
    end
    
    # Write to file with pretty printing
    open(filepath, "w") do io
        prettyprint(io, doc)
    end
    
    @info "Exported network to SNDlib XML: $filepath"
    @info "  Nodes: $(length(network.network_structure.nodes))"
    @info "  Links: $(length(network.network_structure.links))"
    @info "  Demands: $(length(network.demands))"
    
    return nothing
end
