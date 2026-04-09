"""
Cut filtering strategies for Benders decomposition.

Implements methods to select which cuts to add after solving multiple subproblems,
decoupling subproblem solving from cut addition.
"""

using LinearAlgebra
using Clustering
using Distances

"""
    CutCandidate

Represents a candidate cut with metadata for filtering decisions.

# Fields
- `cut_lhs`: Left-hand side expression
- `cut_rhs`: Right-hand side value
- `violation`: Violation amount at current solution
- `scenario_id`: ID of scenario that generated this cut
- `coefficients`: Vector of non-zero coefficients (for diversity/efficacy)
"""
struct CutCandidate
    cut_lhs::Any  # AffExpr
    cut_rhs::Float64
    violation::Float64
    scenario_id::Int
    coefficients::Vector{Float64}
end

"""
    CutFilteringStrategy

Abstract type for cut filtering strategies.
"""
abstract type CutFilteringStrategy end

"""
    NoFiltering <: CutFilteringStrategy

Add all cuts from solved subproblems (current implementation).
"""
struct NoFiltering <: CutFilteringStrategy end

"""
    DiversityFiltering <: CutFilteringStrategy

Select k cuts with maximally diverse support structures.

# TODO: Implement diversity filtering
Measure diversity by comparing which decision variables appear with non-zero
coefficients in each cut. Steps:
1. Extract support set (indices of non-zero coefficients) for each cut
2. Compute pairwise Jaccard distance: 1 - |A ∩ B| / |A ∪ B|
3. Greedily select cuts to maximize minimum pairwise distance
4. Alternative: Use clustering to select representative cuts

Benefits: Prevents redundancy where multiple similar cuts provide little
marginal value. Cuts with different link/module combinations provide
complementary information to the master problem.
"""
struct DiversityFiltering <: CutFilteringStrategy
    max_cuts::Int
    min_diversity::Float64  # Minimum Jaccard distance threshold
    
    DiversityFiltering(max_cuts=5, min_diversity=0.3) = new(max_cuts, min_diversity)
end

"""
    EfficacyFiltering <: CutFilteringStrategy

Rank cuts by efficacy (violation / coefficient norm).

# TODO: Implement efficacy-based filtering
Efficacy = violation / ||coefficients||_2

High efficacy cuts provide strong violation relative to geometric "size",
making them more likely to remain active in subsequent iterations.
This metric is widely used in MIP solvers for cutting plane selection.

Steps:
1. For each cut, compute ||π||_2 where π is vector of y-variable coefficients
2. Compute efficacy = violation / ||π||_2
3. Sort cuts by descending efficacy
4. Add top-k cuts

Alternative norms: L1 norm (sum of absolute coefficients) or L∞ norm (max coefficient).
"""
struct EfficacyFiltering <: CutFilteringStrategy
    max_cuts::Int
    norm_type::Symbol  # :l2, :l1, or :linf
    
    EfficacyFiltering(max_cuts=5, norm_type=:l2) = new(max_cuts, norm_type)
end

"""
    HybridFiltering <: CutFilteringStrategy

Combine multiple criteria using weighted scoring.

# TODO: Implement hybrid filtering
Score each cut by: w_v * violation + w_e * efficacy + w_d * diversity

where:
- violation: raw violation amount (normalized to [0,1])
- efficacy: violation / ||coefficients|| (normalized to [0,1])
- diversity: minimum distance to already-selected cuts

Algorithm:
1. Normalize violation and efficacy across all candidate cuts
2. Iteratively select cuts with highest combined score
3. Update diversity component after each selection
4. Stop when k cuts selected or no cuts meet threshold

Weights can be tuned based on solution phase:
- Early: emphasize diversity (explore different constraint structures)
- Middle: balance all criteria
- Late: emphasize violation (focus on most critical constraints)
"""
struct HybridFiltering <: CutFilteringStrategy
    max_cuts::Int
    weight_violation::Float64
    weight_efficacy::Float64
    weight_diversity::Float64
    
    HybridFiltering(max_cuts=5, w_v=0.5, w_e=0.3, w_d=0.2) = 
        new(max_cuts, w_v, w_e, w_d)
end

"""
    filter_cuts(cuts, strategy) -> Vector{CutCandidate}

Apply filtering strategy to select which cuts to add.

# Arguments
- `cuts`: Vector of CutCandidate
- `strategy`: CutFilteringStrategy instance

# Returns
Filtered vector of cuts to add to master problem

# Current implementation (NoFiltering)
Returns all cuts unchanged.
"""
function filter_cuts(cuts::Vector{CutCandidate}, strategy::NoFiltering)::Vector{CutCandidate}
    return cuts  # Add all cuts
end

