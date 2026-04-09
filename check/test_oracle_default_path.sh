#!/bin/bash
# Quick oracle test script
# Tests oracle functionality with abilene instance using default filepath

cd "$(dirname "$0")" || exit 1

echo "=== Oracle Default Filepath Test ==="
echo "Testing oracle write mode with default filepath..."
echo ""

# Run oracle write
julia --project=. -e '
using BendersNetworkDesign
using Gurobi

# Load instance
network = read_sndlib_network("../data/sndlib/abilene.xml")
scenarios = generate_outage_scenarios(network; include_base_case=false)
settings = read_settings("settings/experiment5/oracle_write.toml")

println("Instance: abilene.xml ($(length(network.nodes)) nodes, $(length(scenarios)) scenarios)")
println("Expected oracle path: check/oracle/abilene.csv")
println("")

# Solve
env = Gurobi.Env()
result = solve_benders(network; 
    optimizer=() -> Gurobi.Optimizer(env), 
    outage_scenarios=scenarios, 
    settings=settings
)

println("")
println("✓ Oracle write completed")
println("Objective: $(result.objective)")
'

# Check if oracle file was created
if [ -f "check/oracle/abilene.csv" ]; then
    echo ""
    echo "✅ SUCCESS: Oracle file created at check/oracle/abilene.csv"
    echo ""
    echo "First 10 lines:"
    head -10 check/oracle/abilene.csv
else
    echo ""
    echo "❌ FAILED: Oracle file not found at check/oracle/abilene.csv"
    exit 1
fi
