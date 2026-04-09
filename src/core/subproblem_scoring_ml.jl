"""
Machine learning-based subproblem scoring for Benders decomposition.

Implements online learning to predict which contingency subproblems (line outages)
will be infeasible and yield cuts, based on master solution features.

Uses a simple online logistic regression model that updates after each iteration.
"""

using LinearAlgebra
using Statistics
using Serialization

"""
    MLMetrics

Tracks prediction performance metrics for ML model evaluation.

# Fields
- `total_predictions::Int`: Total number of predictions made
- `true_positives::Int`: Correctly predicted infeasible (cut found)
- `true_negatives::Int`: Correctly predicted feasible (no cut)
- `false_positives::Int`: Predicted infeasible but was feasible
- `false_negatives::Int`: Predicted feasible but was infeasible
- `prediction_history::Vector{Tuple{Float64,Bool,Bool}}`: (prediction, actual, correct) history
"""
mutable struct MLMetrics
    total_predictions::Int
    true_positives::Int
    true_negatives::Int
    false_positives::Int
    false_negatives::Int
    prediction_history::Vector{Tuple{Float64,Bool,Bool}}  # (prediction_prob, was_infeasible, was_correct)
    
    MLMetrics() = new(0, 0, 0, 0, 0, Tuple{Float64,Bool,Bool}[])
end

"""
    OnlineLogisticRegression

Simple online logistic regression classifier for predicting subproblem infeasibility.

Trained incrementally as master solutions evolve during Benders iterations.
Uses stochastic gradient descent for weight updates with prediction quality tracking.

# Fields
- `weights::Vector{Float64}`: Feature weights (coefficients)
- `bias::Float64`: Intercept term
- `learning_rate::Float64`: Step size for gradient descent
- `regularization::Float64`: L2 regularization parameter
- `n_features::Int`: Number of features in the model
- `n_updates::Int`: Number of training updates performed
- `metrics::MLMetrics`: Performance tracking metrics
- `prediction_quality::Dict{Int,Float64}`: Quality score for each scenario's predictions
- `decision_threshold::Float64`: Threshold for binary classification (default 0.5, lower for higher recall)
- `positive_class_weight::Float64`: Weight multiplier for positive class (>1.0 increases recall)
"""
mutable struct OnlineLogisticRegression
    weights::Vector{Float64}
    bias::Float64
    learning_rate::Float64
    regularization::Float64
    n_features::Int
    n_updates::Int
    metrics::MLMetrics
    prediction_quality::Dict{Int,Float64}  # scenario_id => quality score (0-1)
    feature_means::Vector{Float64}         # Running mean for normalization
    feature_stds::Vector{Float64}          # Running std for normalization
    decision_threshold::Float64            # Classification threshold (lower = higher recall)
    positive_class_weight::Float64         # Weight for positive class in loss (higher = higher recall)
    
    function OnlineLogisticRegression(n_features::Int; 
                                     learning_rate::Float64=0.02,
                                     regularization::Float64=0.001,
                                     decision_threshold::Float64=0.3,  # Lower threshold for higher recall
                                     positive_class_weight::Float64=3.0)  # Penalize false negatives 3x more
        new(zeros(n_features), 0.0, learning_rate, regularization, n_features, 0, 
            MLMetrics(), Dict{Int,Float64}(), zeros(n_features), ones(n_features),
            decision_threshold, positive_class_weight)
    end
end

"""
    sigmoid(x::Float64) -> Float64

Standard sigmoid activation function for logistic regression.
"""
function sigmoid(x::Float64)::Float64
    return 1.0 / (1.0 + exp(-x))
end

"""
    predict_proba(model::OnlineLogisticRegression, features::Vector{Float64}) -> Float64

Predict probability that a subproblem will be infeasible (yield a cut).

# Arguments
- `model`: Trained logistic regression model
- `features`: Feature vector extracted from master solution

# Returns
Probability in [0, 1] that subproblem will be infeasible
"""
function predict_proba(model::OnlineLogisticRegression, features::Vector{Float64})::Float64
    @assert length(features) == model.n_features "Feature dimension mismatch"
    
    # Fast normalization and linear combination
    z = model.bias
    @inbounds for i in 1:model.n_features
        if model.feature_stds[i] > 1e-6
            x_norm = (features[i] - model.feature_means[i]) / model.feature_stds[i]
        else
            x_norm = 0.0
        end
        z += model.weights[i] * x_norm
    end
    
    # Clamp and sigmoid
    z = clamp(z, -10.0, 10.0)
    return 1.0 / (1.0 + exp(-z))
