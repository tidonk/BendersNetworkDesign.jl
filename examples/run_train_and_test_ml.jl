#!/usr/bin/env julia
"""
Train and test ML-based subproblem scoring on pdh instance

Usage: julia examples/run_train_and_test_ml.jl

Step 1: Train ML model (solve all scenarios)
Step 2: Test with trained model (filtered solving)
"""

using Pkg
Pkg.activate(@__DIR__)

using BendersNetworkDesign

# Paths
NETWORK = joinpath(@__DIR__, "../data/sndlib/pdh.xml")
SETTINGS_TRAIN = joinpath(@__DIR__, "settings/test/benders_ML-train.toml")
SETTINGS_TEST = joinpath(@__DIR__, "settings/test/benders_ML-0.5-20S_readML.toml")

NETWORK_NAME = basename(NETWORK)
SETTINGS_TRAIN_NAME = replace(basename(SETTINGS_TRAIN), ".toml" => "")
SETTINGS_TEST_NAME = replace(basename(SETTINGS_TEST), ".toml" => "")

println("\n" * "="^70)
println("ML MODEL TRAINING AND TESTING")
println("="^70)

# Step 1: Train model
println("\n[1/2] Training ML model on $(NETWORK_NAME) instance...")
println("      Network: $(NETWORK_NAME)")
println("      Settings: $(SETTINGS_TRAIN_NAME) (solve all, export model)")
println()

main(NETWORK, SETTINGS_TRAIN)

# Step 2: Test with trained model
println("\n" * "="^70)
println("\n[2/2] Testing with trained ML model...")
println("      Network: $(NETWORK_NAME)")
println("      Settings: $(SETTINGS_TEST_NAME) (import model, ML filtering)")
println()

#main(NETWORK, SETTINGS_TEST)

println("\n" * "="^70)
println("COMPLETED")
println("="^70)
