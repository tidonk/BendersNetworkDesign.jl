"""
Multi-regressor machine learning-based subproblem scoring for Benders decomposition.

Implements one regressor per subproblem (scenario) to improve recall by learning
scenario-specific patterns. Each regressor predicts the probability that its 
corresponding subproblem will yield a cut given the current master solution.

Key improvements over single-regressor:
- Better recall: Each model specializes on one scenario's cut patterns
- Scenario-specific features: Locality features (k-hop neighborhoods)
- Flexible feature system: Easy to add/remove features by configuration

Uses online logistic regression with per-scenario models that update after each iteration.
"""

using LinearAlgebra
using Statistics
using Serialization


"""
    FeatureConfig

Configuration for which features to extract.

Make it easy to enable/disable features by commenting out entries.
Each boolean flag controls a group of related features.

# Feature Groups
- `failed_link_metrics`: Capacity, flow, utilization of failed link(s) [3 features]
- `failed_link_centrality`: Betweenness centrality of failed link(s) [1 feature]
- `khop_capacity`: k-hop capacity stats (avg/std/min/max) [4 features]
- `khop_flow`: k-hop flow stats (avg/std/min/max) [4 features]
- `khop_utilization`: k-hop utilization stats (avg/std/min/max) [4 features]
- `score_metrics`: Historical score components (5 features: violation, reliability, reliability_filtered, total_share, stabilization)
"""
struct FeatureConfig
    failed_link_metrics::Bool          # 3 features
    failed_link_centrality::Bool       # 1 feature
    khop_capacity::Bool                # 4 features (avg/std/min/max)
    khop_flow::Bool                    # 4 features
    khop_utilization::Bool             # 4 features
    score_metrics::Bool                # 5 features
    
    # Default: enable all features
    FeatureConfig(;
        failed_link_metrics=true,
        failed_link_centrality=false,
        khop_capacity=true,
        khop_flow=false,
        khop_utilization=true,
        score_metrics=true
    ) = new(failed_link_metrics, failed_link_centrality, khop_capacity, 
            khop_flow, khop_utilization, score_metrics)
end

"""
    count_features(config::FeatureConfig) -> Int

Count total number of features based on configuration.
"""
function count_features(config::FeatureConfig)::Int
    count = 0
    config.failed_link_metrics && (count += 3)
    config.failed_link_centrality && (count += 1)
    config.khop_capacity && (count += 4)
    config.khop_flow && (count += 4)
    config.khop_utilization && (count += 4)
    config.score_metrics && (count += 5)
    return count
end

"""
    MultiRegressorML

One logistic regression model per subproblem for scenario-specific prediction.

Each regressor learns patterns specific to its scenario (which link(s) fail).
Aggregates metrics across all regressors for overall performance tracking.

# Fields
- `regressors::Dict{Int,OnlineLogisticRegression}`: Map scenario_id => regressor
- `n_features::Int`: Number of features per regressor
- `feature_config::FeatureConfig`: Which features are enabled
- `khop_distance::Int`: Neighborhood radius for locality features
- `learning_rate::Float64`: Learning rate for all regressors
- `regularization::Float64`: L2 regularization for all regressors
- `decision_threshold::Float64`: Classification threshold (lower = higher recall)
- `positive_class_weight::Float64`: Weight for positive class (higher = higher recall)
"""
mutable struct MultiRegressorML
    regressors::Dict{Int,OnlineLogisticRegression}
    n_features::Int
    feature_config::FeatureConfig
    khop_distance::Int
    learning_rate::Float64
    regularization::Float64
    decision_threshold::Float64
    positive_class_weight::Float64
    
    function MultiRegressorML(n_scenarios::Int;
                             feature_config::FeatureConfig=FeatureConfig(),
                             khop_distance::Int=2,
                             learning_rate::Float64=0.02,
                             regularization::Float64=0.001,
                             decision_threshold::Float64=0.3,
                             positive_class_weight::Float64=3.0)
        n_features = count_features(feature_config)
        regressors = Dict{Int,OnlineLogisticRegression}()
        
        # Pre-create all regressors (scenario IDs typically 1 to n_scenarios)
        for scenario_id in 1:n_scenarios
            regressors[scenario_id] = OnlineLogisticRegression(
                n_features, 
                learning_rate=learning_rate,
                regularization=regularization,
                decision_threshold=decision_threshold,
                positive_class_weight=positive_class_weight
            )
        end
        
        new(regressors, n_features, feature_config, khop_distance, learning_rate, regularization,
            decision_threshold, positive_class_weight)
    end