end

"""
    update!(model::OnlineLogisticRegression, features::Vector{Float64}, label::Bool, scenario_id::Int)

Update model weights using one training example and track prediction quality.

Performs single stochastic gradient descent step with L2 regularization.
Updates metrics and prediction quality scores.

# Arguments
- `model`: Model to update (modified in-place)
- `features`: Feature vector from master solution
- `label`: True if subproblem was infeasible, False otherwise
- `scenario_id`: ID of the scenario being trained on
"""
function update!(model::OnlineLogisticRegression, features::Vector{Float64}, label::Bool, scenario_id::Int)::Nothing
    @assert length(features) == model.n_features "Feature dimension mismatch"
    
    model.n_updates += 1
    
    # Update running statistics (Welford's algorithm - needed for proper normalization)
    @inbounds for i in 1:model.n_features
        delta = features[i] - model.feature_means[i]
        model.feature_means[i] += delta / model.n_updates
        delta2 = features[i] - model.feature_means[i]
        # Update variance estimate (needed to prevent saturation)
        if model.n_updates > 1
            old_var = (model.feature_stds[i]^2) * (model.n_updates - 2)
            new_var = old_var + delta * delta2
            model.feature_stds[i] = sqrt(max(new_var / (model.n_updates - 1), 1e-8))
        end
    end
    
    # Convert label to float (1.0 for infeasible, 0.0 for feasible)
    y = label ? 1.0 : 0.0
    
    # Normalize features in-place (reuse for both prediction and gradient)
    @inbounds for i in 1:model.n_features
        if model.feature_stds[i] > 1e-6
            features[i] = (features[i] - model.feature_means[i]) / model.feature_stds[i]
        else
            features[i] = 0.0
        end
    end
    
    # Fast prediction (features already normalized)
    z = model.bias
    @inbounds for i in 1:model.n_features
        z += model.weights[i] * features[i]
    end
    z = clamp(z, -10.0, 10.0)
    pred = 1.0 / (1.0 + exp(-z))
    
    # Fast metrics update (use adjustable threshold)
    model.metrics.total_predictions += 1
    predicted_infeasible = pred > model.decision_threshold
    was_correct = (predicted_infeasible == label)
    
    if label
        if predicted_infeasible
            model.metrics.true_positives += 1
        else
            model.metrics.false_negatives += 1
        end
    else
        if predicted_infeasible
            model.metrics.false_positives += 1
        else
            model.metrics.true_negatives += 1
        end
    end
    
    # Track minimal history for statistics (still fast - just a push)
    push!(model.metrics.prediction_history, (pred, label, was_correct))
    
    # Gradient descent update with class weighting
    # Apply class weight to loss gradient (penalize false negatives more)
    error = pred - y
    weighted_error = label ? error * model.positive_class_weight : error
    
    # Fast gradient descent (features already normalized, reuse them)
    @inbounds for i in 1:model.n_features
        gradient = weighted_error * features[i] + model.regularization * model.weights[i]
        model.weights[i] -= model.learning_rate * gradient
    end
    
    model.bias -= model.learning_rate * weighted_error
    
    return nothing
end

