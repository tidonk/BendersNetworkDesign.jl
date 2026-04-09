#!/usr/bin/env python3
"""
Performance profile plotting for Benders decomposition experiments.

Reads compiled CSV files from check/results/compiled/*.csv and generates
performance profile plots showing solving time and optimality gap.
"""

import os
import sys
import glob
import argparse
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns

# Configure matplotlib for LaTeX rendering
plt.rcParams['text.usetex'] = True
plt.rcParams['font.family'] = 'serif'
plt.rcParams['font.size'] = 11

# Color palettes and line styles
black3palette = ['#000000', '#555555', '#AAAAAA']
linestyles3 = ['solid', 'dashed', 'dotted']

# Algorithm name mapping for display
algo_names = {
    'benders_standard': 'Standard Benders',
    'benders_ML-0.5-5C-20S-5R': 'ML-0.5',
    'benders_ML-P0.3-20S-UR': 'ML-P0.3',
    'benders_ML-P0.7-20S-5R': 'ML-P0.7',
    'benders_ML-PA-20S-UR': 'ML-PA',
    'oracle_read' : 'Oracle',
}


def read_compiled_csv(filepath):
    """
    Read a compiled CSV file from check/results/compiled/*.csv.
    
    Parameters:
    -----------
    filepath : str
        Path to the CSV file
    
    Returns:
    --------
    df : pd.DataFrame
        DataFrame with columns: instance, settings, total_time, gap, solved
    """
    df = pd.read_csv(filepath)
    
    # Extract settings name from settings_file column (remove .toml extension)
    if 'settings_file' in df.columns:
        df['settings'] = df['settings_file'].str.replace('.toml', '')
    
    # Compute gap: (objective_value - bound) / max(|objective_value|, 1.0)
    if 'objective_value' in df.columns and 'bound' in df.columns:
        df['gap'] = (df['objective_value'] - df['bound']) / df[['objective_value']].abs().clip(lower=1.0).iloc[:, 0]
        df['gap'] = df['gap'].abs()  # Absolute gap
    else:
        df['gap'] = float('inf')
    
    # Determine solved status (OPTIMAL or gap < 1e-6)
    if 'status' in df.columns:
        df['solved'] = (df['status'] == 'OPTIMAL') | (df['gap'] < 1e-6)
    else:
        df['solved'] = df['gap'] < 1e-6
    
    return df


def read_all_compiled_csvs(directory):
    """
    Read all compiled CSV files from a directory.
    
    Parameters:
    -----------
    directory : str
        Path to directory containing compiled CSV files
    
    Returns:
    --------
    df : pd.DataFrame
        Combined DataFrame from all CSV files
    """
    csv_files = glob.glob(os.path.join(directory, '*.csv'))
    
    if not csv_files:
        raise ValueError(f"No CSV files found in {directory}")
    
    print(f"Found {len(csv_files)} CSV files in {directory}")
    
    dfs = []
    for csv_file in csv_files:
        try:
            df = read_compiled_csv(csv_file)
            dfs.append(df)
        except Exception as e:
            print(f"Warning: Failed to read {csv_file}: {e}")
    
    if not dfs:
        raise ValueError(f"Failed to read any CSV files from {directory}")
    
    combined_df = pd.concat(dfs, ignore_index=True)
    print(f"Loaded {len(combined_df)} rows from {len(dfs)} files")
    
    # some instance-settings pairs may have multiple lines - keep the first only
    combined_df = combined_df.drop_duplicates(subset=['instance', 'settings'], keep='first')

    # Write combined CSV (with relevant cols only) into results/compiled
    summary_csv_path = os.path.join(directory, 'performance_profile_data.csv')
    combined_df[['instance', 'settings', 'total_time', 'gap', 'solved']].to_csv(summary_csv_path, index=False)
    print(f"Wrote performance profile data to {summary_csv_path}")

    return combined_df


