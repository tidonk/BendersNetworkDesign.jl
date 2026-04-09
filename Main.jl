"""
BendersNetworkDesign - Main Entry Point

Solves a single SNDlib instance using Benders decomposition.
"""

# Use Revise for automatic code reloading during development
using Revise
using Pkg

using BendersNetworkDesign
#Pkg.develop(path=@__DIR__)

main(joinpath(@__DIR__, "data/sndlib/abilene.xml"), joinpath(@__DIR__, "settings/benders_standard.toml"))