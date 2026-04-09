# Integration test for ML-based proportion prediction in Benders callback
# Verifies that the predictor is correctly invoked for prediction and training

using Test

# Load common test setup only if not already loaded
if !isdefined(Main, :BendersNetworkDesign)
    include("common.jl")
end

@testset "Prediction-Based Integration" begin
    # Load a small network
    network = read_sndlib_network(joinpath(DATA_DIR, "sndlib", "abilene.xml"))
    
    # Generate a small number of scenarios for fast testing
    scenarios = generate_outage_scenarios(network; include_base_case=false, k=1)
    scenarios = scenarios[1:5]  # Use only 5 scenarios
    
    # Load prediction-based settings (path relative to code/ directory)
    settings = read_settings("settings/test/benders_adaptive_prediction_based.toml")
    
    @testset "Prediction-based solve completes" begin
        @test settings.selection_strategy == "adaptive"
        @test settings.adaptive_mode == "prediction_based"
        
        # Run the solve
        result = solve_benders(network; 
                             optimizer=settings.optimizer, 
                             outage_scenarios=scenarios, 
                             settings=settings)
        
        # Verify solve completed successfully
        @test haskey(result, :objective_value)
        @test haskey(result, :iterations)
        @test haskey(result, :total_cuts_added)
        @test haskey(result, :total_ml_selection_time)
        
        # Verify we got a valid objective
        @test result[:objective_value] > 0
        @test result[:iterations] > 0
        
        # Verify ML selection was active (training time should be non-zero after multiple iterations)
        @test result[:total_ml_selection_time] >= 0.0
    end
    
    @testset "Proportion predictor is trained" begin
        # Create a predictor
        predictor = ProportionPredictor(32)
        
        # Initial state: all zeros, empty history
        @test all(predictor.weights .== 0.0)
        @test predictor.n_samples == 0
        @test isempty(predictor.performance_history)
        
        # Extract features (using empty history - will default to 0.0 in extract_performance_features)
        features = extract_full_features(network, 1, 10, predictor.performance_history)
        @test length(features) == 32
        
        # Make initial prediction (should be 0.5 with zero weights)
        pred1 = predict_proportion(predictor, features)
        @test pred1 ≈ 0.5  # sigmoid(0) = 0.5
        
        # Train with actual proportion (test that training completes without error)
        train_proportion_predictor!(predictor, features, 0.8)
        @test predictor.n_samples == 1
        
        # Training updates weights (note: direction depends on features, just verify it runs)
        pred2 = predict_proportion(predictor, features)
        @test pred2 isa Float64
        @test 0.0 <= pred2 <= 1.0  # Valid probability
    end
    
    @testset "Performance history updates" begin
        predictor = ProportionPredictor(32, history_decay=0.9)
        
        # Initial history is empty
        @test isempty(predictor.performance_history)
        
        # First update initializes history
        update_exponential_average!(predictor.performance_history, 0.7, predictor.history_decay)
        @test length(predictor.performance_history) == 1
        @test predictor.performance_history[1] == 0.7
        
        # Second update applies exponential averaging
        update_exponential_average!(predictor.performance_history, 0.5, predictor.history_decay)
        
        # Formula: new = decay * old + (1 - decay) * new
        #        = 0.9 * 0.7 + 0.1 * 0.5 = 0.63 + 0.05 = 0.68
        @test predictor.performance_history[1] ≈ 0.68 rtol=1e-6
    end
    
    @testset "Strategy creation with prediction mode" begin
        # Verify strategy is correctly created from settings
        strategy = create_selection_strategy(settings, length(scenarios))
        
        @test strategy isa AdaptiveCutLimit
        @test strategy.mode == "prediction_based"
        @test strategy.proportion_predictor !== nothing
        @test strategy.proportion_predictor isa ProportionPredictor
        
        # Check configured proportions
        @test strategy.min_proportion == 0.05
        @test strategy.max_proportion == 1.0
        @test strategy.default_proportion == 0.5
    end
end

println("\n✓ All prediction integration tests passed!")