"""
    compute_link_betweenness_centrality(network) -> Dict{String,Float64}

Compute betweenness centrality for all links in the network.

Betweenness centrality measures how many shortest paths between all node pairs
use each link. Higher values indicate more critical links for network connectivity.

# Algorithm
1. For each pair of nodes (s, t), compute shortest path using BFS
2. Count how many shortest paths use each link
3. Normalize by total number of node pairs

# Returns
Dict mapping link_id => normalized betweenness centrality [0, 1]
"""
function compute_link_betweenness_centrality(nodes, links)::Dict{String,Float64}
    # Build adjacency list for BFS
    adjacency = Dict{String,Vector{Tuple{String,String}}}()  # node => [(neighbor, link_id), ...]
    for node_id in keys(nodes)
        adjacency[node_id] = []
    end
    
    for (link_id, link) in links
        # Add both directions (undirected graph for routing)
        push!(adjacency[link.source], (link.target, link_id))
        push!(adjacency[link.target], (link.source, link_id))
    end
    
    # Initialize betweenness counts
    betweenness = Dict{String,Float64}(link_id => 0.0 for link_id in keys(links))
    
    node_ids = collect(keys(nodes))
    num_pairs = 0
    
    # For each source node, run BFS to all other nodes
    for source in node_ids
        # BFS to find shortest paths
        distances = Dict{String,Int}(source => 0)
        predecessors = Dict{String,Vector{Tuple{String,String}}}()  # node => [(prev_node, link_id), ...]
        queue = [source]
        
        while !isempty(queue)
            current = popfirst!(queue)
            current_dist = distances[current]
            
            for (neighbor, link_id) in adjacency[current]
                if !haskey(distances, neighbor)
                    # First time visiting neighbor
                    distances[neighbor] = current_dist + 1
                    predecessors[neighbor] = [(current, link_id)]
                    push!(queue, neighbor)
                elseif distances[neighbor] == current_dist + 1
                    # Another shortest path to neighbor
                    push!(predecessors[neighbor], (current, link_id))
                end
            end
        end
        
        # Count links on shortest paths from source to all other nodes
        for target in node_ids
            if target != source && haskey(predecessors, target)
                num_pairs += 1
                # Backtrack from target to source along shortest paths
                visited_nodes = Set{String}()
                visited_links = Set{String}()
                to_visit = [target]
                
                while !isempty(to_visit)
                    node = pop!(to_visit)
                    if node in visited_nodes
                        continue
                    end
                    push!(visited_nodes, node)
                    
                    if haskey(predecessors, node)
                        for (prev_node, link_id) in predecessors[node]
                            if !(link_id in visited_links)
                                betweenness[link_id] += 1.0
                                push!(visited_links, link_id)
                            end
                            if !(prev_node in visited_nodes)
                                push!(to_visit, prev_node)
                            end
                        end
                    end
                end
            end
        end
    end
    
    # Normalize by number of node pairs
    if num_pairs > 0
        for link_id in keys(betweenness)
            betweenness[link_id] /= num_pairs
        end
    end
    
    return betweenness
end

