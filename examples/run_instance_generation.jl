"""
Instance generation script for BendersNetworkDesign.

Provides high-level functions to generate test instance suites:
- generate_quick_test_suite: Small suite for quick testing
- generate_large_suite: Large diverse suite for comprehensive testing  
- generate_spanning_suite: Instances spanning from small to large proportions
- generate_varied_suite: Varied networks (2-5) with proportions 0.3-0.7

All core generation logic is in src/network/instance.jl.
"""

# Load the main package
include("src/BendersNetworkDesign.jl")
using .BendersNetworkDesign
using Random
using Dates

"""
    generate_quick_test_suite(; base_seed::Int=42)

Generate a small test suite (5 instances) for quick testing.
"""
function generate_quick_test_suite(; base_seed::Int=42)::Vector{String}
    return BendersNetworkDesign.generate_instance_suite(
        num_instances=5,
        base_seed=base_seed,
        num_networks_range=[3],
        proportion_range=[0.5, 1.0],
        cost_scale_factors=[0.1],
        output_dir="../data/generated/test_suite"
    )
end

"""
    generate_large_suite(; base_seed::Int=42)

Generate a large diverse suite (50 instances) for comprehensive testing.
"""
function generate_large_suite(; base_seed::Int=42)::Vector{String}
    return BendersNetworkDesign.generate_instance_suite(
        num_instances=50,
        base_seed=base_seed,
        num_networks_range=[3, 4, 5, 6],
        proportion_range=[0.2, 0.4, 0.6, 0.8, 1.0],
        cost_scale_factors=[0.05, 0.1, 0.15, 0.2],
        output_dir="../data/generated/large_suite"
    )
end

"""
    generate_spanning_suite(; base_seed::Int=42, num_instances::Int=50)

Generate instances spanning from small proportions (0.1) to full networks (1.0).

Instances use proportions evenly distributed from 0.1 to 1.0, combining 3-5 base networks.
This creates a natural range from small subgraphs to complete combined networks.
"""
function generate_spanning_suite(; base_seed::Int=42, num_instances::Int=50)::Vector{String}
    # Generate evenly spaced proportions from 0.1 to 1.0
    proportions = collect(range(0.1, 1.0, length=num_instances))
    
    println("Generating spanning suite: proportions 0.1 to 1.0")
    
    return BendersNetworkDesign.generate_instance_suite(
        num_instances=num_instances,
        base_seed=base_seed,
        num_networks_range=[3, 4, 5],
        proportion_range=proportions,
        cost_scale_factors=[0.1],
        output_dir="../data/generated/spanning_suite"
    )
end

"""
    generate_varied_suite(; base_seed::Int=800, num_instances::Int=30)

Generate diverse instances with varying numbers of base networks (2-5) and proportions (0.45-0.65).

This suite systematically explores different instance sizes and complexities by cycling through:
- 2, 3, 4, or 5 base networks combined
- 10 evenly-spaced proportions from 0.45 to 0.65
- Cost scale of 0.1

The proportions are tuned to target 40-90 scenarios per instance, which empirically yields
runtimes in the 30-150 minute range. This avoids both trivially fast instances (<30min)
and instances that hit the time limit (>180min).

Instance characteristics:
- 2 networks @ 0.45-0.65: ~15-40 scenarios, 5-30min runtime
- 3 networks @ 0.45-0.65: ~30-60 scenarios, 10-90min runtime  
- 4 networks @ 0.45-0.65: ~50-90 scenarios, 30-150min runtime
- 5 networks @ 0.45-0.65: ~70-120 scenarios, 60-180min runtime
"""
function generate_varied_suite(; base_seed::Int=800, num_instances::Int=30)::Vector{String}
    # Generate evenly spaced proportions from 0.45 to 0.65 (narrower range for better runtime distribution)
    proportions = collect(range(0.45, 0.65, length=10))
    
    println("Generating varied suite: 2-5 networks, proportions 0.45 to 0.65")
    println("Target: 30-150 minute runtime instances (40-90 scenarios)")
    
    return BendersNetworkDesign.generate_instance_suite(
        num_instances=num_instances,
        base_seed=base_seed,
        num_networks_range=[2, 3, 4, 5],
        proportion_range=proportions,
        cost_scale_factors=[0.1],
        output_dir="../data/generated/experiment5"
    )
end

# If run as a script, generate the default suite
if abspath(PROGRAM_FILE) == @__FILE__
    println("Running instance generation...")
    generated_files = generate_instance_suite()
    println("\nGenerated $(length(generated_files)) instances successfully!")
end
