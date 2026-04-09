# Network Instances

This page lists all available SNDlib network instances included in the `data/sndlib/` directory, along with their network statistics.

## Instance Overview

The table below shows the number of nodes, links, and demands for each network instance. All instances are from the [SNDlib library](http://sndlib.zib.de/).

| Instance | Nodes | Links | Demands | Size Category |
|----------|------:|------:|--------:|---------------|
| abilene | 12 | 15 | 132 | Small |
| atlanta | 15 | 22 | 210 | Small |
| brain | 161 | 332 | 14,311 | Very Large |
| cost266 | 37 | 57 | 1,332 | Medium |
| dfn-bwin | 10 | 45 | 90 | Small |
| dfn-gwin | 11 | 47 | 110 | Small |
| di-yuan | 11 | 42 | 22 | Small |
| france | 25 | 45 | 300 | Medium |
| geant | 22 | 36 | 462 | Small |
| germany50 | 50 | 88 | 662 | Large |
| giul39 | 39 | 172 | 1,471 | Medium |
| india35 | 35 | 80 | 595 | Medium |
| janos-us | 26 | 84 | 650 | Medium |
| janos-us-ca | 39 | 122 | 1,482 | Medium |
| newyork | 16 | 49 | 240 | Small |
| nobel-eu | 28 | 41 | 378 | Medium |
| nobel-germany | 17 | 26 | 121 | Small |
| nobel-us | 14 | 21 | 91 | Small |
| norway | 27 | 51 | 702 | Medium |
| pdh | 11 | 34 | 24 | Small |
| pioro40 | 40 | 89 | 780 | Medium |
| polska | 12 | 18 | 66 | Small |
| sun | 27 | 102 | 67 | Medium |
| ta1 | 24 | 55 | 396 | Medium |
| ta2 | 65 | 108 | 1,869 | Large |
| zib54 | 54 | 81 | 1,501 | Large |

## Size Categories

Instances are classified by node count:

- **Small**: < 20 nodes (12 instances)
- **Medium**: 20-50 nodes (11 instances)
- **Large**: 50-100 nodes (3 instances)
- **Very Large**: > 100 nodes (1 instance)

## Usage

To load a network instance in your code:

```julia
using BendersNetworkDesign

# Load a network
network = read_sndlib_network("data/sndlib/abilene.xml")

# Access network statistics
println("Nodes: ", length(network.network_structure.nodes))
println("Links: ", length(network.network_structure.links))
println("Demands: ", length(network.demands))
```

## Commonly Used Test Instances

The following instances are frequently used in testing and benchmarking:

- **abilene** (12 nodes): Small network, good for quick testing and debugging
- **atlanta** (15 nodes): Small network with more connectivity
- **france** (25 nodes): Medium-sized network, well-studied in the literature
- **germany50** (50 nodes): Larger network for performance testing
- **ta2** (65 nodes): Large network with many demands, challenging instance

## References

For more information about these network instances and their original sources, please refer to:

- [SNDlib - Survivable Network Design Library](http://sndlib.zib.de/)
- Orlowski, S., Wessäly, R., Pióro, M., Tomaszewski, A. (2010). SNDlib 1.0—Survivable Network Design Library. *Networks*, 55(3), 276-286.
## Generating Test Instances

You can generate larger test instances by combining multiple base networks using the instance generation framework:

### Quick Start

```julia
include("examples/run_instance_generation.jl")

# Generate 5 test instances
files = generate_quick_test_suite(base_seed=42)

# Generate 30 varied instances (2-5 networks, proportions 0.3-0.7)
files = generate_varied_suite(base_seed=800, num_instances=30)
```

### Proportion-Based Sizing

The generation framework uses proportion-based sizing to control instance size:

- **proportion = 1.0**: Use full networks (combine complete networks as-is)
- **proportion = 0.5**: Extract 50% of nodes from each network
- **proportion = 0.3**: Extract 30% of nodes from each network

**Example:**
```julia
# Combine 3 networks at 70% size each
files = BendersNetworkDesign.generate_instance_suite(
    num_instances=10,
    base_seed=100,
    num_networks_range=[3],
    proportion_range=[0.7],
    cost_scale_factors=[0.1],
    output_dir="../data/generated/my_suite"
)
```

### Generation Functions

Four convenience functions are available in `examples/run_instance_generation.jl`:

1. **`generate_quick_test_suite(base_seed=42)`**
   - 5 instances for quick testing
   - 3 networks combined
   - Proportions: 0.5 and 1.0

2. **`generate_large_suite(base_seed=42)`**
   - 50 diverse instances for comprehensive testing
   - 3-6 networks combined
   - Proportions: 0.2, 0.4, 0.6, 0.8, 1.0
   - Cost scales: 0.05, 0.1, 0.15, 0.2

3. **`generate_spanning_suite(base_seed=100, num_instances=50)`**
   - Spans from small to large proportions
   - Proportions evenly distributed from 0.1 to 1.0
   - 3-5 networks combined

4. **`generate_varied_suite(base_seed=800, num_instances=30)`**
   - Systematically varies network counts and proportions
   - 2-5 networks combined
   - 10 proportions from 0.3 to 0.7
   - Creates diverse instance sizes (7 to 150+ nodes)

### Custom Generation

For full control, use the core API function directly:

```julia
using BendersNetworkDesign

files = generate_instance_suite(
    num_instances=20,
    base_seed=42,
    num_networks_range=[3, 4, 5],      # Cycle through 3, 4, 5 networks
    proportion_range=[0.4, 0.6, 1.0],  # Cycle through proportions
    cost_scale_factors=[0.1],
    output_dir="../data/generated/custom",
    manifest_file="instance_manifest.md"
)
```

### Features

- **Automatic cost scaling**: Default 0.1 factor keeps objectives < 1e6
- **Markdown manifests**: Generated `instance_manifest.md` with formatted tables
- **Metadata tracking**: Each XML includes source networks, proportions, seeds
- **Reproducible**: Deterministic generation from seeds

### Output Structure

Generated instances are saved as SNDlib XML files with descriptive names:

```
instance_0001_n3_s42_seed101.xml
         ↑    ↑   ↑    ↑
         │    │   │    └─ Random seed used
         │    │   └────── Actual node count (size)
         │    └────────── Number of networks combined
         └─────────────── Instance ID
```

Each suite includes a markdown manifest:

```markdown
# Instance Generation Manifest

**Generated:** 2026-01-16T10:19:39.657  
**Base seed:** 1000  
**Total instances:** 30  

## Instances

| ID | Seed | Networks | Proportion | Scale | Nodes | Links | Demands | Filename |
|----|------|----------|------------|-------|-------|-------|---------|----------|
| 1  | 1001 | 2        | 0.3        | 0.1   | 15    | 51    | 137     | instance_0001_n2_s15_seed1001.xml |
| 2  | 1002 | 3        | 0.344      | 0.1   | 74    | 145   | 1901    | instance_0002_n3_s74_seed1002.xml |
...
```