"""
    extract_subproblem_features(y_values, link_modules, failed_link_indices, f_base_values, link_list, model, scenario_id, subproblem_scores) -> Vector{Float64}

Extract feature vector for a specific contingency subproblem.

Features capture (10 deterministic features):
1-4. Failed link capacity, flows (fwd/bwd), utilization (averaged across all failed links)
5. Failed link betweenness centrality (averaged, topological importance)
6-10. Score statistics (violation, reliability, reliability_filtered, total_share, stabilization)

Note: Removed nondeterministic features in v0.7.1:
- Average solve time (timing-dependent, hardware-specific)
- Iteration number (phase indicator, not intrinsic to solution)
- Optimality gap magnitude (solver-dependent)
- Cumulative cuts added (history-dependent)

# Arguments
- `y_values`: Module installation decisions from master
- `link_modules`: Link module specifications
- `failed_link_indices`: Vector of link indices that fail in this contingency (supports k>1)
- `f_base_values`: Base case flow solution from master
- `link_list`: Ordered list of link IDs
- `model`: ML model (unused, for compatibility)
- `scenario_id`: Scenario ID (for score lookup)
- `subproblem_scores`: Score dictionary (for score components)
- `iteration`: Current iteration number (unused, for compatibility)
- `upper_bound`: Current upper bound (unused, for compatibility)
- `lower_bound`: Current lower bound (unused, for compatibility)
- `cumulative_cuts`: Total cuts added so far (unused, for compatibility)

# Returns
Feature vector for ML prediction (10 deterministic features)
"""
function extract_subproblem_features(y_values::Dict{Tuple{String,Int},Float64},
                                    link_modules::Dict{String,Vector{Tuple{Int,Float64,Float64}}},
                                    failed_link_indices::Vector{Int},
                                    f_base_values::Dict{Tuple{String,Tuple{String,Symbol}},Float64},
                                    link_list::Vector{String},
                                    model::Union{OnlineLogisticRegression,Nothing}=nothing,
                                    scenario_id::Union{Int,Nothing}=nothing,
                                    subproblem_scores::Union{Dict{Int,SubproblemScore},Nothing}=nothing,
                                    iteration::Int=0,
                                    upper_bound::Float64=Inf,
                                    lower_bound::Float64=-Inf,
                                    cumulative_cuts::Int=0,
                                    link_centrality::Union{Dict{String,Float64},Nothing}=nothing)::Vector{Float64}
    
    # For k-contingency scenarios, average the failed link metrics
    num_failed_links = length(failed_link_indices)
    @assert num_failed_links > 0 "Must have at least one failed link"
    
    # Build flow index once per call (amortized over k failed links)
    # This avoids O(k × |flows|) iteration, reducing to O(|flows| + k)
    # Aggregate flows by direction (matching capacity constraint formulation)
    flow_by_link = Dict{String, Float64}()
    for ((d, (l, dir)), flow_val) in f_base_values
        flow_by_link[l] = get(flow_by_link, l, 0.0) + abs(flow_val)
    end
    
    # Initialize accumulators for averaging
    total_capacity = 0.0
    total_flow = 0.0
    total_utilization = 0.0
    
    # Compute metrics for each failed link and accumulate
    for failed_link_index in failed_link_indices
        failed_link_id = link_list[failed_link_index]
        
        # Feature 1: Total installed capacity on failed link
        failed_link_capacity = 0.0
        if haskey(link_modules, failed_link_id)
            mods = link_modules[failed_link_id]
            for m in eachindex(mods)
                if haskey(y_values, (failed_link_id, m))
                    failed_link_capacity += mods[m][2] * y_values[(failed_link_id, m)]
                end
            end
        end
        total_capacity += failed_link_capacity
        
        # Feature 2: Total base flow on failed link (both directions)
        # Use precomputed flow index (O(1) lookup instead of O(|flows|) iteration)
        # Matches capacity constraint formulation: sum of absolute flows
        failed_link_flow = get(flow_by_link, failed_link_id, 0.0)
        total_flow += failed_link_flow
        
        # Feature 3: Utilization ratio on failed link
        failed_link_utilization = failed_link_capacity > 1e-6 ? 
                                  failed_link_flow / failed_link_capacity : 
                                  0.0
        total_utilization += failed_link_utilization
    end
    
    # Average across all failed links
    failed_link_capacity = total_capacity / num_failed_links
    failed_link_flow = total_flow / num_failed_links
    failed_link_utilization = total_utilization / num_failed_links
    
    # Feature 5: Betweenness centrality (averaged across failed links)
    failed_link_centrality = 0.0
    if link_centrality !== nothing
        for failed_link_index in failed_link_indices
            failed_link_id = link_list[failed_link_index]
            failed_link_centrality += get(link_centrality, failed_link_id, 0.0)
        end
        failed_link_centrality /= num_failed_links
    end
    
    # Extract score-based features (default to 0.0 if no score data)
    score = (scenario_id !== nothing && haskey(subproblem_scores, scenario_id)) ? 
            subproblem_scores[scenario_id] : nothing
    
    # Features 5-9: Weighted score statistics (exponentially decayed for recency bias)
    # These are deterministic given the same sequence of subproblem outcomes
    weighted_times_solved::Float64 = score !== nothing ? Float64(score.weighted_times_solved) : 0.0
    weighted_times_cut_generated::Float64 = score !== nothing ? Float64(score.weighted_times_cut_generated) : 0.0
    weighted_times_cut_added::Float64 = score !== nothing ? Float64(score.weighted_times_cut_added) : 0.0
    weighted_total_violations::Float64 = score !== nothing ? Float64(score.weighted_total_violations) : 0.0
    weighted_total_cuts_produced::Float64 = score !== nothing ? Float64(score.weighted_total_cuts_produced) : 0.0
    
    # Alternative Features 5-9: unweighted score statistics
    r_violation::Float64 = score !== nothing ? Float64(score.r_violation) : 0.0
    r_reliability::Float64 = score !== nothing ? Float64(score.r_reliability) : 0.0
    r_reliability_filtered::Float64 = 0.0#score !== nothing ? Float64(score.r_reliability_filtered) : 0.0
    r_total_share::Float64 = score !== nothing ? Float64(score.r_total_share) : 0.0
    r_stabilization::Float64 = score !== nothing ? Float64(score.r_stabilization) : 0.0

    # Construct feature vector (9 deterministic features)
    features = [
        failed_link_capacity,
        failed_link_flow,
        failed_link_utilization,
        failed_link_centrality,
        r_violation,
        r_reliability,
        r_reliability_filtered,
        r_total_share,
        r_stabilization
    ]
    
    return features
end

"""
    normalize_features(model, features) -> Vector{Float64}

Normalize features using running mean and standard deviation.
Prevents sigmoid saturation by scaling features to similar ranges.
"""
function normalize_features(model::OnlineLogisticRegression,
                           features::Vector{Float64})::Vector{Float64}
    normalized = similar(features)
    for i in 1:length(features)
        if model.feature_stds[i] > 1e-6
            normalized[i] = (features[i] - model.feature_means[i]) / model.feature_stds[i]
        else
            normalized[i] = 0.0
        end
    end
    return normalized
end