end

"""
    build_adjacency_list(nodes, links) -> Dict{String,Vector{String}}

Build adjacency list for network graph traversal.

Returns map: node_id => [neighbor_ids]
"""
function build_adjacency_list(nodes, links)::Dict{String,Vector{String}}
    adjacency = Dict{String,Vector{String}}()
    
    # Initialize all nodes
    for node_id in keys(nodes)
        adjacency[node_id] = String[]
    end
    
    # Add edges (both directions for undirected graph)
    for link in values(links)
        push!(adjacency[link.source], link.target)
        push!(adjacency[link.target], link.source)
    end
    
    return adjacency
end

"""
    get_khop_neighbors(node_id::String, adjacency::Dict{String,Vector{String}}, k::Int) -> Set{String}

Get all nodes within k hops of given node using BFS.

# Arguments
- `node_id`: Starting node
- `adjacency`: Adjacency list (node => neighbors)
- `k`: Maximum hop distance

# Returns
Set of node IDs within k hops (excludes starting node)
"""
function get_khop_neighbors(node_id::String, adjacency::Dict{String,Vector{String}}, k::Int)::Set{String}
    k <= 0 && return Set{String}()
    
    neighbors = Set{String}()
    visited = Set{String}([node_id])
    current_level = [node_id]
    
    for hop in 1:k
        next_level = String[]
        for node in current_level
            for neighbor in get(adjacency, node, String[])
                if !(neighbor in visited)
                    push!(visited, neighbor)
                    push!(neighbors, neighbor)
                    push!(next_level, neighbor)
                end
            end
        end
        current_level = next_level
        isempty(current_level) && break
    end
    
    return neighbors
end

"""
    get_links_in_khop_neighborhood(failed_link_id::String, links, adjacency::Dict{String,Vector{String}}, k::Int) -> Vector{String}

Get all link IDs in k-hop neighborhood of a failed link.

# Algorithm
1. Get source and target nodes of failed link
2. Find all nodes within k hops of either endpoint
3. Return all links with both endpoints in the neighborhood

# Returns
Vector of link IDs in k-hop neighborhood (excludes failed link itself)
"""
function get_links_in_khop_neighborhood(failed_link_id::String, 
                                       links,
                                       adjacency::Dict{String,Vector{String}}, 
                                       k::Int)::Vector{String}
    k <= 0 && return String[]
    
    # Get failed link endpoints
    failed_link = links[failed_link_id]
    source = failed_link.source
    target = failed_link.target
    
    # Get nodes within k hops of either endpoint
    neighborhood = Set{String}([source, target])
    union!(neighborhood, get_khop_neighbors(source, adjacency, k))
    union!(neighborhood, get_khop_neighbors(target, adjacency, k))
    
    # Find all links with both endpoints in neighborhood (excluding failed link)
    neighborhood_links = String[]
    for (link_id, link) in links
        if link_id != failed_link_id && 
           link.source in neighborhood && 
           link.target in neighborhood
            push!(neighborhood_links, link_id)
        end
    end
    
    return neighborhood_links
end

