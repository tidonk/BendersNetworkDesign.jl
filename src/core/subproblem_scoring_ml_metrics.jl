"""
    subproblem_scoring_ml_metrics.jl

Metrics printing and analysis functions for ML-based subproblem scoring.
"""

using Printf

"""
    print_ml_metrics_summary(model::OnlineLogisticRegression)

Print comprehensive ML performance metrics after solving.

Displays:
- Overall accuracy, precision, recall, F1-score
- Prediction distribution by confidence bins
- True positive/negative rates
"""
function print_ml_metrics_summary(model::OnlineLogisticRegression)::Nothing
    metrics = model.metrics
    
    if metrics.total_predictions == 0
        println("\n╔════════════════════════════════════════════════╗")
        println("║     ML Model Performance Summary               ║")
        println("╠════════════════════════════════════════════════╣")
        println("║  No predictions made (model not trained)       ║")
        println("╚════════════════════════════════════════════════╝")
        return nothing
    end
    
    # Compute metrics
    total = metrics.total_predictions
    tp = metrics.true_positives
    tn = metrics.true_negatives
    fp = metrics.false_positives
    fn = metrics.false_negatives
    
    accuracy = (tp + tn) / total
    precision = tp + fp > 0 ? tp / (tp + fp) : 0.0
    recall = tp + fn > 0 ? tp / (tp + fn) : 0.0
    f1_score = precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0.0
    
    # Confidence bins
    bins = [(0.0, 0.1), (0.1, 0.2), (0.2, 0.3), (0.3, 0.4), (0.4, 0.5),
            (0.5, 0.6), (0.6, 0.7), (0.7, 0.8), (0.8, 0.9), (0.9, 1.0)]
    bin_counts = Dict(bin => 0 for bin in bins)
    bin_cuts = Dict(bin => 0 for bin in bins)
    bin_no_cuts = Dict(bin => 0 for bin in bins)
    
    for (pred, actual, correct) in metrics.prediction_history
        for bin in bins
            if bin[1] <= pred < bin[2] || (bin[2] == 1.0 && pred == 1.0)
                bin_counts[bin] += 1
                if actual  # actual indicates whether a cut was generated
                    bin_cuts[bin] += 1
                else
                    bin_no_cuts[bin] += 1
                end
                break
            end
        end
    end
    
    # Print summary
    println("\n╔══════════════════════════════════════════════════════╗")
    println("║          ML Model Performance Summary                ║")
    println("╠══════════════════════════════════════════════════════╣")
    @printf("║  Total Predictions:      %-6d                      ║\n", total)
    @printf("║  Training Updates:       %-6d                      ║\n", model.n_updates)
    println("╠══════════════════════════════════════════════════════╣")
    @printf("║  Accuracy:               %6.2f%%                     ║\n", accuracy * 100)
    @printf("║  Precision:              %6.2f%%                     ║\n", precision * 100)
    @printf("║  Recall:                 %6.2f%%                     ║\n", recall * 100)
    @printf("║  F1-Score:               %6.2f%%                     ║\n", f1_score * 100)
    println("╠══════════════════════════════════════════════════════╣")
    @printf("║  True Positives:         %-6d                      ║\n", tp)
    @printf("║  True Negatives:         %-6d                      ║\n", tn)
    @printf("║  False Positives:        %-6d                      ║\n", fp)
    @printf("║  False Negatives:        %-6d                      ║\n", fn)
    println("╚══════════════════════════════════════════════════════╝")
    
    # Print confidence bins
    println("\n╔════════════════════════════════════════════════════════════════════╗")
    println("║          Predictions by Confidence (Cut Generation)                ║")
    println("╠═══════════╦══════════╦═══════════╦══════════════╦══════════════════╣")
    println("║  Bin      ║  Count   ║  Cut      ║  No Cut      ║  Cuts (%)        ║")
    println("╠═══════════╬══════════╬═══════════╬══════════════╬══════════════════╣")
    
    for bin in bins
        count = bin_counts[bin]
        cuts = bin_cuts[bin]
        no_cuts = bin_no_cuts[bin]
        cuts_pct = count > 0 ? 100.0 * cuts / count : 0.0
        @printf("║  %.1f-%.1f  ║  %6d  ║  %7d  ║  %10d  ║  %13.1f%%  ║\n", 
                bin[1], bin[2], count, cuts, no_cuts, cuts_pct)
    end
    
    println("╚═══════════╩══════════╩═══════════╩══════════════╩══════════════════╝")
    
    # Print model weights
    println("\n╔═════════════════════════════════════════════════════════════════════════╗")
    println("║                    Model Weights (10 Features)                          ║")
    println("╠═════════════════════════════════════════════════╦═══════════════════════╣")
    println("║                                                 ║ -1.0     0       +1.0 ║")
    
    feature_names = [
        "Failed Link Capacity",
        "Failed Link Flow",
        "Failed Link Utilization",
        "Failed Link Centrality",
        "Violation",
        "Reliability",
        "Reliability Filtered",
        "Total Share",
        "Stabilization"
    ]
    
    for (i, (name, weight)) in enumerate(zip(feature_names, model.weights))
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
    @printf("║  Bias: %-63.4f  ║\n", model.bias)
    println("╚═════════════════════════════════════════════════════════════════════════╝")
    
    return nothing
