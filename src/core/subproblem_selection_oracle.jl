"""
Oracle recording and replay for subproblem selection.

Provides "perfect information" strategies by recording which subproblems yield cuts
in a full solve, then replaying that information in subsequent runs.
"""

"""
    OracleError <: Exception

Custom exception for oracle validation failures.

Thrown when oracle replay encounters a scenario that was indicated to yield a cut
but does not produce a cut in the read phase, indicating non-determinism in the
Benders process.
"""
struct OracleError <: Exception
    msg::String
end

Base.showerror(io::IO, e::OracleError) = print(io, "OracleError: ", e.msg)

"""
    OracleData

Stores oracle information: which subproblems yielded cuts in each iteration.

# Fields
- `iterations::Dict{Int,Vector{Vector{Int}}}`: Maps iteration number to list of failed_link_indices that yielded cuts
"""
struct OracleData
    iterations::Dict{Int,Vector{Vector{Int}}}
end

OracleData() = OracleData(Dict{Int,Vector{Vector{Int}}}())

"""
    record_cut_scenario!(oracle::OracleData, iteration::Int, failed_link_indices::Vector{Int})

Record that a scenario with given failed link indices yielded a cut in a given iteration.
"""
function record_cut_scenario!(oracle::OracleData, iteration::Int, failed_link_indices::Vector{Int})::Nothing
    if !haskey(oracle.iterations, iteration)
        oracle.iterations[iteration] = Vector{Int}[]
    end
    push!(oracle.iterations[iteration], failed_link_indices)
    return nothing
end

"""
    record_no_cuts!(oracle::OracleData, iteration::Int)

Record that an iteration occurred but yielded no cuts.
This is represented by an empty vector in the scenario list.
"""
function record_no_cuts!(oracle::OracleData, iteration::Int)::Nothing
    if !haskey(oracle.iterations, iteration)
        oracle.iterations[iteration] = Vector{Int}[]
    end
    return nothing
end

"""
    write_oracle_data(oracle::OracleData, filepath::String)

Write oracle data to CSV file.

Format: iteration,failed_link_indices (semicolon-separated list of link indices)
Example: 1,3;5 means iteration 1 with links 3 and 5 failed
"""
function write_oracle_data(oracle::OracleData, filepath::String)::Nothing
    # Create output directory if needed
    dir = dirname(filepath)
    if !isdir(dir) && !isempty(dir)
        mkpath(dir)
    end
    
    # Collect all records
    records = Tuple{Int,Vector{Int}}[]
    for (iter, failed_links_list) in sort(collect(oracle.iterations))
        for failed_links in failed_links_list
            push!(records, (iter, failed_links))
        end
    end
    
    # Write to CSV
    # Iterations with cuts: write scenario failed_link_indices
    # Iterations with no cuts: write "*" to indicate "solve all scenarios"
    open(filepath, "w") do io
        println(io, "iteration,failed_link_indices")
        for (iter, failed_links) in records
            # Convert vector to string representation
            links_str = join(failed_links, ";")
            println(io, "$iter,$links_str")
        end
        
        # Write iterations with no cuts - must solve all scenarios to verify solution
        for (iter, failed_links_list) in sort(collect(oracle.iterations))
            if isempty(failed_links_list)
                println(io, "$iter,*")  # "*" means solve all scenarios
            end
        end
    end
    
    println("Oracle data written to: $filepath")
    println("  Total iterations: $(length(oracle.iterations))")
    println("  Total cut scenarios: $(length(records))")
    
    return nothing
end