"""
    compute_khop_stats(values::Vector{Float64}) -> Tuple{Float64,Float64,Float64,Float64}

Compute statistics (avg, std, min, max) for a vector of values.

Returns (0, 0, 0, 0) for empty vectors.
"""
function compute_khop_stats(values::Vector{Float64})::Tuple{Float64,Float64,Float64,Float64}
    isempty(values) && return (0.0, 0.0, 0.0, 0.0)
    
    avg = mean(values)
    std_val = length(values) > 1 ? std(values) : 0.0
    min_val = minimum(values)
    max_val = maximum(values)
    
    return (avg, std_val, min_val, max_val)
end

"""
    extract_multi_regressor_features(
        y_values, link_modules, failed_link_indices, f_base_values, link_list,
        nodes, links, adjacency, link_centrality, subproblem_scores,
        scenario_id, feature_config, khop_distance
    ) -> Vector{Float64}

Extract feature vector for multi-regressor prediction.

Features are organized by groups (controlled by FeatureConfig):
1. Failed link metrics: capacity, flow, utilization (averaged over failed links)
2. Failed link centrality: betweenness centrality (averaged)
3. k-hop capacity: avg/std/min/max of installed capacity in k-hop neighborhood
4. k-hop flow: avg/std/min/max of base flows in k-hop neighborhood
5. k-hop utilization: avg/std/min/max of utilization ratios in k-hop neighborhood
6. Score metrics: r_violation, r_reliability, r_reliability_filtered, r_total_share, r_stabilization

# Arguments
- `y_values`: Module installation decisions
- `link_modules`: Link module specifications
- `failed_link_indices`: Failed link indices for this scenario
- `f_base_values`: Base flow solution
- `link_list`: Ordered list of link IDs
- `nodes`: Network nodes (for adjacency)
- `links`: Network links
- `adjacency`: Precomputed adjacency list
- `link_centrality`: Betweenness centrality per link
- `subproblem_scores`: Score tracking dict
- `scenario_id`: Scenario ID (for score lookup)
- `feature_config`: Which features to extract
- `khop_distance`: Neighborhood radius

# Returns
Feature vector with length determined by feature_config
"""
function extract_multi_regressor_features(
    y_values,
    link_modules,
    failed_link_indices,
    f_base_values,
    link_list,
    nodes,
    links,
    adjacency,
    link_centrality,
    subproblem_scores,
    scenario_id::Int,
    feature_config::FeatureConfig,
    khop_distance::Int
)::Vector{Float64}
    
    features = Float64[]
    
    # Precompute flow index for efficiency
    flow_by_link = Dict{String, Float64}()
    for ((d, (l, dir)), flow_val) in f_base_values
        flow_by_link[l] = get(flow_by_link, l, 0.0) + abs(flow_val)
    end
    
    # Get failed link IDs
    failed_link_ids = [link_list[idx] for idx in failed_link_indices]
    num_failed = length(failed_link_ids)
    
    # ========================================
    # 1. Failed Link Metrics (3 features)
    # ========================================
    if feature_config.failed_link_metrics
        total_capacity = 0.0
        total_flow = 0.0
        total_utilization = 0.0
        
        for failed_link_id in failed_link_ids
            # Installed capacity
            capacity = 0.0
            if haskey(link_modules, failed_link_id)
                mods = link_modules[failed_link_id]
                for m in eachindex(mods)
                    if haskey(y_values, (failed_link_id, m))
                        capacity += mods[m][2] * y_values[(failed_link_id, m)]
                    end
                end
            end
            total_capacity += capacity
            
            # Base flow
            flow = get(flow_by_link, failed_link_id, 0.0)
            total_flow += flow
            
            # Utilization
            utilization = capacity > 1e-6 ? flow / capacity : 0.0
            total_utilization += utilization
        end
        
        # Average over failed links
        push!(features, total_capacity / num_failed)
        push!(features, total_flow / num_failed)
        push!(features, total_utilization / num_failed)
    end
    
    # ========================================
    # 2. Failed Link Centrality (1 feature)
    # ========================================
    if feature_config.failed_link_centrality
        centrality_sum = 0.0
        if link_centrality !== nothing
            for failed_link_id in failed_link_ids
                centrality_sum += get(link_centrality, failed_link_id, 0.0)
            end
        end
        push!(features, centrality_sum / num_failed)
    end
    
    # ========================================
    # 3-5. k-hop Neighborhood Features (12 features)
    # ========================================
    # Compute k-hop neighborhood once (union over all failed links)
    neighborhood_link_ids = Set{String}()
    for failed_link_id in failed_link_ids
        khop_links = get_links_in_khop_neighborhood(failed_link_id, links, adjacency, khop_distance)
        union!(neighborhood_link_ids, khop_links)
    end
    
    # Collect capacity, flow, utilization for all neighborhood links
    khop_capacities = Float64[]
    khop_flows = Float64[]
    khop_utilizations = Float64[]
    
    for link_id in neighborhood_link_ids
        # Capacity
        capacity = 0.0
        if haskey(link_modules, link_id)
            mods = link_modules[link_id]
            for m in eachindex(mods)
                if haskey(y_values, (link_id, m))
                    capacity += mods[m][2] * y_values[(link_id, m)]
                end
            end
        end
        push!(khop_capacities, capacity)
        
        # Flow
        flow = get(flow_by_link, link_id, 0.0)
        push!(khop_flows, flow)
        
        # Utilization
        utilization = capacity > 1e-6 ? flow / capacity : 0.0
        push!(khop_utilizations, utilization)
    end
    
    # 3. k-hop capacity stats (4 features)
    if feature_config.khop_capacity
        avg, std_val, min_val, max_val = compute_khop_stats(khop_capacities)
        push!(features, avg, std_val, min_val, max_val)
    end
    
    # 4. k-hop flow stats (4 features)
    if feature_config.khop_flow
        avg, std_val, min_val, max_val = compute_khop_stats(khop_flows)
        push!(features, avg, std_val, min_val, max_val)
    end
    
    # 5. k-hop utilization stats (4 features)
    if feature_config.khop_utilization
        avg, std_val, min_val, max_val = compute_khop_stats(khop_utilizations)
        push!(features, avg, std_val, min_val, max_val)
    end
    
    # ========================================
    # 6. Score Metrics (5 features)
    # ========================================
    if feature_config.score_metrics
        score = (subproblem_scores !== nothing && haskey(subproblem_scores, scenario_id)) ? 
                subproblem_scores[scenario_id] : nothing
        
        r_violation = score !== nothing ? Float64(score.r_violation) : 0.0
        r_reliability = score !== nothing ? Float64(score.r_reliability) : 0.0
        r_reliability_filtered = score !== nothing ? Float64(score.r_reliability_filtered) : 0.0
        r_total_share = score !== nothing ? Float64(score.r_total_share) : 0.0
        r_stabilization = score !== nothing ? Float64(score.r_stabilization) : 0.0
        
        push!(features, r_violation, r_reliability, r_reliability_filtered, r_total_share, r_stabilization)
    end
    
    return features
