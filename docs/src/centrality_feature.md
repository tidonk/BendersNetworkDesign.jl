# Link Betweenness Centrality Feature for ML-Based Scenario Prioritization

## Overview

Added **link betweenness centrality** as the 5th feature in the ML model for predicting which network failure scenarios will generate Benders cuts. This topological feature captures the structural importance of links in the network, complementing the existing capacity and flow-based features.

## Feature Definition

**Betweenness centrality** for a link measures the fraction of all-pairs shortest paths that traverse that link. It quantifies how critical a link is for network connectivity and routing.

### Computation Algorithm

For a network with node set $N$ and link set $L$:

1. **For each node pair** $(s,t) \in N \times N, s \neq t$:
   - Compute shortest paths from $s$ to $t$ using breadth-first search (BFS)
   - Track all links on any shortest path

2. **Count path usage**: For each link $\ell \in L$, count the number of node pairs whose shortest paths use $\ell$

3. **Normalize**: Divide by total number of node pairs $|N|(|N|-1)$

### Mathematical Formulation

$$
\text{BC}(\ell) = \frac{1}{|N|(|N|-1)} \sum_{s,t \in N, s \neq t} \sigma_{st}(\ell)
$$

where:
- $\sigma_{st}(\ell) = 1$ if link $\ell$ is on at least one shortest path from $s$ to $t$
- $\sigma_{st}(\ell) = 0$ otherwise

### Properties

- **Range**: $[0, 1]$ (normalized by number of node pairs)
- **Bridge links**: High centrality (appear on many shortest paths)
- **Redundant links**: Low centrality (rarely needed for shortest paths)
- **Critical for connectivity**: Links with high centrality are more likely to cause routing failures when they fail

## Integration with ML Model

### Feature Vector (10 features total)

| Index | Feature | Description | For k-Contingencies |
|-------|---------|-------------|---------------------|
| 1 | Capacity | Installed capacity on failed link(s) | Averaged |
| 2 | Flow (Forward) | Base case flow in forward direction | Averaged |
| 3 | Flow (Backward) | Base case flow in backward direction | Averaged |
| 4 | Utilization | Flow / Capacity ratio | Averaged |
| **5** | **Centrality** | **Betweenness centrality** | **Averaged** |
| 6 | Violation | Historical average violation magnitude | From scores |
| 7 | Reliability | Historical cut generation rate | From scores |
| 8 | Reliability (Filtered) | Historical cut success rate (post-filtering) | From scores |
| 9 | Total Share | Share of all cuts produced | From scores |
| 10 | Stabilization | Staleness penalty (rounds since solved) | From scores |

### For k-Contingencies (Multiple Simultaneous Failures)

When $k > 1$ links fail simultaneously:
- Centrality values are **averaged** across all failed links
- Captures the combined topological importance of the failure set
- Example: If links $\ell_1, \ell_2$ fail, feature 5 = $\frac{\text{BC}(\ell_1) + \text{BC}(\ell_2)}{2}$

## Implementation Details

### Code Location
- **Function**: `compute_link_betweenness_centrality(nodes, links)` 
- **File**: `src/core/subproblem_scoring_ml.jl`
- **Integration**: `src/models/benders.jl` (computed once at start, reused throughout)

### Computational Complexity
- **Time**: $O(|N|^2 \cdot |L|)$ for BFS-based implementation
- **Space**: $O(|L|)$ for storing centrality values
- **Caching**: Computed once per network instance, not per iteration

### Example Output (Abilene Network)

Top 5 most critical links by betweenness centrality:
```
IPLSng_KSCYng: 0.3788   # Indianapolis-Kansas City: 37.88% of paths
ATLAng_HSTNng: 0.3788   # Atlanta-Houston: 37.88% of paths  
DNVRng_KSCYng: 0.3030   # Denver-Kansas City: 30.30% of paths
ATLAng_IPLSng: 0.2727   # Atlanta-Indianapolis: 27.27% of paths
HSTNng_LOSAng: 0.2576   # Houston-Los Angeles: 25.76% of paths
```

## Motivation and Expected Impact

### Why Centrality Matters

1. **Topological vs. Load-Based Failures**:
   - Existing features (capacity, flow, utilization) capture **load-based** failures
   - Centrality captures **topological** importance independent of current flows
   - A link can have low utilization but high centrality (critical for backup paths)

2. **Predictive Power for Network Design**:
   - High-centrality links are natural bottlenecks
   - Failures of high-centrality links force traffic onto longer alternate paths
   - More likely to cause capacity violations even if currently underutilized

3. **Complementary Information**:
   - **High centrality + high utilization** → Very likely to generate cuts
   - **High centrality + low utilization** → May generate cuts if backup paths are insufficient
   - **Low centrality + high utilization** → May be overloaded but has redundant routing options

### Expected Benefits

1. **Improved Prediction Accuracy**:
   - Distinguish between critical bottlenecks and redundant overloaded links
   - Better early-iteration predictions (before historical scores accumulate)

2. **Instance-Independent Learning**:
   - Centrality is a structural property of the network topology
   - Models trained on one instance may generalize better to similar networks

3. **Reduced Subproblem Solving**:
   - More accurate prioritization → fewer unnecessary subproblem solves
   - Focus effort on scenarios with highest combined topological and load-based risk

## Validation and Testing

### Unit Tests
✓ Centrality computation verified on Abilene network (12 nodes, 15 links)
✓ Feature extraction correctly integrates centrality values
✓ Averaging works correctly for k-contingency scenarios

### Integration Tests
- Model initializes with 10 features (previously 9)
- Centrality passed through entire ML pipeline
- Metrics display updated to show centrality weights

## Future Work

### Alternative Centrality Metrics
- **Edge betweenness (weighted)**: Account for link capacities
- **Edge betweenness (flow-based)**: Consider actual traffic patterns
- **Closeness centrality**: Average distance to all other nodes
- **Eigenvector centrality**: Influence propagation through network

### Dynamic Centrality
- Update centrality after link failures (conditional betweenness)
- Requires efficient incremental computation algorithms

### Multi-Objective Centrality
- Combine multiple centrality metrics into composite score
- Learn optimal weighting through ML training

## References

1. **Betweenness Centrality**: 
   - Freeman, L. C. (1977). "A set of measures of centrality based on betweenness." *Sociometry*, 40(1), 35-41.

2. **Network Reliability and Centrality**:
   - Latora, V., & Marchiori, M. (2001). "Efficient behavior of small-world networks." *Physical Review Letters*, 87(19), 198701.

3. **Vulnerability Analysis**:
   - Crucitti, P., Latora, V., Marchiori, M., & Rapisarda, A. (2003). "Efficiency of scale-free networks: error and attack tolerance." *Physica A*, 320, 622-642.

## Summary for Paper

**Added topological feature to ML model**: Link betweenness centrality (5th of 10 features) measures the fraction of shortest paths using each link, capturing structural importance independent of current flows. Computed once per instance using BFS ($O(|N|^2 |L|)$ time). For k-contingency scenarios, centrality values are averaged across all failed links. This feature enables the ML model to distinguish between critical network bottlenecks and redundant overloaded links, improving prediction accuracy especially in early iterations before historical performance data accumulates.
