"""
Unit tests for SNDlib network reader
"""

include("common.jl")

@testset "SNDlib Reader Tests" begin
    
    @testset "Data structures" begin
        # Test Node structure
        node = Node("A", 10.5, 20.3)
        @test node.id == "A"
        @test node.x == 10.5
        @test node.y == 20.3
        
        # Test Link structure
        link = Link("AB", "A", "B", 1.5, 100.0, 1000.0, 0.0, [])
        @test link.id == "AB"
        @test link.source == "A"
        @test link.target == "B"
        @test link.routing_cost == 1.5
        @test link.setup_cost == 100.0
        @test link.preinstalled_capacity == 1000.0
        
        # Test Demand structure
        demand = Demand("A_B", "A", "B", nothing, 50.0, nothing, [])
        @test demand.id == "A_B"
        @test demand.source == "A"
        @test demand.target == "B"
        @test demand.demand_value == 50.0
        
        println("✓ Data structures validated")
    end
    
    @testset "NetworkStructure validation" begin
        nodes = Dict(
            "A" => Node("A", 0.0, 0.0),
            "B" => Node("B", 1.0, 1.0)
        )
        
        links = Dict(
            "AB" => Link("AB", "A", "B", 1.0, 10.0, 100.0, 0.0, [])
        )
        
        network_structure = NetworkStructure(nodes, links)
        
        @test length(network_structure.nodes) == 2
        @test length(network_structure.links) == 1
        @test haskey(network_structure.nodes, "A")
        @test haskey(network_structure.nodes, "B")
        @test haskey(network_structure.links, "AB")
        
        println("✓ NetworkStructure created correctly")
    end
    
    @testset "SNDlibNetwork validation" begin
        nodes = Dict("A" => Node("A", 0.0, 0.0))
        links = Dict("AB" => Link("AB", "A", "B", 1.0, 10.0, 100.0, 0.0, []))
        demands = Dict("A_B" => Demand("A_B", "A", "B", nothing, 50.0, nothing, []))
        
        network = SNDlibNetwork(
            nothing,
            NetworkStructure(nodes, links),
            demands
        )
        
        @test network.network_structure.nodes === nodes
        @test network.network_structure.links === links
        @test network.demands === demands
        
        println("✓ SNDlibNetwork created correctly")
    end
    
    @testset "Demand matrix handling" begin
        # Test demand matrix format
        scenario1 = Dict("A_B" => 10.0, "C_D" => 20.0)
        scenario2 = Dict("A_B" => 15.0, "C_D" => 25.0)
        
        scenarios = [scenario1, scenario2]
        
        @test length(scenarios) == 2
        @test haskey(scenarios[1], "A_B")
        @test scenarios[1]["A_B"] == 10.0
        @test scenarios[2]["A_B"] == 15.0
        
        # Test demand value access
        for (i, scenario) in enumerate(scenarios)
            @test scenario isa Dict{String, Float64}
            @test all(v > 0 for v in values(scenario))
        end
        
        println("✓ Demand matrix handling correct")
    end
    
    @testset "Network consistency checks" begin
        # Test that link endpoints reference existing nodes
        nodes = Dict(
            "A" => Node("A", 0.0, 0.0),
            "B" => Node("B", 1.0, 1.0)
        )
        
        links = Dict(
            "AB" => Link("AB", "A", "B", 1.0, 10.0, 100.0, 0.0, [])
        )
        
        network_structure = NetworkStructure(nodes, links)
        
        for (link_id, link) in network_structure.links
            @test haskey(network_structure.nodes, link.source)
            @test haskey(network_structure.nodes, link.target)
        end
        
        println("✓ Network consistency validated")
    end
    
    @testset "Cost and capacity handling" begin
        # Test handling of nothing values
        link1 = Link("L1", "A", "B", nothing, nothing, nothing, 0.0, [])
        @test isnothing(link1.routing_cost)
        @test isnothing(link1.setup_cost)
        @test isnothing(link1.preinstalled_capacity)
        
        # Test default value handling in model
        cost = something(link1.routing_cost, 0.0)
        @test cost == 0.0
        
        setup = something(link1.setup_cost, 0.0)
        @test setup == 0.0
        
        capacity = something(link1.preinstalled_capacity, 1e6)
        @test capacity == 1e6
        
        println("✓ Cost and capacity defaults work")
    end
end