def performance_profile_with_gaps(df, time_col='total_time', gap_col='gap', 
                                   solved_col='solved', solver_col='settings',
                                   max_time=3600, figsize=(14, 6), palette=None,
                                   solver_order=None, linestyles=None, log_scale_time=False,
                                   min_time=0, show_gaps=True):
    """
    Create a performance profile plot with two parts:
    1. Left part: Percentage of instances solved within given time (0 to max_time)
    2. Right part: Percentage of instances with gap at most given value
    
    Parameters:
    -----------
    df : pd.DataFrame
        DataFrame with columns for solver (i.e., settings), instance, time, gap, and solved status
    time_col : str
        Column name for solving time
    gap_col : str
        Column name for optimality gap
    solved_col : str
        Column name for solved status (boolean)
    solver_col : str
        Column name for solver/settings identifier
    max_time : float
        Maximum time to show on x-axis (default: 3600s)
    figsize : tuple
        Figure size (width, height)
    palette : list or None
        Color palette for solvers (one color per solver)
    solver_order : list or None
        List of solver names in the desired display order. If None, uses sorted order.
    linestyles : list or None
        List of line styles for each solver (e.g., ['solid', 'dashed', 'dotted', 'dashdot']).
        If None, uses 'solid' for all solvers. Should match length of solver_order.
    
    Returns:
    --------
    fig, ax : matplotlib figure and axis objects
    """
    # map solver order and solver names 
    solver_order = [algo_names.get(solver, solver) for solver in solver_order] if solver_order else None
    df[solver_col] = df[solver_col].map(lambda s: algo_names.get(s, s))

    fig, ax = plt.subplots(figsize=figsize)
    
    # Determine solver order
    if solver_order is None:
        solvers = sorted(df[solver_col].unique())
    else:
        solvers = solver_order
    
    # Set up colors
    if palette is None:
        if len(solvers) == 3:
            colors = black3palette
        else:
            colors = sns.color_palette(n_colors=len(solvers))
    else:
        colors = palette
    
    # Set up line styles
    if linestyles is None:
        if len(solvers) == 3:
            linestyles = linestyles3
        else:
            linestyles = ['solid'] * len(solvers)
    elif len(linestyles) < len(solvers):
        # Extend with 'solid' if not enough styles provided
        linestyles = list(linestyles) + ['solid'] * (len(solvers) - len(linestyles))
        
    # set max time to minimum of max_time and the maximum time in the data
    max_time = min(max_time, df[time_col].max())
    
    # Define log scale parameters
    min_log_val = max(0.1, min_time)
    
    def transform_time(t):
        if not log_scale_time:
            return t
        if t <= min_log_val:
            return 0
        log_t = np.log10(t)
        log_min = np.log10(min_log_val)
        log_max = np.log10(max_time)
        return (log_t - log_min) / (log_max - log_min) * max_time
    
    # Find global min/max gap across all unsolved instances (for consistent x-axis)
    # Exclude infinite gaps
    all_unsolved = df[df[solved_col] == False]
    if len(all_unsolved) > 0:
        all_unsolved_finite = all_unsolved[~np.isinf(all_unsolved[gap_col])]
        if len(all_unsolved_finite) > 0:
            global_min_gap = all_unsolved_finite[gap_col].min()
            global_max_gap = all_unsolved_finite[gap_col].max()
        else:
            global_min_gap = 0
            global_max_gap = 1
    else:
        global_min_gap = 0
        global_max_gap = 1
    
    gap_range = global_max_gap - global_min_gap if global_max_gap > global_min_gap else 1
    
    for idx, solver in enumerate(solvers):
        solver_df = df[df[solver_col] == solver].copy()
        n_instances = len(solver_df)
        
        if n_instances == 0:
            continue
        
        # Part 1: Time-based performance (0 to max_time)
        solved_df = solver_df[solver_df[solved_col] == True].copy()
        
        if len(solved_df) > 0:
            times = sorted(solved_df[time_col].values)
            # Clamp times to max_time
            times = [min(t, max_time) for t in times]
            
            # Create step function for cumulative percentage
            time_x = [min_time]
            # Count instances solved <= min_time
            current_solved = sum(1 for t in times if t <= min_time)
            time_y = [current_solved / n_instances * 100]
            
            for i, t in enumerate(times):
                if t <= min_time:
                    continue
                time_x.append(t)
                time_y.append((i+1)/n_instances * 100)
            
            # Extend to max_time
            if time_x[-1] < max_time:
                time_x.append(max_time)
                time_y.append(time_y[-1])
        else:
            time_x = [min_time, max_time]
            time_y = [0, 0]
        
        # Plot time part
        transformed_time_x = [transform_time(t) for t in time_x]
        ax.plot(transformed_time_x, time_y, label=solver, color=colors[idx], linewidth=2, 
                linestyle=linestyles[idx])
        
        if not show_gaps:
            continue

        # Part 2: Gap-based performance
        unsolved_df = solver_df[solver_df[solved_col] == False].copy()
        print(unsolved_df)
        
        if len(unsolved_df) > 0:
            # Filter out infinite and NaN gaps - we only plot up to the largest finite gap
            unsolved_finite = unsolved_df[~np.isinf(unsolved_df[gap_col]) & ~np.isnan(unsolved_df[gap_col])].copy()
            
            if len(unsolved_finite) > 0:
                # Sort by gap (only finite gaps)
                unsolved_gaps = sorted(unsolved_finite[gap_col].values)
                
                n_solved = len(solved_df)
                
                # Build gap profile
                gap_x = [max_time]
                gap_y = [n_solved/n_instances * 100]
                
                for gap in unsolved_gaps:
                    # Map gap to x-position: max_time to 2*max_time
                    x_pos = max_time + (gap - global_min_gap) / gap_range * max_time
                    
                    # Count how many instances have been "solved" at this gap
                    # Only count unsolved instances with finite gaps
                    n_with_gap_at_most = n_solved + len(unsolved_finite[unsolved_finite[gap_col] <= gap])
                    
                    gap_x.append(x_pos)
                    gap_y.append(n_with_gap_at_most/n_instances * 100)
                
                # Extend line horizontally to the end of the plot
                gap_x.append(2*max_time)
                gap_y.append(gap_y[-1])  # Keep the same percentage
                
                # Plot gap part with same line style as time part
                ax.plot(gap_x, gap_y, color=colors[idx], linewidth=2, 
                        linestyle=linestyles[idx])
            # If all unsolved instances have infinite gaps, don't plot gap part
        elif len(solved_df) == n_instances:
            # All instances solved - extend line at 100%
            gap_x = [max_time, 2*max_time]
            gap_y = [100, 100]
            ax.plot(gap_x, gap_y, color=colors[idx], linewidth=2, 
                    linestyle=linestyles[idx])
    
    # Styling
    if show_gaps:
        ax.set_xlabel('Time / Gap')
        ax.set_title('Performance Profile: Solving Time and Optimality Gap', fontsize=14, fontweight='bold')
    else:
        ax.set_xlabel('Time')
        ax.set_title('Performance Profile: Solving Time', fontsize=14, fontweight='bold')
        
    ax.set_ylabel('Percentage of instances')
    # ax.grid(True, alpha=0.3, linestyle=':', linewidth=0.7)
    ax.legend(loc='lower right')#, fontsize=11, framealpha=0.9)
    ax.set_ylim(0, 100)
    
    if log_scale_time:
        if show_gaps:
            ax.set_xlim(0, 2*max_time)
        else:
            ax.set_xlim(0, max_time)
    else:
        if show_gaps:
            ax.set_xlim(min_time, 2*max_time)
        else:
            ax.set_xlim(min_time, max_time)
    
    # Add vertical line to separate time and gap sections
    if show_gaps:
        ax.axvline(x=max_time, color='gray', linestyle=':', linewidth=2, alpha=0.5, label='_separator')
    
    # Create custom x-axis labels
    # For time part: show regular time values
    if log_scale_time:
        # Generate log ticks: 0.1, 1, 10, 100, 1000...
        min_pow = int(np.floor(np.log10(min_log_val)))
        max_pow = int(np.ceil(np.log10(max_time)))
        time_ticks_vals = [10**i for i in range(min_pow, max_pow + 1)]
        
        # Filter ticks within range
        valid_ticks = [t for t in time_ticks_vals if t >= min_log_val and t <= max_time]
        
        # Always include max_time for the boundary if not close to existing tick
        if not any(np.isclose(t, max_time) for t in valid_ticks):
             valid_ticks.append(max_time)
             
        time_ticks = [transform_time(t) for t in valid_ticks]
        time_labels = [rf'{t:g}\thinspace s' for t in valid_ticks]
    else:
        time_ticks = [min_time, min_time + (max_time-min_time)/4, min_time + (max_time-min_time)/2, 
                      min_time + 3*(max_time-min_time)/4, max_time]
        time_labels = [rf'{int(t)}\thinspace s' for t in time_ticks]
    
    if show_gaps:
        # For gap part: show gap values
        gap_ticks = [max_time + i*max_time/4 for i in range(5)]
        gap_values = [global_min_gap + (t - max_time)/max_time * gap_range for t in gap_ticks]
        gap_labels = [rf'{100 *v:.1f}\thinspace\%' for v in gap_values]
        
        ax.set_xticks(time_ticks + gap_ticks)
        ax.set_xticklabels(time_labels + gap_labels, rotation=0)
        
        # # Add section labels
        # ax.text(max_time/2, -12, 'Solving Time', ha='center', fontsize=11, 
        #         fontweight='bold', transform=ax.get_xaxis_transform())
        # ax.text(max_time*1.5, -12, 'Optimality Gap', ha='center', fontsize=11,
        #         fontweight='bold', transform=ax.get_xaxis_transform())
    else:
        ax.set_xticks(time_ticks)
        ax.set_xticklabels(time_labels, rotation=0)
    
    plt.legend(frameon=False)
    return fig, ax


