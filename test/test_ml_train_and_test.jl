"""
Test ML model training and inference workflow.

Tests the complete workflow of:
1. Training an ML model on abilene network
2. Using the trained model for inference 
3. Verifying both runs produce valid solutions

Uses settings files from settings/test/ directory.
"""

include("common.jl")

using JuMP  # For MOI.OPTIMAL
using Printf

@testset "ML Training and Testing Workflow" begin
    println("\n" * "="^80)
    println("Testing ML Model Training and Inference on Abilene")
    println("="^80)
    
    network_file = joinpath(DATA_DIR, "sndlib", "abilene.xml")
    # Model files are saved to check/models/ directory by default
    models_dir = joinpath(dirname(dirname(@__FILE__)), "check", "models")
    model_file = joinpath(models_dir, "trained_model_abilene.jls")
    train_settings_file = joinpath(SETTINGS_DIR, "test", "ml_train.toml")
    test_settings_file = joinpath(SETTINGS_DIR, "test", "ml_inference.toml")
    
    # Clean up any existing model file
    isfile(model_file) && rm(model_file)
    
    @testset "Train ML Model" begin
        println("\n--- Phase 1: Training ML model ---")
        
        # Load network and settings
        network = read_sndlib_network(network_file)
        settings = read_settings(train_settings_file)
        
        # Generate outage scenarios (limit to 15 for faster testing)
        all_scenarios = generate_outage_scenarios(network; include_base_case=false)
        outage_scenarios = all_scenarios[1:min(15, length(all_scenarios))]
        
        # Solve with training settings
        result = solve_benders(network; 
            optimizer = settings.optimizer,
            outage_scenarios = outage_scenarios,
            settings = settings
        )
        
        @test result.status == MOI.OPTIMAL
        @test result.objective_value > 0
        @test result.iterations > 0
        @test isfile(model_file)  # Check model was exported
        
        println("  ✓ Training completed: $(result.iterations) iterations, objective=$(round(result.objective_value, digits=2))")
    end
    
    @testset "Test with Trained Model" begin
        println("\n--- Phase 2: Testing with trained model ---")
        
        # Load network and settings
        network = read_sndlib_network(network_file)
        settings = read_settings(test_settings_file)
        
        # Settings file already has read flag configured
        # Verify model file exists in check/models/
        instance_name = splitext(basename(network_file))[1]
        models_dir = joinpath(@__DIR__, "..", "check", "models")
        model_path = joinpath(models_dir, "trained_model_$(instance_name).jls")
        @test isfile(model_path)
        
        # Generate outage scenarios (limit to 15 for faster testing)
        all_scenarios = generate_outage_scenarios(network; include_base_case=false)
        outage_scenarios = all_scenarios[1:min(15, length(all_scenarios))]
        
        # Solve with trained model
        result = solve_benders(network;
            optimizer = settings.optimizer,
            outage_scenarios = outage_scenarios,
            settings = settings
        )
        
        @test result.status == MOI.OPTIMAL
        @test result.objective_value > 0
        @test result.iterations > 0
        
        println("  ✓ Testing completed: $(result.iterations) iterations, objective=$(round(result.objective_value, digits=2))")
    end
    
    # Clean up model file
    isfile(model_file) && rm(model_file)
    
    println("\n" * "="^80)
    println("ML Training and Testing Workflow - PASSED")
    println("="^80)
end
