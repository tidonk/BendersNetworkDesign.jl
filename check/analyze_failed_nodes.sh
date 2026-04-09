#!/bin/bash

# Script to identify clustOR nodes that caused rsync errors
# Checks all .err files in check/logs for the specific error and extracts the node from corresponding .log file

LOGS_DIR="logs"

echo "Analyzing failed nodes from HTCondor logs..."
echo "=============================================="
echo ""

declare -A node_count
declare -A failed_nodes
declare -A all_nodes

# Iterate through all .err files
for err_file in "$LOGS_DIR"/*.err; do
    # Check if file exists (in case no .err files)
    [ -f "$err_file" ] || continue
    
    # Check first two lines for errors (line 1 is often "ls: cannot access")
    first_line=$(head -n1 "$err_file")
    second_line=$(sed -n '2p' "$err_file")
    
    error_type=""
    
    # Check for rsync juliaup error (usually on line 2)
    if echo "$second_line" | grep -q "rsync.*change_dir.*\.juliaup.*failed"; then
        error_type="rsync juliaup"
    # Check for ls: cannot access /home/donkiewicz/ (line 1)
    elif echo "$first_line" | grep -q "ls: cannot access '/home/donkiewicz/'"; then
        error_type="ls cannot access home"
    # Check for mkdir permission denied
    elif echo "$first_line" | grep -q "mkdir: cannot create directory '/local/tmp': Permission denied"; then
        error_type="mkdir permission denied"
    fi
    
    # Skip if no error detected
    [ -z "$error_type" ] && continue
    
    # Extract base name without extension
    base_name=$(basename "$err_file" .err)
    
    # Corresponding log file
    log_file="$LOGS_DIR/${base_name}.log"
    
    if [ -f "$log_file" ]; then
        # Extract last occurrence of alias=
        # Using grep to find all lines with alias=, then tail to get last one
        # Then extract the hostname using sed
        node=$(grep -o 'alias=[^&]*' "$log_file" | tail -n1 | sed 's/alias=//')
        
        if [ -n "$node" ]; then
            echo "Instance: $base_name"
            echo "  Node: $node"
            echo "  Error: $error_type"
            echo ""
            
            # Count occurrences
            node_count["$node"]=$((${node_count["$node"]:-0} + 1))
            failed_nodes["$node"]=1
        else
            echo "Instance: $base_name"
            echo "  Node: Could not extract from log file"
            echo "  Error: $error_type"
            echo ""
        fi
    else
        echo "Instance: $base_name"
        echo "  Node: Log file not found"
        echo "  Error: $error_type"
        echo ""
    fi
done

# Now collect all nodes that ran (successful or not)
echo ""
echo "=============================================="
echo "Collecting all nodes that executed jobs..."
echo "=============================================="

for log_file in "$LOGS_DIR"/*.log; do
    [ -f "$log_file" ] || continue
    
    node=$(grep -o 'alias=[^&]*' "$log_file" | tail -n1 | sed 's/alias=//')
    
    if [ -n "$node" ]; then
        all_nodes["$node"]=1
    fi
done

# Print summary
echo ""
echo "=============================================="
echo "Summary of problematic nodes:"
echo "=============================================="

if [ ${#node_count[@]} -eq 0 ]; then
    echo "No instances with errors found."
else
    # Sort by count (descending) and print
    for node in "${!node_count[@]}"; do
        echo "${node_count[$node]} failures: $node"
    done | sort -rn
fi

echo ""
echo "Total unique nodes with errors: ${#node_count[@]}"

echo ""
echo "=============================================="
echo "Nodes that worked (no errors):"
echo "=============================================="

# Find nodes that are in all_nodes but not in failed_nodes
working_nodes=()
for node in "${!all_nodes[@]}"; do
    if [ -z "${failed_nodes[$node]}" ]; then
        working_nodes+=("$node")
    fi
done

if [ ${#working_nodes[@]} -eq 0 ]; then
    echo "No nodes completed jobs without errors."
else
    # Sort and print working nodes
    printf '%s\n' "${working_nodes[@]}" | sort
    echo ""
    echo "Total unique nodes without errors: ${#working_nodes[@]}"
fi
