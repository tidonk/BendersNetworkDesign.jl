"""
Tests for multi-regressor ML scoring system.

Tests feature extraction, k-hop neighborhoods, training, prediction,
and aggregated metrics.
"""

using Test

# Get workspace root directory (test/ is one level down from code/)
workspace_root = dirname(@__DIR__)

# Load common test utilities
include(joinpath(workspace_root, "test", "common.jl"))

@testset "Multi-Regressor ML Scoring" begin
    
    @testset "FeatureConfig" begin
        # Test default configuration
        config = FeatureConfig()
        @test config.failed_link_metrics == true
        @test config.failed_link_centrality == true
        @test config.khop_capacity == true
        @test config.khop_flow == true
        @test config.khop_utilization == true
        @test config.score_metrics == true
        
        # Test feature counting (all enabled: 3+1+4+4+4+5 = 21)
        @test count_features(config) == 21
        
        # Test partial configuration
        config_partial = FeatureConfig(
            failed_link_metrics=true,
            failed_link_centrality=false,
            khop_capacity=false,
            khop_flow=false,
            khop_utilization=false,
            score_metrics=true
        )
        @test count_features(config_partial) == 8  # 3 + 5
    end
    
    @testset "Adjacency List" begin
        # Load test network (use correct path relative to code/)
        network_path = joinpath(workspace_root, "..", "data", "sndlib", "abilene.xml")
        if !isfile(network_path)
            # Try alternative path
            network_path = joinpath(workspace_root, "data", "sndlib", "abilene.xml")
        end
        network = read_sndlib_network(network_path)
        
        # Build adjacency list
        adjacency = build_adjacency_list(network.network_structure.nodes, 
                                        network.network_structure.links)
        
        # Check all nodes present
        @test length(adjacency) == length(network.network_structure.nodes)
        
        # Check bidirectional edges
        for (link_id, link) in network.network_structure.links
            @test link.target in adjacency[link.source]
            @test link.source in adjacency[link.target]
        end
    end
    
    @testset "k-hop Neighborhoods" begin
        # Create simple test graph: A -- B -- C -- D
        #                           |         |
        #                           +----E----+
        nodes = Dict(
            "A" => nothing, "B" => nothing, "C" => nothing, 
            "D" => nothing, "E" => nothing
        )
        adjacency = Dict{String,Vector{String}}(
            "A" => ["B", "E"],
            "B" => ["A", "C"],
            "C" => ["B", "D", "E"],
            "D" => ["C"],
            "E" => ["A", "C"]
        )
        
        # Test 1-hop from A
        neighbors_1 = get_khop_neighbors("A", adjacency, 1)
        @test Set(neighbors_1) == Set(["B", "E"])
        
        # Test 2-hop from A
        neighbors_2 = get_khop_neighbors("A", adjacency, 2)
        @test Set(neighbors_2) == Set(["B", "E", "C"])
        
        # Test 3-hop from A (should reach all)
        neighbors_3 = get_khop_neighbors("A", adjacency, 3)
        @test Set(neighbors_3) == Set(["B", "E", "C", "D"])
        
        # Test k=0 (empty)
        neighbors_0 = get_khop_neighbors("A", adjacency, 0)
        @test isempty(neighbors_0)
    end
    
    @testset "k-hop Link Neighborhoods" begin
        # Load test network (use correct path)
        network_path = joinpath(workspace_root, "..", "data", "sndlib", "abilene.xml")
        if !isfile(network_path)
            network_path = joinpath(workspace_root, "data", "sndlib", "abilene.xml")
        end
        network = read_sndlib_network(network_path)
        links = network.network_structure.links
        adjacency = build_adjacency_list(network.network_structure.nodes, links)
        
        # Get first link
        first_link_id = first(keys(links))
        
        # Get 1-hop neighborhood
        neighborhood_links = get_links_in_khop_neighborhood(
            first_link_id, links, adjacency, 1
        )
        
        # Should have some neighbors but not include self
        @test length(neighborhood_links) >= 0
        @test !(first_link_id in neighborhood_links)
        
        # 2-hop should have more links than 1-hop
        neighborhood_links_2 = get_links_in_khop_neighborhood(
            first_link_id, links, adjacency, 2
        )
        @test length(neighborhood_links_2) >= length(neighborhood_links)
    end
    
    @testset "Statistics Computation" begin
        # Test with non-empty values
        values = [1.0, 2.0, 3.0, 4.0, 5.0]
        avg, std_val, min_val, max_val = compute_khop_stats(values)
        
        @test avg == 3.0
        @test min_val == 1.0
        @test max_val == 5.0
        @test std_val > 0.0
        
        # Test with single value
        single_value = [5.0]
        avg, std_val, min_val, max_val = compute_khop_stats(single_value)
        @test avg == 5.0
        @test std_val == 0.0
        @test min_val == 5.0
        @test max_val == 5.0
        
        # Test with empty values
        empty_values = Float64[]
        avg, std_val, min_val, max_val = compute_khop_stats(empty_values)
        @test avg == 0.0
        @test std_val == 0.0
        @test min_val == 0.0
        @test max_val == 0.0
    end
    
    @testset "MultiRegressorML Creation" begin
        n_scenarios = 10
        
        # Default configuration
        model = MultiRegressorML(n_scenarios)
        @test length(model.regressors) == n_scenarios
        @test model.n_features == 21  # All features enabled
        @test model.khop_distance == 2
        
        # Custom configuration
        custom_config = FeatureConfig(
            failed_link_metrics=true,
            failed_link_centrality=true,
            khop_capacity=false,
            khop_flow=false,
            khop_utilization=false,
            score_metrics=true
        )
        model_custom = MultiRegressorML(n_scenarios; feature_config=custom_config)
        @test model_custom.n_features == 9  # 3+1+5
        
        # Check all regressors initialized
        for scenario_id in 1:n_scenarios
            @test haskey(model.regressors, scenario_id)
            @test model.regressors[scenario_id].n_features == 21
        end
    end
    
    @testset "Feature Extraction" begin
        # Load test network (use correct path)
        network_path = joinpath(workspace_root, "..", "data", "sndlib", "abilene.xml")
        if !isfile(network_path)
            network_path = joinpath(workspace_root, "data", "sndlib", "abilene.xml")
        end
        network = read_sndlib_network(network_path)
        
        # Build required structures
        link_list = collect(keys(network.network_structure.links))
        link_modules = Dict{String,Vector{Tuple{Int,Float64,Float64}}}()
        for (link_id, link) in network.network_structure.links
            modules = Tuple{Int,Float64,Float64}[]
            for (idx, (cap, cost)) in enumerate(link.additional_modules)
                push!(modules, (idx, cap, cost))
            end
            link_modules[link_id] = modules
        end
        
        # Create dummy solution
        y_values = Dict{Tuple{String,Int},Float64}()
        for (link_id, mods) in link_modules
            for m in eachindex(mods)
                y_values[(link_id, m)] = 0.0
            end
        end
        
        # Create dummy flow solution
        f_base_values = Dict{Tuple{String,Tuple{String,Symbol}},Float64}()
        for (demand_id, demand) in network.demands
            for link_id in link_list
                f_base_values[(demand_id, (link_id, :forward))] = 0.0
                f_base_values[(demand_id, (link_id, :backward))] = 0.0
            end
        end
        
        # Build adjacency
        adjacency = build_adjacency_list(network.network_structure.nodes, 
                                        network.network_structure.links)
        
        # Create subproblem scores
        subproblem_scores = Dict{Int,SubproblemScore}()
        subproblem_scores[1] = SubproblemScore()
        
        # Extract features
        config = FeatureConfig()
        features = extract_multi_regressor_features(
            y_values, link_modules, [1], f_base_values, link_list,
            network.network_structure.nodes, network.network_structure.links,
            adjacency, nothing, subproblem_scores, 1, config, 2
        )
        
        # Check feature count matches config
        @test length(features) == count_features(config)
        @test all(isfinite, features)
    end
    
    @testset "Prediction and Training" begin
        # Load test network (use correct path)
        network_path = joinpath(workspace_root, "..", "data", "sndlib", "abilene.xml")
        if !isfile(network_path)
            network_path = joinpath(workspace_root, "data", "sndlib", "abilene.xml")
        end
        network = read_sndlib_network(network_path)
        
        # Generate scenarios
        outage_scenarios = generate_outage_scenarios(network; include_base_case=false)
        n_scenarios = length(outage_scenarios)
        
        # Create model
        model = MultiRegressorML(n_scenarios; khop_distance=1)
        
        # Build required structures
        link_list = collect(keys(network.network_structure.links))
        link_modules = Dict{String,Vector{Tuple{Int,Float64,Float64}}}()
        for (link_id, link) in network.network_structure.links
            modules = Tuple{Int,Float64,Float64}[]
            for (idx, (cap, cost)) in enumerate(link.additional_modules)
                push!(modules, (idx, cap, cost))
            end
            link_modules[link_id] = modules
        end
        
        y_values = Dict{Tuple{String,Int},Float64}()
        for (link_id, mods) in link_modules
            for m in eachindex(mods)
                y_values[(link_id, m)] = rand()
            end
        end
        
        f_base_values = Dict{Tuple{String,Tuple{String,Symbol}},Float64}()
        for (demand_id, demand) in network.demands
            for link_id in link_list
                f_base_values[(demand_id, (link_id, :forward))] = rand() * 10.0
                f_base_values[(demand_id, (link_id, :backward))] = rand() * 10.0
            end
        end
        
        adjacency = build_adjacency_list(network.network_structure.nodes, 
                                        network.network_structure.links)
        
        subproblem_scores = Dict{Int,SubproblemScore}()
        for scenario in outage_scenarios
            subproblem_scores[scenario.id] = SubproblemScore()
        end
        
        # Test prediction (before training)
        scenario = outage_scenarios[1]
        prob = predict_multi_regressor(
            model, scenario.id,
            y_values, link_modules, scenario.failed_link_indices,
            f_base_values, link_list,
            network.network_structure.nodes, network.network_structure.links,
            adjacency, nothing, subproblem_scores
        )
        
        @test 0.0 <= prob <= 1.0
        
        # Train on some scenarios
        for i in 1:min(5, n_scenarios)
            scenario = outage_scenarios[i]
            was_infeasible = rand() > 0.5
            
            train_multi_regressor!(
                model, scenario.id, was_infeasible,
                y_values, link_modules, scenario.failed_link_indices,
                f_base_values, link_list,
                network.network_structure.nodes, network.network_structure.links,
                adjacency, nothing, subproblem_scores
            )
            
            # Check training happened
            @test model.regressors[scenario.id].n_updates > 0
        end
        
        # Predict after training
        prob_trained = predict_multi_regressor(
            model, scenario.id,
            y_values, link_modules, scenario.failed_link_indices,
            f_base_values, link_list,
            network.network_structure.nodes, network.network_structure.links,
            adjacency, nothing, subproblem_scores
        )
        
        @test 0.0 <= prob_trained <= 1.0
    end
    
    @testset "Aggregated Metrics" begin
        n_scenarios = 5
        model = MultiRegressorML(n_scenarios)
        
        # Train each regressor with different outcomes
        for scenario_id in 1:n_scenarios
            regressor = model.regressors[scenario_id]
            
            # Manually update metrics
            regressor.metrics.total_predictions = 10
            regressor.metrics.true_positives = scenario_id
            regressor.metrics.true_negatives = 10 - scenario_id
            regressor.metrics.false_positives = 0
            regressor.metrics.false_negatives = 0
        end
        
        # Get aggregated metrics
        agg = aggregate_metrics(model)
        
        @test agg.total_predictions == 50  # 10 * 5
        @test agg.true_positives == 15  # 1+2+3+4+5
        @test agg.true_negatives == 35  # 9+8+7+6+5
        @test agg.false_positives == 0
        @test agg.false_negatives == 0
    end
    
    @testset "Model Save/Load" begin
        n_scenarios = 3
        model = MultiRegressorML(n_scenarios; khop_distance=1)
        
        # Train a bit
        for scenario_id in 1:n_scenarios
            regressor = model.regressors[scenario_id]
            features = rand(model.n_features)
            BendersNetworkDesign.update!(regressor, features, rand() > 0.5, scenario_id)
        end
        
        # Save model
        tmpfile = tempname() * ".jls"
        save_multi_regressor_model(model, tmpfile)
        @test isfile(tmpfile)
        
        # Load model
        loaded_model = load_multi_regressor_model(tmpfile)
        @test length(loaded_model.regressors) == n_scenarios
        @test loaded_model.n_features == model.n_features
        @test loaded_model.khop_distance == model.khop_distance
        
        # Check regressors have same state
        for scenario_id in 1:n_scenarios
            @test loaded_model.regressors[scenario_id].n_updates == 
                  model.regressors[scenario_id].n_updates
        end
        
        # Clean up
        rm(tmpfile)
    end
end

println("\n✓ All multi-regressor ML tests passed!")
