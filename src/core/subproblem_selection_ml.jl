"""
Machine learning models for subproblem selection in adaptive Benders decomposition.

Implements ProportionPredictor: predicts the proportion of subproblems that will yield cuts
before each Benders iteration using online linear regression with sigmoid activation.
"""

using Statistics
using Printf

# Import sigmoid from subproblem_scoring_ml.jl (defined there first)
# sigmoid(z) = 1 / (1 + exp(-z))

"""
    ProportionPredictor

Machine learning model to predict the proportion of subproblems that will yield cuts.

Uses online linear regression with sigmoid activation:
    proportion = σ(w^T x)

where x is a feature vector and σ is the sigmoid function.

Training uses gradient descent with mean squared error loss and L2 regularization:
    L = (y_pred - y_actual)^2 + λ||w||^2
    ∂L/∂w = 2(y_pred - y_actual) * σ'(z) * x + 2λw

# Feature Vector (8 features total):
- [1-4]: Score statistics (min, max, avg, std)
- [5-8]: Utilization statistics (min, max, avg, std)

# Fields
- `weights::Vector{Float64}`: Model weights (8 features: 4 score stats + 4 utilization stats)
- `learning_rate::Float64`: Learning rate for gradient descent
- `regularization::Float64`: L2 regularization strength (λ)
- `feature_means::Vector{Float64}`: Running mean for each feature (Welford's algorithm)
- `feature_m2::Vector{Float64}`: Running M2 for variance computation (Welford's algorithm)
- `n_samples::Int`: Number of training samples seen
- `performance_history::Vector{Float64}`: Recent proportions (for exponential averaging)
- `history_decay::Float64`: Decay factor for exponential averaging (0.9 = give 90% weight to history)
- `min_training_sample_rate::Float64`: Minimum fraction of scenarios that must be solved to train (avoid recall bias)
"""
mutable struct ProportionPredictor
    weights::Vector{Float64}
    learning_rate::Float64
    regularization::Float64
    feature_means::Vector{Float64}
    feature_m2::Vector{Float64}
    n_samples::Int
    performance_history::Vector{Float64}
    history_decay::Float64
    min_training_sample_rate::Float64
    
    function ProportionPredictor(n_features::Int=8; learning_rate::Float64=0.01, 
                                regularization::Float64=0.01, history_decay::Float64=0.9,
                                min_training_sample_rate::Float64=0.5)
        new(
            zeros(n_features),
            learning_rate,
            regularization,
            zeros(n_features),
            zeros(n_features),
            0,
            Float64[],
            history_decay,
            min_training_sample_rate
        )
    end
end

"""
    extract_score_features(scores::Dict{Int,SubproblemScore}) -> Vector{Float64}

Extract statistics from subproblem scores (4 features).

Returns: [min_score, max_score, avg_score, std_score]
"""
function extract_score_features(scores::Dict{Int,SubproblemScore})::Vector{Float64}
    if isempty(scores)
        return [0.0, 0.0, 0.0, 0.0]
    end
    
    score_values = [s.scaled_score for s in values(scores)]
    
    return [
        minimum(score_values),  # min
        maximum(score_values),  # max
        mean(score_values),     # avg
        std(score_values)       # std
    ]
end

"""
    extract_utilization_features(network::SNDlibNetwork) -> Vector{Float64}

Extract link utilization statistics (4 features).

Utilization = preinstalled_capacity / total_capacity for each link.

Returns: [min_util, max_util, avg_util, std_util]
"""
function extract_utilization_features(network::SNDlibNetwork)::Vector{Float64}
    links = network.network_structure.links
    
    if isempty(links)
        return [0.0, 0.0, 0.0, 0.0]
    end
    
    utilizations = Float64[]
    for link in values(links)  # links is a Dict, iterate over values
        # additional_modules is a Vector of (capacity, cost) tuples
        if !isempty(link.additional_modules)
            total_capacity = maximum(m[1] for m in link.additional_modules)  # m[1] is capacity
            preinstalled = isnothing(link.preinstalled_capacity) ? 0.0 : link.preinstalled_capacity
            if total_capacity > 0
                util = preinstalled / total_capacity
                push!(utilizations, util)
            else
                push!(utilizations, 0.0)
            end
        else
            push!(utilizations, 0.0)
        end
    end
    
    return [
        minimum(utilizations),  # min
        maximum(utilizations),  # max
        mean(utilizations),     # avg
        std(utilizations)       # std
    ]
