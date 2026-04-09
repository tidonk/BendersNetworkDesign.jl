#!/bin/bash
#
# compile_instance_csv.sh
#
# Compile multiple CSV files with different settings for the same instance
# into a single CSV file per instance.
#
# Usage:
#   ./compile_instance_csv.sh [-f]
#
# Options:
#   -f    Force overwrite of existing compiled CSV files
#
# Behavior:
#   - Scans results/ directory for CSV files
#   - Groups files by instance name (e.g., abilene-*.csv -> abilene.csv)
#   - Combines all settings for each instance into one CSV
#   - Warns if output file exists (unless -f is specified)
#   - Reports compilation statistics

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Parse arguments
FORCE_OVERWRITE=0
if [ "$1" == "-f" ]; then
    FORCE_OVERWRITE=1
fi

# Check if results directory exists
if [ ! -d "results" ]; then
    echo -e "${RED}Error: results/ directory not found${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CSV Compilation Tool${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Results directory: results/"
echo "Force overwrite: $([ $FORCE_OVERWRITE -eq 1 ] && echo 'yes' || echo 'no')"
echo ""

# Find all CSV files that match the pattern <instance>-<config>*.csv
# Exclude files that are already compiled (just <instance>.csv) and test files
csv_files=$(find results/ -maxdepth 1 -type f -name "*-*.csv" ! -name "*_local_test*" || true)

if [ -z "$csv_files" ]; then
    echo -e "${YELLOW}No CSV files with configuration patterns found in results/${NC}"
    echo "Expected format: <instance>-<config>.csv or <instance>-<config>-results.csv"
    exit 0
fi

# Extract unique instance names
# Format: abilene-test_cuts5_order_none-results.csv -> abilene
declare -A instances

for csv_file in $csv_files; do
    basename_file=$(basename "$csv_file" .csv)
    
    # Extract instance name (everything before the settings pattern)
    # Settings patterns: test_*, compact, default, benders_*, oracle_*
    # First remove -results suffix if present
    basename_file="${basename_file%-results}"
    
    # Match instance name (everything before any settings pattern)
    # Matches: test_*, compact, default, benders_*, oracle_*, or any other config pattern
    if [[ "$basename_file" =~ ^(.+)-(test_|compact|default|benders_|oracle_read) ]]; then
        instance="${BASH_REMATCH[1]}"
        instances[$instance]=1
    fi
done

# Check if we found any instances
if [ ${#instances[@]} -eq 0 ]; then
    echo -e "${YELLOW}No CSV files with instance-config pattern found${NC}"
    echo "Expected format: <instance>-<config>.csv"
    echo "Example: abilene-test_cuts5_order_none.csv"
    exit 0
fi

echo "Found ${#instances[@]} unique instance(s)"
echo ""

# Create compiled directory
mkdir -p results/compiled

# Compile CSVs for each instance
compiled_count=0
skipped_count=0
total_settings=0

for instance in "${!instances[@]}"; do
    output_file="results/compiled/${instance}.csv"
    
    # Find all CSV files for this instance (both patterns)
    # Use grep to ensure exact instance name match (avoid matching janos-us-ca when looking for janos-us)
    source_files=$(find results/ -maxdepth 1 -type f \( -name "${instance}-*.csv" \) ! -name "${instance}.csv" | grep -E "/${instance}-(test_|compact|default|benders_|oracle_)" | sort)
    
    # Count source files
    num_settings=$(echo "$source_files" | grep -c "." || echo "0")
    
    if [ "$num_settings" -eq 0 ]; then
        echo -e "${YELLOW}Warning: No source files found for instance '$instance'${NC}"
        continue
    fi
    
    total_settings=$((total_settings + num_settings))
    
    echo -e "${GREEN}Processing instance: $instance${NC}"
    echo "  Settings count: $num_settings"
    echo "  Output file: $output_file"
    
    # Check if output file exists
    if [ -f "$output_file" ] && [ $FORCE_OVERWRITE -eq 0 ]; then
        echo -e "  ${YELLOW}⚠ Output file already exists (use -f to overwrite)${NC}"
        echo "  Skipping..."
        skipped_count=$((skipped_count + 1))
        echo ""
        continue
    fi
    
    # Compile CSVs
    first_file=1
    temp_file="${output_file}.tmp"
    rm -f "$temp_file"
    
    for source_file in $source_files; do
        # Check if file has content
        if [ ! -s "$source_file" ]; then
            echo "  Warning: Skipping empty file: $(basename "$source_file")"
            continue
        fi
        
        if [ $first_file -eq 1 ]; then
            # First file: include header
            cat "$source_file" > "$temp_file"
            first_file=0
        else
            # Subsequent files: skip header (first line)
            tail -n +2 "$source_file" >> "$temp_file"
        fi
    done
    
    # Check if we created a valid temp file
    if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
        echo -e "  ${RED}✗ Failed to compile (all source files empty)${NC}"
        rm -f "$temp_file"
        echo ""
        continue
    fi
    
    # Move temp file to output file
    mv "$temp_file" "$output_file"
    
    # Count rows in compiled file (excluding header)
    row_count=$(($(wc -l < "$output_file") - 1))
    
    echo "  ✓ Compiled $row_count row(s)"
    echo "  Output: $output_file"
    compiled_count=$((compiled_count + 1))
    echo ""
done

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Compilation Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Unique instances: ${#instances[@]}"
echo "Total settings across all instances: $total_settings"
echo "Successfully compiled: $compiled_count instance(s)"
if [ $skipped_count -gt 0 ]; then
    echo -e "${YELLOW}Skipped (already exists): $skipped_count instance(s)${NC}"
fi
echo ""

if [ $compiled_count -gt 0 ]; then
    echo -e "${GREEN}Compiled CSV files are in: results/compiled/${NC}"
    echo "Files created:"
    for instance in "${!instances[@]}"; do
        output_file="results/compiled/${instance}.csv"
        if [ -f "$output_file" ]; then
            rows=$(($(wc -l < "$output_file") - 1))
            echo "  - ${instance}.csv ($rows rows)"
        fi
    done
fi

echo ""
echo -e "${GREEN}Done!${NC}"