def main():
    """
    Main function to read compiled CSVs and generate performance profiles.
    """
    parser = argparse.ArgumentParser(
        description='Generate performance profile plots from compiled CSV results'
    )
    parser.add_argument(
        '--input-dir',
        default='results/compiled',
        help='Directory containing compiled CSV files (default: results/compiled)'
    )
    parser.add_argument(
        '--output',
        default='check/plots/performance_profile.pdf',
        help='Output file path for the plot (default: check/plots/performance_profile.pdf)'
    )
    parser.add_argument(
        '--max-time',
        type=float,
        default=3600,
        help='Maximum time to show on x-axis in seconds (default: 3600)'
    )
    parser.add_argument(
        '--log-scale',
        action='store_true',
        help='Use logarithmic scale for time axis'
    )
    parser.add_argument(
        '--no-gaps',
        action='store_true',
        help='Hide gap portion of the plot (only show time)'
    )
    parser.add_argument(
        '--figsize',
        nargs=2,
        type=float,
        default=[14, 6],
        help='Figure size as width height (default: 14 6)'
    )
    parser.add_argument(
        '--solver-order',
        nargs='+',
        help='Order of solvers in legend (space-separated)'
    )
    
    args = parser.parse_args()
    
    # Read all compiled CSV files
    print(f"Reading CSV files from {args.input_dir}...")
    df = read_all_compiled_csvs(args.input_dir)
    
    # Filter out setting ML-PA
    df = df[df['settings'] != 'benders_ML-PA-20S-UR']
    df = df[df['settings'] != 'oracle_write']

    # Write combined CSV (with relevant cols only) into results/compiled
    summary_csv_path = os.path.join(args.input_dir, 'performance_profile_data.csv')
    df[['instance', 'settings', 'total_time', 'gap', 'solved']].to_csv(summary_csv_path, index=False)
    print(f"Wrote performance profile data to {summary_csv_path}")

    # Print summary statistics
    print(f"\nDataset summary:")
    print(f"  Total instances: {df['instance'].nunique()}")
    print(f"  Total settings: {df['settings'].nunique()}")
    print(f"  Settings: {sorted(df['settings'].unique())}")
    print(f"  Solved instances: {df['solved'].sum()} / {len(df)} ({100*df['solved'].sum()/len(df):.1f}%)")
    
    # Write a CSV of all the data, but only with the relevant columns, into results/compiled
    summary_csv_path = os.path.join(args.input_dir, 'performance_profile_data.csv')
    df[['instance', 'settings', 'total_time', 'gap', 'solved']].to_csv(summary_csv_path, index=False)
    print(f"Wrote performance profile data to {summary_csv_path}")

    # Generate performance profile
    print(f"\nGenerating performance profile...")
    fig, ax = performance_profile_with_gaps(
        df,
        time_col='total_time',
        gap_col='gap',
        solved_col='solved',
        solver_col='settings',
        max_time=args.max_time,
        figsize=tuple(args.figsize),
        log_scale_time=args.log_scale,
        show_gaps=not args.no_gaps,
        solver_order=args.solver_order
    )
    
    # Create dir
    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    # Save figure
    plt.tight_layout()
    plt.savefig(args.output, dpi=300, bbox_inches='tight')
    print(f"Saved plot to {args.output}")
    
    # Show plot (if in interactive mode)
    # plt.show()


if __name__ == '__main__':
    main()