end

"""
    extract_full_features(network::SNDlibNetwork, scores::Dict{Int,SubproblemScore}) -> Vector{Float64}

Extract complete feature vector for proportion prediction (8 features).

Features are unpacked explicitly for visibility:
- [1]: min_score
- [2]: max_score  
- [3]: avg_score
- [4]: std_score
- [5]: min_utilization
- [6]: max_utilization
- [7]: avg_utilization
- [8]: std_utilization

Returns: Vector of 8 features (4 score stats + 4 utilization stats)
"""
function extract_full_features(network::SNDlibNetwork, 
                              scores::Dict{Int,SubproblemScore})::Vector{Float64}
    # Extract score features (4)
    score_features = extract_score_features(scores)
    min_score = score_features[1]
    max_score = score_features[2]
    avg_score = score_features[3]
    std_score = score_features[4]
    
    # Extract utilization features (4)
    util_features = extract_utilization_features(network)
    min_util = util_features[1]
    max_util = util_features[2]
    avg_util = util_features[3]
    std_util = util_features[4]
    
    # Assemble full feature vector (unpacked for visibility)
    return [
        min_score,      # [1]
        max_score,      # [2]
        avg_score,      # [3]
        std_score,      # [4]
        min_util,       # [5]
        max_util,       # [6]
        avg_util,       # [7]
        std_util        # [8]
    ]
end

# Backward compatibility wrapper for old function signature (deprecated)
function extract_full_features(network::SNDlibNetwork, iteration::Int, 
                              total_cuts::Int, history::Vector{Float64})::Vector{Float64}
    # Old signature called from outside callback - just use dummy scores
    scores = Dict{Int,SubproblemScore}()
    return extract_full_features(network, scores)
end

"""
    normalize_features!(predictor::ProportionPredictor, features::Vector{Float64}) -> Nothing

Normalize features using online mean and standard deviation (Welford's algorithm).

Updates running statistics and normalizes features in-place to zero mean, unit variance.

Formula:
    normalized[i] = (features[i] - mean[i]) / std[i]

Welford's online algorithm:
    delta = x - mean
    mean_new = mean + delta / n
    M2_new = M2 + delta * (x - mean_new)
    variance = M2 / n
"""
function normalize_features!(predictor::ProportionPredictor, 
                             features::Vector{Float64})::Nothing
    n = predictor.n_samples + 1
    
    for i in 1:length(features)
        # Welford's online algorithm for mean and variance
        delta = features[i] - predictor.feature_means[i]
        predictor.feature_means[i] += delta / n
        delta2 = features[i] - predictor.feature_means[i]
        predictor.feature_m2[i] += delta * delta2
        
        # Normalize (avoid division by zero)
        if predictor.n_samples > 0
            variance = predictor.feature_m2[i] / predictor.n_samples
            std_dev = sqrt(variance)
            if std_dev > 1e-10
                features[i] = (features[i] - predictor.feature_means[i]) / std_dev
            else
                features[i] = 0.0
            end
        end
    end
    
    return nothing
end

"""
    predict_proportion(predictor::ProportionPredictor, features::Vector{Float64}) -> Float64

Predict the proportion of subproblems that will yield cuts.

Uses sigmoid activation: σ(w^T x) where σ(z) = 1 / (1 + exp(-z))

Returns value in [0, 1] representing predicted proportion.
"""
function predict_proportion(predictor::ProportionPredictor, 
                           features::Vector{Float64})::Float64
    # Normalize features (modifies in-place but we make a copy first)
    features_copy = copy(features)
    normalize_features!(predictor, features_copy)
    
    # Linear combination: z = w^T x
    z = dot(predictor.weights, features_copy)
    
    # Sigmoid activation: σ(z) = 1 / (1 + exp(-z))
    # Use sigmoid from subproblem_scoring_ml.jl
    return sigmoid(z)
end

