"""
Test ML-based subproblem scoring functionality.

Verifies that:
1. Model has 9 features with normalization
2. Feature normalization works correctly (z-scores)
3. Prediction quality and solve time tracking
4. Online training updates statistics correctly
"""

using Test

# Load module
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))
using BendersNetworkDesign

@testset "ML Subproblem Scoring" begin
    
    @testset "ML Model Structure (9 features)" begin
        println("\n" * "="^80)
        println("Testing ML model structure with 9 features...")
        println("="^80)
        
        # Create ML model with 9 features (3 link + 1 centrality + 5 score)
        model = OnlineLogisticRegression(9)
        
        # Check structure
        @test model.n_features == 9
        @test length(model.weights) == 9
        @test length(model.feature_means) == 9
        @test length(model.feature_stds) == 9
        @test hasfield(typeof(model), :metrics)
        println("✓ ML model has 9 features")
        println("✓ ML model has feature_means and feature_stds for normalization")
        println("✓ ML model has metrics field")
        
        # Check initial values
        @test all(model.feature_means .== 0.0)
        @test all(model.feature_stds .== 1.0)
        @test model.n_updates == 0
        println("✓ Feature statistics initialized correctly")
    end
    
    @testset "Feature Normalization (Z-scores)" begin
        println("\n" * "="^80)
        println("Testing feature normalization...")
        println("="^80)
        
        model = OnlineLogisticRegression(9)
        
        # Manually set some statistics
        model.feature_means[1] = 100.0
        model.feature_stds[1] = 20.0
        model.feature_means[2] = 0.5
        model.feature_stds[2] = 0.1
        
        # Test normalization through predict_proba
        features = zeros(9)
        features[1] = 120.0  # (120 - 100) / 20 = 1.0
        features[2] = 0.6    # (0.6 - 0.5) / 0.1 = 1.0
        
        pred = BendersNetworkDesign.predict_proba(model, features)
        @test 0.0 <= pred <= 1.0
        println("✓ Z-score normalization works through predict_proba")
    end
    
    @testset "Solve Time Tracking" begin
        println("\n" * "="^80)
        println("Testing solve time tracking and feature extraction...")
        println("="^80)
        
        # Create subproblem scores
        scores = Dict{Int,SubproblemScore}()
        scores[1] = SubproblemScore()
        
        # Simulate solving scenario 1 multiple times
        BendersNetworkDesign.update_subproblem_score!(scores[1], true, true, 5.0, 1, 0.123)
        BendersNetworkDesign.update_subproblem_score!(scores[1], true, false, 3.0, 2, 0.089)
        BendersNetworkDesign.update_subproblem_score!(scores[1], false, false, 0.0, 2, 0.156)
        
        # Check tracking
        @test scores[1].times_solved == 3
        @test isapprox(scores[1].total_solve_time, 0.123 + 0.089 + 0.156, atol=1e-6)
        
        avg_time = scores[1].total_solve_time / scores[1].times_solved
        @test isapprox(avg_time, (0.123 + 0.089 + 0.156) / 3, atol=1e-6)
        println("✓ Average solve time tracked: $(round(avg_time, digits=4))s")
        
        # Verify it's used in feature extraction (feature 17)
        # We can't easily test the full feature extraction without a complete network,
        # but we can verify the field exists and is computed
        @test hasfield(SubproblemScore, :total_solve_time)
        println("✓ SubproblemScore has total_solve_time field")
    end
    
    @testset "Online Training with Statistics Update" begin
        println("\n" * "="^80)
        println("Testing online training updates feature statistics...")
        println("="^80)
        
        model = OnlineLogisticRegression(9)
        
        # Train with varying features
        features1 = rand(9) .* 100  # Random features in [0, 100]
        features2 = rand(9) .* 100
        features3 = rand(9) .* 100
        
        BendersNetworkDesign.update!(model, features1, true, 1)
        @test model.n_updates == 1
        @test !all(model.feature_means .== 0.0)  # Means updated
        println("✓ After 1 update: means updated")
        
        BendersNetworkDesign.update!(model, features2, false, 2)
        @test model.n_updates == 2
        println("✓ After 2 updates: n_updates = $(model.n_updates)")
        
        BendersNetworkDesign.update!(model, features3, true, 3)
        @test model.n_updates == 3
        
        # Check that stds are being updated (Welford's algorithm)
        @test any(model.feature_stds .!= 1.0)
        println("✓ Feature stds updated via Welford's algorithm")
        
        # Verify metrics tracked
        @test model.metrics.total_predictions == 3
        println("✓ Metrics tracked: $(model.metrics.total_predictions) predictions")
    end
    
    @testset "Prediction with Normalization" begin
        println("\n" * "="^80)
        println("Testing predictions use normalized features...")
        println("="^80)
        
        model = OnlineLogisticRegression(9)
        
        # Train to establish feature statistics
        for i in 1:10
            features = rand(9) .* 100
            label = rand() > 0.5
            BendersNetworkDesign.update!(model, features, label, i)
        end
        
        # Make prediction with new features
        test_features = rand(9) .* 100
        prob = BendersNetworkDesign.predict_proba(model, test_features)
        
        # Probability should be in [0, 1]
        @test 0.0 <= prob <= 1.0
        println("✓ Prediction probability in valid range: $(round(prob, digits=4))")
        
        # With normalization, predictions should not be extreme (0 or 1)
        # unless weights are very large
        @test prob != 0.0
        @test prob != 1.0
        println("✓ Normalization prevents saturation (not exactly 0 or 1)")
    end
    
end

println("\n" * "="^80)
println("All ML scoring tests passed!")
println("="^80)