end

"""
    predict_multi_regressor(
        model::MultiRegressorML, scenario_id::Int,
        y_values, link_modules, failed_link_indices, f_base_values, link_list,
        nodes, links, adjacency, link_centrality, subproblem_scores
    ) -> Float64

Predict probability that scenario will yield a cut using its dedicated regressor.

# Returns
Probability in [0, 1] that subproblem will be infeasible
"""
function predict_multi_regressor(
    model::MultiRegressorML,
    scenario_id::Int,
    y_values,
    link_modules,
    failed_link_indices,
    f_base_values,
    link_list,
    nodes,
    links,
    adjacency,
    link_centrality,
    subproblem_scores
)::Float64
    
    # Get or create regressor for this scenario
    if !haskey(model.regressors, scenario_id)
        model.regressors[scenario_id] = OnlineLogisticRegression(
            model.n_features,
            learning_rate=model.learning_rate,
            regularization=model.regularization
        )
    end
    
    regressor = model.regressors[scenario_id]
    
    # Extract features
    features = extract_multi_regressor_features(
        y_values, link_modules, failed_link_indices, f_base_values, link_list,
        nodes, links, adjacency, link_centrality, subproblem_scores,
        scenario_id, model.feature_config, model.khop_distance
    )
    
    @assert length(features) == model.n_features "Feature dimension mismatch: got $(length(features)), expected $(model.n_features)"
    
    # Predict using scenario-specific regressor
    return predict_proba(regressor, features)
