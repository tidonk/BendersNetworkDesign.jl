"""
Test instance generation framework.

Tests combining networks (abilene + atlanta) and verifies feasibility.
"""

include("common.jl")

using CSV
using DataFrames

@testset "Instance Generation" begin
    @testset "Load individual networks" begin
        abilene = read_sndlib_network(joinpath(DATA_DIR, "sndlib", "abilene.xml"))
        atlanta = read_sndlib_network(joinpath(DATA_DIR, "sndlib", "atlanta.xml"))
        
        @test length(abilene.network_structure.nodes) == 12
        @test length(atlanta.network_structure.nodes) == 15
        @test !isempty(abilene.demands)
        @test !isempty(atlanta.demands)
    end
    
    @testset "Graph connectivity utilities" begin
        abilene = read_sndlib_network(joinpath(DATA_DIR, "sndlib", "abilene.xml"))
        
        # Test degree computation
        degrees = compute_node_degrees(abilene)
        @test length(degrees) == length(abilene.network_structure.nodes)
        @test all(d >= 0 for d in values(degrees))
        
        # Test connectivity check
        @test is_network_connected(abilene)
        
        # Test average degree
        avg_degree = compute_average_degree(abilene)
        @test avg_degree > 0.0
        @test avg_degree <= 2 * length(abilene.network_structure.links) / length(abilene.network_structure.nodes)
        
        # Test high-degree nodes
        hubs = get_high_degree_nodes(abilene, 3)
        @test length(hubs) == 3
        @test all(haskey(abilene.network_structure.nodes, hub) for hub in hubs)
    end
    
    @testset "Network subgraph extraction" begin
        abilene = read_sndlib_network(joinpath(DATA_DIR, "sndlib", "abilene.xml"))
        
        # Extract subgraph with 6 nodes
        subgraph = extract_subgraph(abilene, 6; seed=42)
        
        @test length(subgraph.network_structure.nodes) <= 6
        @test length(subgraph.network_structure.nodes) > 0
        @test is_network_connected(subgraph)
        
        # Verify all links connect nodes in the subgraph
        node_ids = Set(keys(subgraph.network_structure.nodes))
        for link in values(subgraph.network_structure.links)
            @test link.source in node_ids
            @test link.target in node_ids
        end
        
        # Verify all demands connect nodes in the subgraph
        for demand in values(subgraph.demands)
            @test demand.source in node_ids
            @test demand.target in node_ids
        end
    end
    
    @testset "Network prefixing" begin
        abilene = read_sndlib_network(joinpath(DATA_DIR, "sndlib", "abilene.xml"))
        
        prefixed = add_prefix_to_network(abilene, "A_")
        
        # Check all nodes have prefix
        @test all(startswith(node_id, "A_") for node_id in keys(prefixed.network_structure.nodes))
        
        # Check all links have prefix
        @test all(startswith(link_id, "A_") for link_id in keys(prefixed.network_structure.links))
        
        # Check link endpoints have prefix
        for link in values(prefixed.network_structure.links)
            @test startswith(link.source, "A_")
            @test startswith(link.target, "A_")
        end
        
        # Check all demands have prefix
        @test all(startswith(demand_id, "A_") for demand_id in keys(prefixed.demands))
        
        # Check demand endpoints have prefix
        for demand in values(prefixed.demands)
            @test startswith(demand.source, "A_")
            @test startswith(demand.target, "A_")
        end
    end
    
    @testset "Combine abilene + atlanta (full networks)" begin
        abilene_path = joinpath(DATA_DIR, "sndlib", "abilene.xml")
        atlanta_path = joinpath(DATA_DIR, "sndlib", "atlanta.xml")
        
        combined = combine_sndlib_instances(
            [abilene_path, atlanta_path],
            ["abilene_", "atlanta_"]
        )
        
        # Basic structural checks
        @test !isempty(combined.network_structure.nodes)
        @test !isempty(combined.network_structure.links)
        @test !isempty(combined.demands)
        
        # Should have nodes from both networks (27 total)
        @test length(combined.network_structure.nodes) == 27  # 12 + 15
        
        # Check prefix separation
        abilene_nodes = [n for n in keys(combined.network_structure.nodes) if startswith(n, "abilene_")]
        atlanta_nodes = [n for n in keys(combined.network_structure.nodes) if startswith(n, "atlanta_")]
        @test length(abilene_nodes) == 12
        @test length(atlanta_nodes) == 15
        
        # Should have interconnection links (look for "inter_" links)
        inter_links = [l for l in keys(combined.network_structure.links) if startswith(l, "inter_")]
        @test !isempty(inter_links)
        @test iseven(length(inter_links))  # Bidirectional links come in pairs
        
        # Verify connectivity
        @test is_network_connected(combined)
        
        println("Combined network stats:")
        println("  Nodes: $(length(combined.network_structure.nodes))")
        println("  Links: $(length(combined.network_structure.links))")
        println("  Demands: $(length(combined.demands))")
        println("  Inter-network links: $(length(inter_links))")
    end
    
    @testset "Combine abilene + atlanta (subgraphs)" begin
        abilene_path = joinpath(DATA_DIR, "sndlib", "abilene.xml")
        atlanta_path = joinpath(DATA_DIR, "sndlib", "atlanta.xml")
        
        combined = combine_sndlib_instances(
            [abilene_path, atlanta_path],
            ["A_", "B_"],
            target_sizes=[6, 8],
            seed=42
        )
        
        # Should have approximately 14 nodes (6 + 8)
        @test length(combined.network_structure.nodes) <= 14
        @test length(combined.network_structure.nodes) >= 10  # Allow some variance
        
        # Verify connectivity
        @test is_network_connected(combined)
        
        # Verify demands exist
        @test !isempty(combined.demands)
        
        println("Combined subgraph stats:")
        println("  Nodes: $(length(combined.network_structure.nodes))")
        println("  Links: $(length(combined.network_structure.links))")
        println("  Demands: $(length(combined.demands))")
    end
    
    @testset "Combined network feasibility" begin
        # Test that we can solve the combined network
        abilene_path = joinpath(DATA_DIR, "sndlib", "abilene.xml")
        atlanta_path = joinpath(DATA_DIR, "sndlib", "atlanta.xml")
        
        combined = combine_sndlib_instances(
            [abilene_path, atlanta_path],
            ["A_", "B_"],
            target_sizes=[6, 6],
            seed=123
        )
        
        # Balance the network (ensure capacities are reasonable)
        balanced = balance_combined_network(combined)
        
        @test !isempty(balanced.network_structure.nodes)
        @test !isempty(balanced.demands)
        
        # Generate scenarios
        scenarios = generate_outage_scenarios(balanced; include_base_case=true)
        @test !isempty(scenarios)
        
        # Load settings
        settings_file = joinpath(@__DIR__, "../settings/test/test_static.toml")
        settings = read_settings(settings_file)
        
        # Override to use shorter time limit and fewer scenarios
        settings = Settings(
            settings.solver,
            settings.optimizer,
            "benders",  # Use Benders
            min(5, length(scenarios)-1),  # Limit scenarios
            42,  # seed
            60.0,  # 60s time limit
            settings.subproblem_ordering,
            settings.scoring_weights,
            settings.scoring_random_seed,
            settings.scale_score,
            settings.selection_strategy,
            settings.cut_limit,
            settings.consecutive_miss,
            settings.min_score_threshold,
            settings.iteration_time_limit,
            settings.score_initialization_enabled,
            settings.stabilization_frequency,
            settings.root_node_stabilization,
            settings.adaptive_mode,
            settings.adaptive_phase_large_gap,
            settings.adaptive_phase_medium_gap,
            settings.adaptive_phase_early_cuts,
            settings.adaptive_phase_middle_cuts,
            settings.adaptive_phase_late_cuts,
            settings.adaptive_progress_base_cuts,
            settings.adaptive_progress_min_cuts,
            settings.adaptive_progress_max_cuts,
            settings.adaptive_progress_factor,
            settings.adaptive_progress_low_threshold,
            settings.adaptive_progress_high_threshold,
            settings.adaptive_progress_stagnation_rounds,
            settings.adaptive_progress_movement_factor,
            settings.adaptive_progress_stagnation_factor,
            settings.adaptive_time_base_cuts,
            settings.adaptive_time_min_cuts,
            settings.adaptive_time_max_cuts,
            settings.adaptive_time_master_threshold,
            settings.adaptive_time_subproblem_threshold,
            settings.adaptive_time_decrease_factor,
            settings.adaptive_time_increase_factor,
            settings.cut_filtering_strategy,
            settings.cut_filtering_max_cuts,
            settings.cut_filtering_efficacy_norm,
            settings.cut_filtering_diversity_threshold,
            settings.cut_filtering_hybrid_weights,
            settings.statistics,
            settings.ml_statistics,
            settings.subproblem_log,
            settings.subproblem_log_success,
            settings.print_solution,
            settings.validate_cuts,
            settings.ml_model_write,
            settings.ml_model_read
        )
        
        # Try to solve (should not error)
        println("\nTesting feasibility by solving combined network...")
        result = solve_benders(balanced; 
                             optimizer=settings.optimizer,
                             outage_scenarios=scenarios[1:min(6, length(scenarios))],
                             settings=settings)
        
        # Verify we got a solution
        @test result.objective_value > 0.0
        @test result.objective_value < Inf
        total_time = result.total_master_time + result.total_callback_time
        @test total_time > 0.0
        
        println("  Solution found!")
        println("  Objective: $(result.objective_value)")
        println("  Time: $(round(total_time, digits=2))s")
        println("  Iterations: $(result.iterations)")
    end
    
    @testset "Network scaling utilities" begin
        abilene = read_sndlib_network(joinpath(DATA_DIR, "sndlib", "abilene.xml"))
        
        # Test demand scaling
        scaled_demands = scale_network_demands(abilene, 2.0)
        original_total = sum(d.demand_value for d in values(abilene.demands))
        scaled_total = sum(d.demand_value for d in values(scaled_demands.demands))
        @test scaled_total ≈ 2.0 * original_total
        
        # Test capacity scaling
        scaled_capacities = scale_network_capacities(abilene, 0.5)
        for (link_id, link) in scaled_capacities.network_structure.links
            original_link = abilene.network_structure.links[link_id]
            # Check that module capacities were scaled (additional_modules is Vector{Tuple{Float64,Float64}})
            if !isempty(link.additional_modules) && !isempty(original_link.additional_modules)
                @test link.additional_modules[1][1] ≈ 0.5 * original_link.additional_modules[1][1]
            end
            # Check preinstalled capacity if present
            if link.preinstalled_capacity !== nothing && original_link.preinstalled_capacity !== nothing
                @test link.preinstalled_capacity ≈ 0.5 * original_link.preinstalled_capacity
            end
        end
        
        # Test normalization
        normalized = normalize_network(abilene; target_avg_demand=20.0)
        avg_demand = sum(d.demand_value for d in values(normalized.demands)) / length(normalized.demands)
        @test avg_demand ≈ 20.0 atol=0.1
    end
    
    @testset "Combine 5 networks to ~25 nodes" begin
        # Select 5 small networks and extract small subgraphs
        # Target: ~5 nodes each for total ~25 nodes
        file_paths = [
            joinpath(DATA_DIR, "sndlib", "abilene.xml"),
            joinpath(DATA_DIR, "sndlib", "atlanta.xml"),
            joinpath(DATA_DIR, "sndlib", "newyork.xml"),
            joinpath(DATA_DIR, "sndlib", "norway.xml"),
            joinpath(DATA_DIR, "sndlib", "geant.xml")
        ]
        
        prefixes = ["abi", "atl", "ny", "nor", "ge"]
        target_sizes = [5, 5, 5, 5, 5]  # 5 nodes each = 25 total
        
        println("\nCombining 5 networks into ~25 node instance...")
        combined = combine_sndlib_instances(
            file_paths,
            prefixes,
            target_sizes=target_sizes,
            seed=12345
        )
        
        # Verify combined network properties
        @test length(combined.network_structure.nodes) >= 20
        @test length(combined.network_structure.nodes) <= 30
        @test !isempty(combined.network_structure.links)
        @test !isempty(combined.demands)
        
        # Check connectivity
        @test is_network_connected(combined)
        
        # Check that all prefixes appear in node IDs
        node_ids = collect(keys(combined.network_structure.nodes))
        for prefix in prefixes
            @test any(startswith(id, prefix) for id in node_ids)
        end
        
        println("Combined 5-network stats:")
        println("  Nodes: $(length(combined.network_structure.nodes))")
        println("  Links: $(length(combined.network_structure.links))")
        println("  Demands: $(length(combined.demands))")
        
        # Test CSV export
        output_dir = mktempdir()
        export_network_to_csv(combined, output_dir, prefix="5net_combined")
        
        # Verify CSV files were created
        @test isfile(joinpath(output_dir, "5net_combined_nodes.csv"))
        @test isfile(joinpath(output_dir, "5net_combined_links.csv"))
        @test isfile(joinpath(output_dir, "5net_combined_demands.csv"))
        
        # Read back and verify content
        nodes_df = CSV.read(joinpath(output_dir, "5net_combined_nodes.csv"), DataFrame)
        links_df = CSV.read(joinpath(output_dir, "5net_combined_links.csv"), DataFrame)
        demands_df = CSV.read(joinpath(output_dir, "5net_combined_demands.csv"), DataFrame)
        
        @test nrow(nodes_df) == length(combined.network_structure.nodes)
        @test nrow(links_df) == length(combined.network_structure.links)
        @test nrow(demands_df) == length(combined.demands)
        
        # Verify data integrity
        @test all(id -> haskey(combined.network_structure.nodes, id), nodes_df.id)
        @test all(id -> haskey(combined.network_structure.links, id), links_df.id)
        @test all(id -> haskey(combined.demands, id), demands_df.id)
        
        println("CSV export validated:")
        println("  Nodes CSV: $(nrow(nodes_df)) rows")
        println("  Links CSV: $(nrow(links_df)) rows")
        println("  Demands CSV: $(nrow(demands_df)) rows")
        
        # Clean up
        rm(output_dir, recursive=true)
    end
end
