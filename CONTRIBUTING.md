# Contributing to BendersNetworkDesign.jl

We welcome contributions to BendersNetworkDesign.jl! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/your-username/BendersNetworkDesign.jl.git
   cd BendersNetworkDesign.jl
   ```
3. Set up the development environment:
   ```bash
   julia --project=. -e 'using Pkg; Pkg.instantiate()'
   ```

## Development Workflow

### Making Changes

1. Create a new branch for your feature or bugfix:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes, ensuring:
   - Code follows Julia style conventions
   - New functionality includes appropriate tests
   - Documentation is updated as needed

3. Run the test suite to ensure all tests pass:
   ```bash
   julia --project=. test/runtests.jl
   ```

4. Commit your changes with clear, descriptive commit messages:
   ```bash
   git commit -m "Add feature: brief description"
   ```

### Code Style

- Follow standard Julia naming conventions:
  - `snake_case` for functions and variables
  - `CamelCase` for types and modules
  - Constants in `UPPER_CASE`
- Use 4 spaces for indentation
- Keep lines under 100 characters when practical
- Add docstrings for exported functions

### Testing

- Add tests for new functionality in the `test/` directory
- Tests should be self-contained and reproducible
- Use descriptive test names that explain what is being tested
- Ensure all existing tests continue to pass

### Documentation

- Update relevant documentation in `docs/` for significant changes
- Add docstrings to new exported functions
- Update `CHANGELOG.md` with a brief description of your changes

## Submitting Changes

1. Push your changes to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

2. Create a Pull Request (PR) on GitHub:
   - Provide a clear description of the changes
   - Reference any related issues
   - Ensure the CI pipeline passes

3. Wait for review:
   - Address any feedback from reviewers
   - Make requested changes in new commits
   - Once approved, your changes will be merged

## Reporting Issues

When reporting issues, please include:

- Julia version and platform (OS)
- Minimal reproducible example
- Expected vs. actual behavior
- Relevant error messages or logs

## Questions?

For questions or discussions, please:
- Open an issue on GitHub
- Check the documentation: https://tidonk.github.io/BendersNetworkDesign.jl/

Thank you for contributing to BendersNetworkDesign.jl!
