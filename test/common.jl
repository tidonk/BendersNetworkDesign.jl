"""
Common test utilities and setup for BendersNetworkDesign test suite.

This file provides shared functionality for all tests, including:
- Module loading with REPL-friendly isdefined guards
- Directory path constants
- Gurobi environment initialization (when needed)

Usage in test files:
    include("common.jl")
"""

using Test

# Only load module if not already loaded (makes tests REPL-friendly)
if !isdefined(Main, :BendersNetworkDesign)
    include("../src/BendersNetworkDesign.jl")
    using .BendersNetworkDesign
else
    using .BendersNetworkDesign
end

# Set up directory constants if not already defined
if !isdefined(Main, :TEST_DIR)
    const TEST_DIR = @__DIR__
end

if !isdefined(Main, :DATA_DIR)
    const DATA_DIR = abspath(joinpath(@__DIR__, "..", "data"))
end

if !isdefined(Main, :SETTINGS_DIR)
    const SETTINGS_DIR = abspath(joinpath(@__DIR__, "..", "settings"))
end

# Initialize Gurobi environment if needed (only if not already initialized)
# This is only defined when Gurobi tests are run
# Note: Gurobi must be loaded by the calling test file before calling this function
function init_gurobi_env()
    if !isdefined(Main, :GRB_ENV)
        # Gurobi must already be loaded via "using Gurobi" in the test file
        grb_env_ref = Ref{Gurobi.Env}()
        grb_env_ref[] = Gurobi.Env()
        # Use global assignment without const (since const can't be used in conditionals)
        Core.eval(Main, :(global GRB_ENV = $grb_env_ref))
        return grb_env_ref
    else
        return Main.GRB_ENV
    end
end
