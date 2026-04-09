# ML Models Directory

This directory stores trained machine learning models for subproblem scoring.

## File Naming Convention

Models are automatically named based on the instance being solved:
- Format: `trained_model_INSTANCENAME.jls`
- Example: `trained_model_abilene.jls` for the Abilene network

## Usage

### Training a Model

Set `model_write = true` in your settings file (e.g., `settings/test/benders_ML-train.toml`):

```toml
[BENDERS.ML]
    model_write = true
```

When you solve an instance with this setting, the trained model will be saved here automatically.

### Using a Trained Model

Set `model_read = true` in your settings file (e.g., `settings/test/benders_ML-0.5-20S_readML.toml`):

```toml
[BENDERS.ML]
    model_read = true
```

The solver will look for `trained_model_INSTANCENAME.jls` in this directory and load it if found.

## Model Format

Models are serialized using Julia's `Serialization` module and contain:
- Trained logistic regression weights and bias
- Feature normalization statistics (means and standard deviations)
- Training metadata (number of updates, learning rate, etc.)
