# Problem Formulation

## Two-Stage Stochastic Network Design

BendersNetworkDesign solves a two-stage stochastic network design problem with modular capacities and link failure scenarios.

## Mathematical Formulation

### Sets

- ``N``: set of nodes
- ``L``: set of links
- ``A``: set of arcs (bidirectional: forward and backward for each link)
- ``D``: set of demands
- ``S``: set of scenarios (link failure combinations)
- ``M_l``: set of capacity modules available for link ``l``

### First-Stage Variables

- ``y_{l,m} \in \mathbb{Z}_+``: number of modules of type ``m`` installed on link ``l``

### Second-Stage Variables (per scenario ``s``)

- ``f_{s,d,a} \geq 0``: flow of demand ``d`` on arc ``a`` in scenario ``s``

### Parameters

- ``\text{cap}_{l,m}``: capacity of module ``m`` for link ``l``
- ``\text{cost}_{l,m}``: installation cost of module ``m`` for link ``l``
- ``\text{demand}_d``: traffic volume for demand ``d``
- ``\pi_s``: probability of scenario ``s``

### Objective

```math
\min \sum_{l \in L} \sum_{m \in M_l} \text{cost}_{l,m} \cdot y_{l,m}
```

Subject to module installation costs only (second-stage is feasibility problem).

### First-Stage Constraints

**Preinstalled capacity limits:**
```math
y_{l,0} \leq 1 \quad \forall l \in L \text{ with preinstalled capacity}
```

**Base case flow conservation:**
```math
\sum_{a \in \delta^+(n)} f_{\text{base},d,a} - \sum_{a \in \delta^-(n)} f_{\text{base},d,a} = \begin{cases}
\text{demand}_d & \text{if } n = \text{source}_d \\
-\text{demand}_d & \text{if } n = \text{target}_d \\
0 & \text{otherwise}
\end{cases}
```

**Base case capacity constraints:**
```math
\sum_{d \in D} (f_{\text{base},d,(l,\text{fwd})} + f_{\text{base},d,(l,\text{bwd})}) \leq \sum_{m \in M_l} \text{cap}_{l,m} \cdot y_{l,m} \quad \forall l \in L
```

### Second-Stage Constraints (Benders Subproblems)

For each scenario ``s \in S``:

**Flow conservation:**
```math
\sum_{a \in \delta^+(n)} f_{s,d,a} - \sum_{a \in \delta^-(n)} f_{s,d,a} = \begin{cases}
\text{demand}_d & \text{if } n = \text{source}_d \\
-\text{demand}_d & \text{if } n = \text{target}_d \\
0 & \text{otherwise}
\end{cases}
```

**Capacity constraints (with failures):**
```math
\sum_{d \in D} (f_{s,d,(l,\text{fwd})} + f_{s,d,(l,\text{bwd})}) \leq \sum_{m \in M_l} \text{cap}_{l,m} \cdot y_{l,m} \quad \forall l \in L \setminus F_s
```

where ``F_s`` is the set of failed links in scenario ``s`` (capacity = 0).

## Benders Decomposition

### Master Problem

Includes first-stage variables ``y`` and recourse variable ``\theta``:

```math
\min \sum_{l \in L} \sum_{m \in M_l} \text{cost}_{l,m} \cdot y_{l,m} + \theta
```

### Subproblems

For each scenario ``s``, given fixed ``\bar{y}``, solve:

```math
\min_{f_{s,d,a}} \quad 0
```

Subject to flow conservation and capacity constraints with ``y = \bar{y}``.

### Benders Cuts

When subproblem is **infeasible** (Farkas dual), add feasibility cut:

```math
\sum_{l \in L \setminus F_s} \sum_{m \in M_l} \left(\sum_{d \in D} \mu^{\text{cap}}_{s,l,d} \cdot \text{cap}_{l,m}\right) \cdot y_{l,m} \geq \sum_{d \in D} \sum_{n \in N} \mu^{\text{flow}}_{s,d,n} \cdot b_{d,n}
```

where ``\mu^{\text{cap}}`` and ``\mu^{\text{flow}}`` are Farkas duals.

## Implementation

The package uses JuMP's lazy constraint callback mechanism:

1. Solve master problem with current cuts
2. Extract ``\bar{y}`` solution
3. Order scenarios by priority score
4. Solve subproblems until stopping criteria met
5. Add violated cuts to master
6. Repeat until convergence

See [API Reference](api/models.md) for implementation details.
