using Documenter
using BendersNetworkDesign

makedocs(
    sitename = "BendersNetworkDesign.jl",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"
    ),
    modules = [BendersNetworkDesign],
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "Problem Formulation" => "formulation.md",
        "Configuration" => "configuration.md",
        "Network Instances" => "instances.md",
        "API Reference" => [
            "Models" => "api/models.md",
            "Subproblem Selection" => "api/selection.md",
            "I/O Functions" => "api/io.md",
        ],
    ],
    repo = "https://git.or.rwth-aachen.de/benders-subproblem-selection/BendersNetworkDesign.jl",
    checkdocs = :none   # Don't error on missing docstrings
)
