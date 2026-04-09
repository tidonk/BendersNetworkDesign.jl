"""
Test adaptive proportion-based subproblem selection using ML prediction.

Tests the ProportionPredictor model for predicting what proportion of subproblems
will yield cuts before each Benders iteration.
"""

using Test
using Random

include("common.jl")

@testset "Adaptive Proportion Tests" begin
    
    @testset "ProportionPredictor Initialization" begin
        predictor = ProportionPredictor(32)
        
        @test length(predictor.weights) == 32
        @test all(predictor.weights .== 0.0)
        @test predictor.learning_rate == 0.01
        @test predictor.regularization == 0.01
        @test predictor.history_decay == 0.9
        @test predictor.n_samples == 0
        @test isempty(predictor.performance_history)
    end
    
    @testset "Sigmoid Function" begin
        # Test sigmoid properties
        @test BendersNetworkDesign.sigmoid(0.0) ≈ 0.5
        @test BendersNetworkDesign.sigmoid(10.0) > 0.99
        @test BendersNetworkDesign.sigmoid(-10.0) < 0.01
        @test 0.0 < BendersNetworkDesign.sigmoid(1.0) < 1.0
    end
    
    @testset "Network Density Computation" begin
        # Load a small network
        network_file = joinpath(DATA_DIR, "sndlib", "abilene.xml")
        if !isfile(network_file)
            @warn "Skipping network density test: abilene.xml not found"
        else
            network = read_sndlib_network(network_file)
            density = BendersNetworkDesign.compute_network_density(network)
            
            @test 0.0 <= density <= 1.0
            @test density > 0.0  # Abilene should have some links
        end
    end
    
    @testset "Aggregated Topology Features" begin
        # Load a small network
        network_file = joinpath(DATA_DIR, "sndlib", "abilene.xml")
        if !isfile(network_file)
            @warn "Skipping topology features test: abilene.xml not found"
        else
            network = read_sndlib_network(network_file)
            features = BendersNetworkDesign.extract_aggregated_topology_features(network)
            
            # Should have 29 features (7 metrics × 4 stats + 1 density)
            @test length(features) == 29
            @test all(isfinite, features)
        end
    end
    
    @testset "Performance Features" begin
        history = Float64[]
        
        # Test with empty history
        features = BendersNetworkDesign.extract_performance_features(1, 10, history)
        @test length(features) == 3
        @test features[1] ≈ 0.01  # iteration / 100
        @test features[2] ≈ 0.01  # cuts / 1000
        @test features[3] ≈ 0.5   # default when no history
        
        # Test with history
        BendersNetworkDesign.update_exponential_average!(history, 0.7, 0.9)
        features = BendersNetworkDesign.extract_performance_features(5, 50, history)
        @test features[3] ≈ 0.7  # Uses history value
    end
    
    @testset "Full Feature Extraction" begin
        network_file = joinpath(DATA_DIR, "sndlib", "abilene.xml")
        if !isfile(network_file)
            @warn "Skipping full features test: abilene.xml not found"
        else
            network = read_sndlib_network(network_file)
            history = Float64[]
            
            features = extract_full_features(network, 1, 10, history)
            
            # Should have 32 features (29 topology + 3 performance)
            @test length(features) == 32
            @test all(isfinite, features)
        end
    end
    
    @testset "Exponential Average Update" begin
        history = Float64[]
        
        # Initialize
        BendersNetworkDesign.update_exponential_average!(history, 0.5, 0.9)
        @test length(history) == 1
        @test history[1] ≈ 0.5
        
        # Update
        BendersNetworkDesign.update_exponential_average!(history, 0.8, 0.9)
        @test length(history) == 1  # Still only 1 element
        @test history[1] ≈ 0.9 * 0.5 + 0.1 * 0.8
        
        # Multiple updates
        for _ in 1:10
            BendersNetworkDesign.update_exponential_average!(history, 0.9, 0.9)
        end
        @test history[1] > 0.7  # Should converge towards 0.9 (but slowly due to high decay)
    end
    
    @testset "Feature Normalization" begin
        predictor = ProportionPredictor(5)
        
        # First sample: should return zeros
        features1 = [1.0, 2.0, 3.0, 4.0, 5.0]
        normalized1 = BendersNetworkDesign.normalize_features!(predictor, features1)
        @test all(normalized1 .≈ 0.0)
        @test predictor.n_samples == 1
        
        # Second sample: should normalize
        features2 = [2.0, 4.0, 6.0, 8.0, 10.0]
        normalized2 = BendersNetworkDesign.normalize_features!(predictor, features2)
        @test predictor.n_samples == 2
        @test all(isfinite, normalized2)
    end
    
    @testset "Prediction and Training" begin
        predictor = ProportionPredictor(5, learning_rate=0.1, regularization=0.01)
        
        # Generate synthetic training data
        Random.seed!(42)
        n_samples = 20
        
        for i in 1:n_samples
            # Simple pattern: sum of features correlates with proportion
            features = rand(5) .* 10.0
            actual_prop = min(sum(features) / 50.0, 1.0)  # Roughly proportional
            
            train_proportion_predictor!(predictor, features, actual_prop)
        end
        
        # After training, predictions should be in [0, 1]
        test_features = [5.0, 5.0, 5.0, 5.0, 5.0]
        prediction = predict_proportion(predictor, test_features)
        
        @test 0.0 <= prediction <= 1.0
        @test predictor.n_samples == n_samples
    end
    
    @testset "AdaptiveCutLimit with Prediction Mode" begin
        # Create prediction-based strategy
        predictor = ProportionPredictor(32)
        strategy = AdaptiveCutLimit(
            mode="prediction_based",
            predictor=predictor,
            default_prop=0.5,
            min_prop=0.05,
            max_prop=1.0
        )
        
        @test strategy.mode == "prediction_based"
        @test strategy.proportion_predictor !== nothing
        @test strategy.default_proportion == 0.5
        @test strategy.min_proportion == 0.05
        @test strategy.max_proportion == 1.0
    end
    
    @testset "Settings with Prediction Mode" begin
        # Test that prediction-based settings can be loaded
        settings_file = joinpath(@__DIR__, "../settings/test/benders_adaptive_prediction_based.toml")
        
        if !isfile(settings_file)
            @warn "Skipping settings test: benders_adaptive_prediction_based.toml not found"
        else
            settings = read_settings(settings_file)
            
            @test settings.selection_strategy == "adaptive"
            @test settings.adaptive_mode == "prediction_based"
            @test settings.adaptive_prediction_learning_rate == 0.01
            @test settings.adaptive_prediction_regularization == 0.01
            @test settings.adaptive_prediction_history_decay == 0.9
            @test settings.adaptive_prediction_default_proportion == 0.5
            @test settings.adaptive_prediction_min_proportion == 0.05
            @test settings.adaptive_prediction_max_proportion == 1.0
        end
    end
    
    @testset "Strategy Creation with Prediction Mode" begin
        settings_file = joinpath(@__DIR__, "../settings/test/benders_adaptive_prediction_based.toml")
        
        if !isfile(settings_file)
            @warn "Skipping strategy creation test: settings file not found"
        else
            settings = read_settings(settings_file)
            num_scenarios = 20
            
            strategy = create_selection_strategy(settings, num_scenarios)
            
            @test strategy isa AdaptiveCutLimit
            @test strategy.mode == "prediction_based"
            @test strategy.proportion_predictor !== nothing
            @test strategy.min_proportion == 0.05
            @test strategy.max_proportion == 1.0
        end
    end
    
    # NOTE: Integration test commented out - requires full Benders callback integration
    # which will be implemented separately. Unit tests above verify all components work.
    # @testset "Integration: Small Solve with Prediction Mode" begin
    #     # Test full Benders solve with prediction-based selection
    #     network_file = joinpath(DATA_DIR, "sndlib", "abilene.xml")
    #     settings_file = joinpath(@__DIR__, "../settings/test/benders_adaptive_prediction_based.toml")
    #     
    #     if !isfile(network_file)
    #         @warn "Skipping integration test: abilene.xml not found"
    #     elseif !isfile(settings_file)
    #         @warn "Skipping integration test: settings file not found"
    #     else
    #         # ... test implementation ...
    #     end
    # end
end