"""
    read_oracle_data(filepath::String) -> OracleData

Read oracle data from CSV file.
"""
function read_oracle_data(filepath::String)::OracleData
    if !isfile(filepath)
        error("Oracle file not found: $filepath")
    end
    
    oracle = OracleData()
    
    # Read CSV line by line (can't use readdlm with mixed types)
    open(filepath, "r") do io
        # Skip header
        readline(io)
        
        for line in eachline(io)
            parts = split(line, ',')
            if length(parts) >= 2
                iter = parse(Int, parts[1])
                links_str = parts[2]
                
                # Check for special "*" marker meaning "solve all scenarios"
                if links_str == "*"
                    # Mark this iteration as needing all scenarios (represented by empty list internally)
                    record_no_cuts!(oracle, iter)
                else
                    # Parse failed link indices (semicolon-separated)
                    failed_links = if isempty(links_str)
                        Int[]  # Base case (no failures)
                    else
                        [parse(Int, x) for x in split(links_str, ';')]
                    end
                    record_cut_scenario!(oracle, iter, failed_links)
                end
            end
        end
    end
    
    println("Oracle data loaded from: $filepath")
    println("  Total iterations: $(length(oracle.iterations))")
    println("  Total cut scenarios: $(sum(length(v) for v in values(oracle.iterations)))")
    
    return oracle
end

"""
    OracleSelection <: SelectionStrategy

Oracle-based selection: solve only scenarios known to yield cuts.

Uses pre-recorded information about which scenarios yielded cuts
in each iteration. Provides "perfect information" baseline.

# Fields
- `oracle::OracleData`: Recorded cut information
- `current_iteration::Ref{Int}`: Tracks current iteration number
"""
mutable struct OracleSelection <: SelectionStrategy
    oracle::OracleData
    current_iteration::Ref{Int}
    expect_no_cuts::Ref{Bool}  # True if current iteration is a "*" (solve all, expect no cuts)
    
    OracleSelection(oracle::OracleData) = new(oracle, Ref(0), Ref(false))
end

"""
    get_oracle_scenarios(strategy::OracleSelection, iteration::Int) -> Vector{Vector{Int}}

Get list of failed link indices to solve for given iteration based on oracle.

Returns empty vector if no oracle data exists for this iteration.
"""
function get_oracle_scenarios(strategy::OracleSelection, iteration::Int)::Vector{Vector{Int}}
    strategy.current_iteration[] = iteration
    scenarios = get(strategy.oracle.iterations, iteration, Vector{Int}[])
    # If empty, this is a "*" iteration - we expect no cuts
    strategy.expect_no_cuts[] = isempty(scenarios)
    return scenarios
end

"""
    should_stop_solving(strategy::OracleSelection, iter_data, current_score, root_node_stabilization) -> Bool

Oracle strategy: stop after solving all oracle-indicated scenarios.

This is checked against a list of scenarios to solve, so this function
always returns false (the scenario list is pre-filtered by oracle).
"""
function should_stop_solving(strategy::OracleSelection, iter_data::IterationData, 
                            current_score::Float64=1.0, root_node_stabilization::Int=0)::Bool
    return false  # Oracle pre-filters scenarios, so never stop early
end

"""
    update_cut_limit!(strategy::OracleSelection, iter_data, prev_iter_data) -> Int

Oracle strategy: no limit updates needed (decisions based on oracle data).
"""
function update_cut_limit!(strategy::OracleSelection, iter_data::IterationData, 
                          prev_iter_data::Union{IterationData,Nothing}, verbose::Bool=false)::Int
    return -1  # No limit applies
end

"""
    order_scenarios_with_oracle(scenarios, scores, ordering, oracle_strategy, iteration, random_seed) -> Vector

Order scenarios for solving, optionally filtering by oracle.

When oracle_strategy is provided, filters scenarios to only those indicated by oracle.
"""
function order_scenarios_with_oracle(scenarios::Vector, scores::Dict{Int,SubproblemScore}, 
                                    ordering::String, oracle_strategy::Union{OracleSelection,Nothing},
                                    iteration::Int, random_seed::Union{Int,Nothing}=nothing)
    # Filter by oracle if using oracle strategy
    if oracle_strategy !== nothing
        oracle_ids = get_oracle_scenarios(oracle_strategy, iteration)
        scenarios = filter(s -> s.id in oracle_ids, scenarios)
    end
    
    # Apply regular ordering to filtered scenarios
    return order_scenarios(scenarios, scores, ordering, random_seed)
end