end

"""
    print_ml_metrics_summary(model::MultiRegressorML)

Print aggregated ML performance metrics for multi-regressor model.

Aggregates metrics across all scenario-specific regressors.
"""
function print_ml_metrics_summary(model::MultiRegressorML)::Nothing
    # Aggregate metrics across all regressors
    aggregated = aggregate_metrics(model)
    
    if aggregated.total_predictions == 0
        println("\n╔════════════════════════════════════════════════╗")
        println("║     ML Model Performance Summary               ║")
        println("╠════════════════════════════════════════════════╣")
        println("║  No predictions made (model not trained)       ║")
        println("╚════════════════════════════════════════════════╝")
        return nothing
    end
    
    # Compute metrics
    total = aggregated.total_predictions
    tp = aggregated.true_positives
    tn = aggregated.true_negatives
    fp = aggregated.false_positives
    fn = aggregated.false_negatives
    
    accuracy = (tp + tn) / total
    precision = tp + fp > 0 ? tp / (tp + fp) : 0.0
    recall = tp + fn > 0 ? tp / (tp + fn) : 0.0
    f1_score = precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0.0
    
    # Count trained regressors
    total_regressors = length(model.regressors)
    trained_regressors = sum(r.n_updates > 0 for r in values(model.regressors))
    total_updates = sum(r.n_updates for r in values(model.regressors))
    
    # Print summary
    println("\n╔══════════════════════════════════════════════════════╗")
    println("║     Multi-Regressor ML Performance Summary           ║")
    println("╠══════════════════════════════════════════════════════╣")
    @printf("║  Total Regressors:       %-6d                      ║\n", total_regressors)
    @printf("║  Trained Regressors:     %-6d                      ║\n", trained_regressors)
    @printf("║  Total Training Updates: %-6d                      ║\n", total_updates)
    @printf("║  Total Predictions:      %-6d                      ║\n", total)
    println("╠══════════════════════════════════════════════════════╣")
    @printf("║  Accuracy:               %6.2f%%                     ║\n", accuracy * 100)
    @printf("║  Precision:              %6.2f%%                     ║\n", precision * 100)
    @printf("║  Recall:                 %6.2f%%                     ║\n", recall * 100)
    @printf("║  F1-Score:               %6.2f%%                     ║\n", f1_score * 100)
    println("╠══════════════════════════════════════════════════════╣")
    @printf("║  True Positives:         %-6d                      ║\n", tp)
    @printf("║  True Negatives:         %-6d                      ║\n", tn)
    @printf("║  False Positives:        %-6d                      ║\n", fp)
    @printf("║  False Negatives:        %-6d                      ║\n", fn)
    println("╠══════════════════════════════════════════════════════╣")
    @printf("║  Features per regressor: %-6d                      ║\n", model.n_features)
    @printf("║  k-hop distance:         %-6d                      ║\n", model.khop_distance)
    println("╚══════════════════════════════════════════════════════╝")
    
    return nothing
end

export print_ml_metrics_summary