"""
    filter_cuts(cuts, strategy::DiversityFiltering) -> Vector{CutCandidate}

Select k geometrically diverse cuts using greedy algorithm.

Greedily selects cuts to maximize minimum pairwise Jaccard distance,
ensuring selected cuts have different support structures.

# Algorithm
1. Select cut with highest violation as first cut
2. Iteratively select cut with maximum minimum distance to already-selected cuts
3. Stop when k cuts selected or all remaining cuts too similar

# Returns
Up to max_cuts diverse cuts
"""
function filter_cuts(cuts::Vector{CutCandidate}, strategy::DiversityFiltering)::Vector{CutCandidate}
    isempty(cuts) && return cuts
    length(cuts) <= strategy.max_cuts && return cuts
    
    # Use DBSCAN clustering to find diverse cuts
    selected = select_cuts_dbscan(cuts, strategy.max_cuts, strategy.min_diversity)
    
    return selected
end

"""
    select_cuts_dbscan(cuts, max_cuts, min_diversity) -> Vector{CutCandidate}

Select representative cuts using DBSCAN clustering.

Clusters cuts based on coefficient similarity and selects medoids
(most representative cuts) from each cluster.

# Algorithm
1. Build distance matrix using Jaccard distance on coefficient support
2. Apply DBSCAN clustering with min_diversity as epsilon (radius)
3. For each cluster, select the medoid (most central point)
4. Return medoids from all clusters (up to one per cluster)
"""
function select_cuts_dbscan(cuts::Vector{CutCandidate}, max_cuts::Int, min_diversity::Float64)::Vector{CutCandidate}
    n = length(cuts)
    
    # Build distance matrix
    dist_matrix = zeros(n, n)
    for i in 1:n
        for j in (i+1):n
            dist = compute_cut_diversity(cuts[i], cuts[j])
            dist_matrix[i, j] = dist
            dist_matrix[j, i] = dist
        end
    end
    
    # Use Clustering.jl's DBSCAN with precomputed distances
    # eps = min_diversity (maximum distance for points to be in same neighborhood)
    # min_neighbors = 1 (every point forms or joins a cluster)
    clustering_result = dbscan(dist_matrix, min_diversity, min_neighbors=1, metric=nothing)
    
    # Select medoid from each cluster
    selected = CutCandidate[]
    
    for cluster in clustering_result.clusters
        cluster_indices = cluster.core_indices
        
        # Find medoid: point with minimum average distance to other points in cluster
        if length(cluster_indices) == 1
            # Single element: it's trivially the medoid (center)
            medoid_idx = cluster_indices[1]
        else
            # Multiple elements: compute medoid as point with minimum average distance
            avg_dists = [mean(dist_matrix[idx, cluster_indices]) for idx in cluster_indices]
            medoid_idx = cluster_indices[argmin(avg_dists)]
        end
        
        push!(selected, cuts[medoid_idx])
    end
    
    return selected
end

"""
    filter_cuts(cuts, strategy::EfficacyFiltering) -> Vector{CutCandidate}

Select k cuts with highest efficacy scores.

Efficacy = violation / ||coefficients|| measures cut quality relative to geometric size.
"""
function filter_cuts(cuts::Vector{CutCandidate}, strategy::EfficacyFiltering)::Vector{CutCandidate}
    isempty(cuts) && return cuts
    length(cuts) <= strategy.max_cuts && return cuts
    
    # Compute efficacy for each cut
    efficacies = [compute_cut_efficacy(c, strategy.norm_type) for c in cuts]
    
    # Select top-k by efficacy
    indices = sortperm(efficacies, rev=true)
    return cuts[indices[1:min(strategy.max_cuts, length(cuts))]]
end

"""
    filter_cuts(cuts, strategy::HybridFiltering) -> Vector{CutCandidate}

Select k cuts using weighted combination of violation, efficacy, and diversity.

Iteratively selects cuts with highest combined score, updating diversity component
after each selection.
"""
function filter_cuts(cuts::Vector{CutCandidate}, strategy::HybridFiltering)::Vector{CutCandidate}
    isempty(cuts) && return cuts
    length(cuts) <= strategy.max_cuts && return cuts
    
    # Normalize violation and efficacy to [0,1]
    violations = [c.violation for c in cuts]
    efficacies = [compute_cut_efficacy(c, :l2) for c in cuts]
    
    v_min, v_max = extrema(violations)
    e_min, e_max = extrema(efficacies)
    
    norm_violations = v_max > v_min ? (violations .- v_min) ./ (v_max - v_min) : ones(length(cuts))
    norm_efficacies = e_max > e_min ? (efficacies .- e_min) ./ (e_max - e_min) : ones(length(cuts))
    
    selected = CutCandidate[]
    remaining_indices = collect(1:length(cuts))
    
    # Iteratively select cuts
    while length(selected) < strategy.max_cuts && !isempty(remaining_indices)
        best_idx = -1
        best_score = -Inf
        
        for (pos, idx) in enumerate(remaining_indices)
            # Compute diversity component (minimum distance to selected cuts)
            diversity = isempty(selected) ? 1.0 : minimum(compute_cut_diversity(cuts[idx], s) for s in selected)
            
            # Combined score
            score = (strategy.weight_violation * norm_violations[idx] +
                    strategy.weight_efficacy * norm_efficacies[idx] +
                    strategy.weight_diversity * diversity)
            
            if score > best_score
                best_score = score
                best_idx = pos
            end
        end
        
        idx = remaining_indices[best_idx]
        push!(selected, cuts[idx])
        deleteat!(remaining_indices, best_idx)
    end
    
    return selected
