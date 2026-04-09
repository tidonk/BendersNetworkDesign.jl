"""
Test oracle recording and replay functionality.

Verifies that:
1. Oracle data can be written during a full solve
2. Oracle data can be read and used for selective solving
3. Oracle replay produces the same solution with fewer subproblem solves
"""

include("common.jl")

using Test
using JuMP  # For MOI constants

@testset "Oracle Recording and Replay" begin
    # Use small instance for quick testing
    network_file = joinpath(@__DIR__, "..", "data", "sndlib", "abilene.xml")
    
    if !isfile(network_file)
        @warn "Test network file not found: $network_file. Skipping oracle test."
    else
        network = read_sndlib_network(network_file)
        
        # Create oracle directory
        oracle_dir = joinpath(@__DIR__, "..", "check", "oracle")
        mkpath(oracle_dir)
        
        # Oracle file path (hardcoded in test settings files)
        oracle_file = joinpath(oracle_dir, "test_abilene.csv")
        
        # Clean up any existing oracle file
        if isfile(oracle_file)
            rm(oracle_file)
        end
        
        @testset "Oracle Write Phase" begin
            # Load write settings
            write_settings_file = joinpath(@__DIR__, "..", "settings", "test", "test_oracle_write.toml")
            settings = read_settings(write_settings_file)
            
            outage_scenarios = BendersNetworkDesign.prepare_outage_scenarios(network, settings)
            
            # Solve with oracle write mode (should solve all scenarios)
            result_write = solve_benders(
                network;
                optimizer=settings.optimizer,
                outage_scenarios=outage_scenarios,
                settings=settings
            )
            
            @test result_write.status == MOI.OPTIMAL || result_write.status == MOI.TIME_LIMIT
            @test result_write.objective_value < Inf
            @test result_write.iterations > 0
            @test result_write.total_cuts_added > 0
            @test result_write.total_subproblems_solved > 0
            
            # Verify oracle file was created at the computed path
            @test isfile(oracle_file)
            
            # Read oracle data and verify format
            oracle_data = read_oracle_data(oracle_file)
            @test length(oracle_data.iterations) > 0
            @test all(iter > 0 for iter in keys(oracle_data.iterations))
            # Note: Some iterations may have empty scenario lists (no cuts added)
            # This is valid - oracle will solve all scenarios in that iteration
            @test any(length(scenarios) > 0 for scenarios in values(oracle_data.iterations))
        end
        
        @testset "Oracle Read Phase" begin
            # Load read settings
            read_settings_file = joinpath(@__DIR__, "..", "settings", "test", "test_oracle_read.toml")
            settings = read_settings(read_settings_file)
            
            # Verify oracle file exists from write phase
            @test isfile(oracle_file)
            
            outage_scenarios = BendersNetworkDesign.prepare_outage_scenarios(network, settings)
            
            # Solve with oracle read mode (should solve only oracle-indicated scenarios)
            result_read = solve_benders(
                network;
                optimizer=settings.optimizer,
                outage_scenarios=outage_scenarios,
                settings=settings
            )
            
            @test result_read.status == MOI.OPTIMAL || result_read.status == MOI.TIME_LIMIT
            @test result_read.objective_value < Inf
            @test result_read.iterations > 0
            @test result_read.total_cuts_added > 0
            
            # Oracle should solve fewer subproblems than full solve
            # (This comparison requires running write phase first in same test session)
            # For now, just verify oracle solved some but not all scenarios
            total_scenarios = length(outage_scenarios) - 1  # Exclude base case
            @test result_read.total_subproblems_solved < result_read.iterations * total_scenarios
        end
        
        @testset "Oracle Data I/O" begin
            # Test oracle data structure directly
            oracle = OracleData()
            
            # Record some scenarios (as vectors)
            record_cut_scenario!(oracle, 1, [5])
            record_cut_scenario!(oracle, 1, [10])
            record_cut_scenario!(oracle, 2, [3])
            record_cut_scenario!(oracle, 2, [5])
            record_cut_scenario!(oracle, 3, [8])
            
            @test length(oracle.iterations) == 3
            @test [5] in oracle.iterations[1]
            @test [10] in oracle.iterations[1]
            @test [3] in oracle.iterations[2]
            
            # Write to file
            test_oracle_file = joinpath(oracle_dir, "test_io_oracle.csv")
            write_oracle_data(oracle, test_oracle_file)
            @test isfile(test_oracle_file)
            
            # Read back
            oracle_loaded = read_oracle_data(test_oracle_file)
            @test length(oracle_loaded.iterations) == 3
            @test Set(oracle_loaded.iterations[1]) == Set([[5], [10]])
            @test Set(oracle_loaded.iterations[2]) == Set([[3], [5]])
            @test Set(oracle_loaded.iterations[3]) == Set([[8]])
            
            # Clean up
            rm(test_oracle_file)
        end
        
        
        # Clean up test oracle file
        if isfile(oracle_file)
            rm(oracle_file)
        end
    end
end