end

"""
    train_multi_regressor!(
        model::MultiRegressorML, scenario_id::Int, was_infeasible::Bool,
        y_values, link_modules, failed_link_indices, f_base_values, link_list,
        nodes, links, adjacency, link_centrality, subproblem_scores
    )

Train scenario-specific regressor on one outcome.

Updates the regressor for given scenario_id based on whether it yielded a cut.
"""
function train_multi_regressor!(
    model::MultiRegressorML,
    scenario_id::Int,
    was_infeasible::Bool,
    y_values,
    link_modules,
    failed_link_indices,
    f_base_values,
    link_list,
    nodes,
    links,
    adjacency,
    link_centrality,
    subproblem_scores
)::Nothing
    
    # Get or create regressor
    if !haskey(model.regressors, scenario_id)
        model.regressors[scenario_id] = OnlineLogisticRegression(
            model.n_features,
            learning_rate=model.learning_rate,
            regularization=model.regularization
        )
    end
    
    regressor = model.regressors[scenario_id]
    
    # Extract features
    features = extract_multi_regressor_features(
        y_values, link_modules, failed_link_indices, f_base_values, link_list,
        nodes, links, adjacency, link_centrality, subproblem_scores,
        scenario_id, model.feature_config, model.khop_distance
    )
    
    @assert length(features) == model.n_features "Feature dimension mismatch: got $(length(features)), expected $(model.n_features)"
    
    # Train scenario-specific regressor
    update!(regressor, features, was_infeasible, scenario_id)
    
    return nothing
end

"""
    aggregate_metrics(model::MultiRegressorML) -> MLMetrics

Aggregate metrics across all regressors into single MLMetrics object.

Sums up TP/TN/FP/FN counts from all scenario-specific regressors.
Does not aggregate prediction history (too memory-intensive).
"""
function aggregate_metrics(model::MultiRegressorML)::MLMetrics
    aggregated = MLMetrics()
    
    for regressor in values(model.regressors)
        aggregated.total_predictions += regressor.metrics.total_predictions
        aggregated.true_positives += regressor.metrics.true_positives
        aggregated.true_negatives += regressor.metrics.true_negatives
        aggregated.false_positives += regressor.metrics.false_positives
        aggregated.false_negatives += regressor.metrics.false_negatives
    end
    
    return aggregated
end

"""
    save_multi_regressor_model(model::MultiRegressorML, filepath::String)

Save multi-regressor model to disk.
"""
function save_multi_regressor_model(model::MultiRegressorML, filepath::String)::Nothing
    open(filepath, "w") do io
        serialize(io, model)
    end
    
    n_regressors = length(model.regressors)
    total_updates = sum(r.n_updates for r in values(model.regressors))
    println("Multi-regressor ML model saved to: $filepath")
    println("  Regressors: $n_regressors, Total updates: $total_updates")
    
    return nothing
end

"""
    load_multi_regressor_model(filepath::String) -> MultiRegressorML

Load multi-regressor model from disk.
"""
function load_multi_regressor_model(filepath::String)::MultiRegressorML
    model = open(filepath, "r") do io
        deserialize(io)
    end
    
    n_regressors = length(model.regressors)
    total_updates = sum(r.n_updates for r in values(model.regressors))
    println("Multi-regressor ML model loaded from: $filepath")
    println("  Regressors: $n_regressors, Total updates: $total_updates")
    
    return model
end