end

"""
    compute_cut_diversity(cut1, cut2) -> Float64

Compute diversity score between two cuts based on support overlap.

Uses Jaccard distance on coefficient support:
    diversity = 1 - |support(c1) ∩ support(c2)| / |support(c1) ∪ support(c2)|

where support is the set of indices with non-zero coefficients.

Returns value in [0, 1] where:
- 0 = identical support (same variables)
- 1 = completely disjoint support (no common variables)
"""
function compute_cut_diversity(cut1::CutCandidate, cut2::CutCandidate)::Float64
    # Get support sets (indices of non-zero coefficients)
    support1 = Set(i for (i, c) in enumerate(cut1.coefficients) if abs(c) > 1e-10)
    support2 = Set(i for (i, c) in enumerate(cut2.coefficients) if abs(c) > 1e-10)
    
    # Handle edge cases
    if isempty(support1) && isempty(support2)
        return 0.0  # Both empty -> identical
    end
    if isempty(support1) || isempty(support2)
        return 1.0  # One empty, one not -> completely different
    end
    
    # Jaccard distance: 1 - (intersection / union)
    intersection_size = length(intersect(support1, support2))
    union_size = length(union(support1, support2))
    
    return 1.0 - (intersection_size / union_size)
end

"""
    compute_cut_efficacy(cut, norm_type) -> Float64

Compute efficacy score for a cut.

Efficacy = violation / norm(coefficients, p)

where p depends on norm_type:
- :l1 -> p=1 (sum of absolute values)
- :l2 -> p=2 (Euclidean norm) [default]
- :linf -> p=Inf (maximum absolute value)

High efficacy indicates strong violation relative to geometric "size",
making the cut more likely to remain active in subsequent iterations.
"""
function compute_cut_efficacy(cut::CutCandidate, norm_type::Symbol=:l2)::Float64
    isempty(cut.coefficients) && return 0.0
    
    coef_norm = if norm_type == :l1
        sum(abs, cut.coefficients)
    elseif norm_type == :l2
        norm(cut.coefficients, 2)
    elseif norm_type == :linf
        maximum(abs, cut.coefficients)
    else
        error("Unknown norm type: $norm_type. Use :l1, :l2, or :linf")
    end
    
    return coef_norm > 1e-10 ? cut.violation / coef_norm : 0.0
end

"""
    extract_cut_coefficients(cut_lhs, num_vars) -> Vector{Float64}

Extract coefficient vector from cut expression for analysis.

Parses JuMP AffExpr to extract all variable coefficients into a dense vector
for computing norms and diversity metrics.

# Arguments
- `cut_lhs`: JuMP AffExpr or GenericAffExpr
- `num_vars`: Total number of variables (for dense vector size)

# Returns
Dense vector of coefficients indexed by variable
"""
function extract_cut_coefficients(cut_lhs, num_vars::Int)::Vector{Float64}
    coeffs = zeros(Float64, num_vars)
    
    # Extract coefficients from AffExpr
    for (var, coef) in cut_lhs.terms
        var_idx = var.index.value
        if var_idx <= num_vars
            coeffs[var_idx] = coef
        end
    end
    
    return coeffs
end

"""
    extract_cut_coefficients(cut_lhs) -> Vector{Float64}

Extract coefficient vector from cut expression (sparse representation).

Returns only non-zero coefficients for efficiency.
"""
function extract_cut_coefficients(cut_lhs)::Vector{Float64}
    coeffs = Float64[]
    
    # Extract non-zero coefficients from AffExpr
    for (var, coef) in cut_lhs.terms
        if abs(coef) > 1e-10
            push!(coeffs, coef)
        end
    end
    
    return coeffs
end

"""
    create_filtering_strategy(settings) -> CutFilteringStrategy

Create cut filtering strategy from settings.

# Arguments
- `settings`: Settings object with cut filtering configuration

# Returns
CutFilteringStrategy instance based on settings.cut_filtering_strategy
"""
function create_filtering_strategy(settings)::CutFilteringStrategy
    strategy = settings.cut_filtering_strategy
    
    if strategy == "none"
        return NoFiltering()
    elseif strategy == "diversity"
        return DiversityFiltering(
            settings.cut_filtering_max_cuts,
            settings.cut_filtering_diversity_threshold
        )
    elseif strategy == "efficacy"
        norm_type = Symbol(settings.cut_filtering_efficacy_norm)
        return EfficacyFiltering(
            settings.cut_filtering_max_cuts,
            norm_type
        )
    elseif strategy == "hybrid"
        weights = settings.cut_filtering_hybrid_weights
        return HybridFiltering(
            settings.cut_filtering_max_cuts,
            weights[1],  # violation weight
            weights[2],  # efficacy weight
            weights[3]   # diversity weight
        )
    else
        error("Unknown cut filtering strategy: $strategy")
    end
end
