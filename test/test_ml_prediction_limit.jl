"""
Test that ML prediction-based selection respects the predicted number of scenarios to solve.
"""

include("common.jl")

using Test

@testset "ML Prediction Limit" begin
    # Load network and settings
    network_file = joinpath(DATA_DIR, "sndlib", "abilene.xml")
    settings_file = joinpath(@__DIR__, "../settings/experiment5/benders_ML-PA-20S-5R.toml")
    
    network = read_sndlib_network(network_file)
    settings = read_settings(settings_file)
    
    @testset "Settings loaded correctly" begin
        @test settings.selection_strategy == "adaptive"
        @test settings.adaptive_mode == "prediction_based"
        @test settings.min_score_threshold == -1.0  # Disabled
        @test settings.iteration_time_limit == -1.0  # Disabled
    end
    
    @testset "Selection strategy checks num_solves for prediction_based" begin
        # Create test scenario
        scenarios = generate_outage_scenarios(network; include_base_case=false, k=1)[1:10]
        
        # Create selection strategy
        selection_strategy = create_selection_strategy(settings, length(scenarios))
        
        @test selection_strategy isa AdaptiveCutLimit
        @test selection_strategy.mode == "prediction_based"
        @test selection_strategy.min_score_threshold == -1.0
        
        # Create iter_data
        iter_data = IterationData()
        iter_data.iteration = 5
        iter_data.is_root_node = false
        iter_data.is_initialization_round = false
        iter_data.is_stabilization_round = false
        
        # Set current_cuts to 7 (simulating ML prediction to solve 7 scenarios)
        selection_strategy.current_cuts = 7
        
        # Test: After solving 5 scenarios with 3 cuts, should NOT stop (5 < 7)
        iter_data.num_solves_this_iter = 5
        iter_data.cuts_found_this_iter = 3
        @test should_stop_solving(selection_strategy, iter_data, 0.8, 0) == false
        
        # Test: After solving 7 scenarios with 3 cuts, SHOULD stop (7 >= 7)
        iter_data.num_solves_this_iter = 7
        iter_data.cuts_found_this_iter = 3
        @test should_stop_solving(selection_strategy, iter_data, 0.8, 0) == true
        
        # Test: After solving 8 scenarios with 3 cuts, SHOULD stop (8 > 7)
        iter_data.num_solves_this_iter = 8
        iter_data.cuts_found_this_iter = 3
        @test should_stop_solving(selection_strategy, iter_data, 0.8, 0) == true
        
        # Test: Even if we found 10 cuts but only solved 5 scenarios, should NOT stop
        iter_data.num_solves_this_iter = 5
        iter_data.cuts_found_this_iter = 10
        @test should_stop_solving(selection_strategy, iter_data, 0.8, 0) == false
        
        println("✓ ML prediction-based selection correctly checks num_solves (not cuts_found)")
    end
    
    @testset "Low score threshold disabled" begin
        scenarios = generate_outage_scenarios(network; include_base_case=false, k=1)[1:10]
        selection_strategy = create_selection_strategy(settings, length(scenarios))
        
        iter_data = IterationData()
        iter_data.iteration = 5
        iter_data.is_root_node = false
        iter_data.is_initialization_round = false
        iter_data.is_stabilization_round = false
        iter_data.num_solves_this_iter = 3
        iter_data.cuts_found_this_iter = 2
        selection_strategy.current_cuts = 10
        
        # Test: Even with very low score (0.1), should NOT stop if min_score_threshold = -1.0
        @test should_stop_solving(selection_strategy, iter_data, 0.1, 0) == false
        @test should_stop_solving(selection_strategy, iter_data, 0.6, 0) == false
        @test should_stop_solving(selection_strategy, iter_data, 0.9, 0) == false
        
        println("✓ Low score threshold disabled correctly")
    end
end

println("\n✅ All ML prediction limit tests passed!")