"""
    predict_subproblem_infeasibility(model, y_values, link_modules, failed_link_indices, f_base_values, link_list, scenario_id, subproblem_scores, iteration, upper_bound, lower_bound, cumulative_cuts) -> Float64

Predict probability that a specific contingency subproblem will be infeasible.

# Arguments
- `model`: Trained ML model
- `y_values`: Current master solution (module installations)
- `link_modules`: Link module specifications
- `failed_link_indices`: Vector of link indices that fail in this contingency (supports k>1)
- `f_base_values`: Base flow solution from master
- `link_list`: Ordered list of link IDs
- `scenario_id`: Scenario ID
- `subproblem_scores`: Score dictionary for reliability_filtered feature
- `iteration`: Current Benders iteration (for temporal feature)
- `upper_bound`: Current upper bound (for gap calculation)
- `lower_bound`: Current lower bound (for gap calculation)
- `cumulative_cuts`: Total cuts added so far

# Returns
Probability that subproblem will be infeasible (yield a cut)
"""
function predict_subproblem_infeasibility(model::OnlineLogisticRegression,
                                         y_values::Dict{Tuple{String,Int},Float64},
                                         link_modules::Dict{String,Vector{Tuple{Int,Float64,Float64}}},
                                         failed_link_indices::Vector{Int},
                                         f_base_values::Dict{Tuple{String,Tuple{String,Symbol}},Float64},
                                         link_list::Vector{String},
                                         scenario_id::Int,
                                         subproblem_scores::Dict{Int,SubproblemScore},
                                         iteration::Int=0,
                                         upper_bound::Float64=Inf,
                                         lower_bound::Float64=-Inf,
                                         cumulative_cuts::Int=0,
                                         link_centrality::Union{Dict{String,Float64},Nothing}=nothing)::Float64
    
    features = extract_subproblem_features(y_values, link_modules, failed_link_indices, 
                                          f_base_values, link_list, model, scenario_id, subproblem_scores,
                                          iteration, upper_bound, lower_bound, cumulative_cuts, link_centrality)
    
    return predict_proba(model, features)
end

"""
    train_subproblem_model!(model, y_values, link_modules, failed_link_indices, f_base_values, link_list, scenario_id, was_infeasible, subproblem_scores, iteration, upper_bound, lower_bound, cumulative_cuts)

Train ML model on one subproblem result.

# Arguments
- `model`: Model to update (modified in-place)
- `y_values`: Master solution when subproblem was solved
- `link_modules`: Link module specifications
- `failed_link_indices`: Vector of link indices that fail in this contingency (supports k>1)
- `f_base_values`: Base flow solution from master
- `link_list`: Ordered list of link IDs
- `scenario_id`: Scenario ID
- `was_infeasible`: Whether subproblem was infeasible (yielded cut)
- `subproblem_scores`: Score dictionary for reliability_filtered feature
- `iteration`: Current Benders iteration
- `upper_bound`: Current upper bound
- `lower_bound`: Current lower bound
- `cumulative_cuts`: Total cuts added so far
"""
function train_subproblem_model!(model::OnlineLogisticRegression,
                                y_values::Dict{Tuple{String,Int},Float64},
                                link_modules::Dict{String,Vector{Tuple{Int,Float64,Float64}}},
                                failed_link_indices::Vector{Int},
                                f_base_values::Dict{Tuple{String,Tuple{String,Symbol}},Float64},
                                link_list::Vector{String},
                                scenario_id::Int,
                                was_infeasible::Bool,
                                subproblem_scores::Dict{Int,SubproblemScore},
                                iteration::Int=0,
                                upper_bound::Float64=Inf,
                                lower_bound::Float64=-Inf,
                                cumulative_cuts::Int=0,
                                link_centrality::Union{Dict{String,Float64},Nothing}=nothing)::Nothing
    
    features = extract_subproblem_features(y_values, link_modules, failed_link_indices,
                                          f_base_values, link_list, model, scenario_id, subproblem_scores,
                                          iteration, upper_bound, lower_bound, cumulative_cuts, link_centrality)
    
    update!(model, features, was_infeasible, scenario_id)
    
    return nothing
end

"""
    save_ml_model(model::OnlineLogisticRegression, filepath::String)

Save trained ML model to disk.
"""
function save_ml_model(model::OnlineLogisticRegression, filepath::String)::Nothing
    open(filepath, "w") do io
        serialize(io, model)
    end
    println("ML model saved to: $filepath")
    return nothing
end

"""
    load_ml_model(filepath::String) -> OnlineLogisticRegression

Load trained ML model from disk.
"""
function load_ml_model(filepath::String)::OnlineLogisticRegression
    model = open(filepath, "r") do io
        deserialize(io)
    end
    println("ML model loaded from: $filepath ($(model.n_updates) training updates)")
    return model
end

