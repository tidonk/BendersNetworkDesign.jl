# Documentation for BendersNetworkDesign.jl

This directory contains the documentation for BendersNetworkDesign.jl using Documenter.jl.

## Building the Documentation

### Prerequisites

```bash
cd docs
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Build Locally

```bash
cd docs
julia --project=. make.jl
```

The generated HTML documentation will be in `docs/build/`.

### Preview Locally

```bash
cd docs/build
python3 -m http.server 8000
# Open browser to http://localhost:8000
```

## Structure

```
docs/
├── Project.toml           # Documentation dependencies
├── make.jl               # Build script
├── src/                  # Documentation source
│   ├── index.md         # Home page
│   ├── getting_started.md
│   ├── formulation.md
│   ├── configuration.md
│   └── api/             # API reference
│       ├── models.md
│       ├── selection.md
│       └── io.md
└── build/               # Generated HTML (git-ignored)
```

## Deploying Documentation

To deploy to GitHub Pages:

1. Update the repository URL in `make.jl`
2. Push to GitHub
3. Run: `julia --project=. make.jl` with CI=true environment variable

The documentation will be deployed to `https://yourusername.github.io/BendersNetworkDesign.jl/`.