"""
    train_proportion_predictor!(predictor::ProportionPredictor, features::Vector{Float64}, 
                                actual_proportion::Float64) -> Nothing

Train the predictor using online gradient descent.

Updates weights based on mean squared error loss with L2 regularization:
    L = (y_pred - y_actual)^2 + λ||w||^2
    ∂L/∂w = 2(y_pred - y_actual) * σ'(z) * x + 2λw

where σ'(z) = σ(z) * (1 - σ(z)) is the sigmoid derivative.

Weight update:
    w_new = w_old - learning_rate * ∂L/∂w
"""
function train_proportion_predictor!(predictor::ProportionPredictor, 
                                    features::Vector{Float64},
                                    actual_proportion::Float64)::Nothing
    # Normalize features
    features_copy = copy(features)
    normalize_features!(predictor, features_copy)
    
    # Forward pass
    z = dot(predictor.weights, features_copy)
    predicted = sigmoid(z)
    
    # Gradient computation
    error = predicted - actual_proportion
    sigmoid_derivative = predicted * (1.0 - predicted)
    
    # Gradient: ∂L/∂w = 2 * error * σ'(z) * x + 2λw
    gradient = 2.0 * error * sigmoid_derivative * features_copy + 
               2.0 * predictor.regularization * predictor.weights
    
    # Update weights: w = w - learning_rate * gradient
    predictor.weights -= predictor.learning_rate * gradient
    
    # Update sample count
    predictor.n_samples += 1
    
    return nothing
end

"""
    update_exponential_average!(history::Vector{Float64}, new_value::Float64, 
                                decay::Float64) -> Nothing

Update exponentially weighted average with new observation.

If history is empty, initialize with new_value.
Otherwise, apply: new_avg = decay * old_avg + (1 - decay) * new_value

The history vector is kept at length 1 (only stores current exponential average).
"""
function update_exponential_average!(history::Vector{Float64}, new_value::Float64, 
                                    decay::Float64)::Nothing
    if isempty(history)
        push!(history, new_value)
    else
        history[1] = decay * history[1] + (1.0 - decay) * new_value
    end
    return nothing
end

"""
    print_ml_selection_weights(predictor::ProportionPredictor) -> Nothing

Print the current ML selection model weights in a formatted table.

Similar to scoring weight display, shows which features are most influential.
"""
function print_ml_selection_weights(predictor::ProportionPredictor)::Nothing
    println()
    println("╔═════════════════════════════════════════════════════════════════════════╗")
    println("║                 ML Selection Model Weights (8 Features)                 ║")
    println("╠═════════════════════════════════════════════════╦═══════════════════════╣")
    println("║                                                 ║ -1.0     0       +1.0 ║")
    
    feature_names = [
        "Min Score",
        "Max Score",
        "Avg Score",
        "Std Score",
        "Min Utilization",
        "Max Utilization",
        "Avg Utilization",
        "Std Utilization"
    ]
    
    for (i, (name, weight)) in enumerate(zip(feature_names, predictor.weights))
        # Create visual bar: -1.0 to +1.0, each 0.1 = 1 character
        # Total bar width: 20 characters (10 left, 10 right)
        clamped_weight = max(-1.0, min(1.0, weight))
        
        if clamped_weight >= 0
            # Positive weight: bar extends right from center
            left_fill = 10
            right_fill = round(Int, clamped_weight * 10)
            bar = "     " * "║" * " " ^ left_fill * "│" * "█" ^ right_fill * " " ^ (10 - right_fill)
        else
            # Negative weight: bar extends left from center
            left_fill = round(Int, (1.0 + clamped_weight) * 10)
            right_fill = 10
            bar = "     " * "║" * " " ^ left_fill * "█" ^ (10 - left_fill) * "│" * " " ^ right_fill
        end
        
        @printf("║  %2d. %-27s %8.4f  %s  ║\n", i, name, weight, bar)
    end
    
    println("╠═════════════════════════════════════════════════════════════════════════╣")
    @printf("║  Training samples: %-55d  ║\n", predictor.n_samples)
    @printf("║  Learning rate: %-58.4f  ║\n", predictor.learning_rate)
    @printf("║  Regularization: %-57.4f  ║\n", predictor.regularization)
    @printf("║  Min training rate: %-54.1f%%  ║\n", predictor.min_training_sample_rate * 100)
    println("╚═════════════════════════════════════════════════════════════════════════╝")
    println()
    
    return nothing
end
