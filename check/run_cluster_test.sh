#!/bin/bash
#
# run_cluster_test.sh
#
# Process a testset file and submit HTCondor jobs for each instance-settings combination.
#
# Usage:
#   ./run_cluster_test.sh [--dry-run] [-f|--force] [--remove-wrong-oracle] <testset_file>
#
# Options:
#   --dry-run: Generate submission files but do not submit jobs
#   -f, --force: Force start all jobs, even if CSV files already exist
#   --remove-wrong-oracle: Remove oracle CSV files that had validation errors
#
# Arguments:
#   testset_file: Path to testset file (e.g., testset/abilene.test)
#
# Settings Auto-Detection:
#   If testset file is named 'testset/NAME.test', the script will automatically
#   use all settings from '../settings/NAME/' folder.
#   Example: testset/experiment5.test → uses all *.toml from ../settings/experiment5/
#
# Testset file format (one entry per line):
#   <network_file>;[settings_file]  (settings optional if auto-detected)
#
# Example testset entries:
#   ../data/generated/experiment5/instance_0001.xml
#   ../data/sndlib/abilene.xml;../settings/custom.toml
#
# Output:
#   - Temporary submission files written to check/temp/
#   - Job logs written to check/logs/
#   - Results CSV written to check/results/

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
JULIA_PROJECT="$(dirname "$SCRIPT_DIR")"
cd "$SCRIPT_DIR"

# Parse arguments
DRY_RUN=0
FORCE=0
REMOVE_WRONG_ORACLE=0
TESTSET_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -f|--force)
            FORCE=1
            shift
            ;;
        --remove-wrong-oracle)
            REMOVE_WRONG_ORACLE=1
            shift
            ;;
        *)
            TESTSET_FILE="$1"
            shift
            ;;
    esac
done

# Check arguments
if [ -z "$TESTSET_FILE" ]; then
    echo -e "${RED}Error: Missing required argument${NC}"
    echo ""
    echo "Usage: $0 [--dry-run] [-f|--force] [--remove-wrong-oracle] <testset_file>"
    echo ""
    echo "Options:"
    echo "  --dry-run: Generate submission files but do not submit jobs"
    echo "  -f, --force: Force start all jobs, even if CSV files already exist"
    echo "  --remove-wrong-oracle: Remove oracle CSV files that had validation errors"
    echo ""
    echo "Arguments:"
    echo "  testset_file: Path to testset file (e.g., testset/experiment5.test)"
    echo ""
    echo "Example:"
    echo "  $0 testset/experiment5.test"
    echo "  $0 --dry-run testset/experiment5.test"
    echo "  $0 --remove-wrong-oracle testset/experiment5.test"
    exit 1
fi

# Validate testset file
if [ ! -f "$TESTSET_FILE" ]; then
    echo -e "${RED}Error: Testset file not found: $TESTSET_FILE${NC}"
    exit 1
fi

# Auto-detect settings folder from testset name
TESTSET_BASENAME=$(basename "$TESTSET_FILE" .test)
SETTINGS_FOLDER="../settings/${TESTSET_BASENAME}"
echo -e $SETTINGS_FOLDER
AUTO_DETECTED_SETTINGS=()

if [ -d "$SETTINGS_FOLDER" ]; then
    echo -e "${GREEN}Auto-detected settings folder: $SETTINGS_FOLDER${NC}"
    # Find all .toml files in settings folder
    while IFS= read -r -d '' settings_file; do
        AUTO_DETECTED_SETTINGS+=("$settings_file")
    done < <(find "$SETTINGS_FOLDER" -maxdepth 1 -name '*.toml' -print0 | sort -z)
    
    if [ ${#AUTO_DETECTED_SETTINGS[@]} -eq 0 ]; then
        echo -e "${YELLOW}Warning: No .toml files found in $SETTINGS_FOLDER${NC}"
    else
        echo "Found ${#AUTO_DETECTED_SETTINGS[@]} settings files:"
        for sf in "${AUTO_DETECTED_SETTINGS[@]}"; do
            echo "  - $(basename "$sf")"
        done
    fi
    echo ""
else
    echo -e "${YELLOW}Settings folder not found: $SETTINGS_FOLDER${NC}"
    echo "Will use settings specified in testset file (if any)"
    echo ""
fi

# Check if HTCondor is available
if [ $DRY_RUN -eq 1 ]; then
    echo -e "${YELLOW}DRY RUN MODE: Jobs will NOT be submitted${NC}"
    echo -e "${YELLOW}Submission files will be generated in temp/ directory${NC}"
    echo ""
    CONDOR_AVAILABLE=0
elif ! command -v condor_submit &> /dev/null; then
    echo -e "${YELLOW}Warning: condor_submit not found. Jobs will not be submitted.${NC}"
    echo -e "${YELLOW}Submission files will still be generated in temp/ directory.${NC}"
    CONDOR_AVAILABLE=0
else
    CONDOR_AVAILABLE=1
fi

# Create necessary directories
mkdir -p temp
mkdir -p logs
mkdir -p results

# Generate timestamp for batch names
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}HTCondor Cluster Test Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Testset: $TESTSET_FILE"
if [ $DRY_RUN -eq 1 ]; then
    echo -e "Mode: ${YELLOW}DRY RUN${NC}"
fi
if [ $FORCE -eq 1 ]; then
    echo -e "Force mode: ${YELLOW}ENABLED${NC} (will ignore existing CSV files)"
fi
if [ $REMOVE_WRONG_ORACLE -eq 1 ]; then
    echo -e "Remove wrong oracle: ${YELLOW}ENABLED${NC} (will remove oracle CSV files with validation errors)"
fi
echo "Timestamp: $TIMESTAMP"
echo ""

# Count entries in testset and calculate total jobs
TESTSET_ENTRIES=$(grep -v '^#' "$TESTSET_FILE" | grep -v '^[[:space:]]*$' | wc -l)
if [ ${#AUTO_DETECTED_SETTINGS[@]} -gt 0 ]; then
    TOTAL_JOBS=$((TESTSET_ENTRIES * ${#AUTO_DETECTED_SETTINGS[@]}))
    echo "Testset entries: $TESTSET_ENTRIES"
    echo "Settings per entry: ${#AUTO_DETECTED_SETTINGS[@]}"
else
    TOTAL_JOBS=$TESTSET_ENTRIES
fi
echo "Total jobs to submit: $TOTAL_JOBS"
echo ""

# Check for Julia
if ! command -v julia &> /dev/null; then
    echo -e "${RED}Error: julia not found in PATH${NC}"
    exit 1
fi

# Process each line in testset
JOB_COUNT=0
SUBMIT_COUNT=0
SKIP_COMPLETED_COUNT=0
SKIP_RUNNING_COUNT=0
SKIP_ORACLE_MISSING_COUNT=0
REMOVED_ORACLE_COUNT=0

# First pass: detect and optionally remove oracle files with validation errors
if [ $REMOVE_WRONG_ORACLE -eq 1 ]; then
    echo "Scanning for oracle validation errors..."
    for out_file in logs/*-oracle_read.out; do
        [ -f "$out_file" ] || continue
        if grep -q "OracleError: Oracle validation failed at" "$out_file"; then
            # Extract instance name from log file name
            instance_name=$(basename "$out_file" | sed 's/-oracle_read\.out$//')
            oracle_csv="$SCRIPT_DIR/oracle/${instance_name}.csv"
            if [ -f "$oracle_csv" ]; then
                echo -e "  ${RED}✗ Removing oracle file with validation error: $oracle_csv${NC}"
                rm -f "$oracle_csv"
                REMOVED_ORACLE_COUNT=$((REMOVED_ORACLE_COUNT+1))
            fi
        fi
    done
    if [ $REMOVED_ORACLE_COUNT -gt 0 ]; then
        echo -e "${GREEN}Removed $REMOVED_ORACLE_COUNT oracle CSV file(s) with validation errors${NC}"
    else
        echo "No oracle validation errors found"
    fi
    echo ""
fi

# Get list of currently running jobs (extract job identifiers from arguments)
echo "Checking for running jobs..."
# Extract network and settings files from the Arguments field which contains the full command
# Match any .xml and .toml files (not just sndlib), extract basenames
RUNNING_JOBS=$(condor_q -af Arguments 2>/dev/null | awk -F"'" '{
    network=""
    settings=""
    for (i=1; i<=NF; i++) {
        if ($i ~ /\.xml$/) {
            network=$i
            # Extract basename from full path
            gsub(/.*\//, "", network)
            gsub(/\.xml$/, "", network)
        }
        if ($i ~ /\.toml$/) {
            settings=$i
            # Extract basename from full path
            gsub(/.*\//, "", settings)
            gsub(/\.toml$/, "", settings)
        }
    }
    if (network != "" && settings != "") {
        print network "-" settings
    }
}' | sort -u)

NUM_RUNNING=$(echo "$RUNNING_JOBS" | grep -c "^" || echo "0")
# Adjust for grep counting empty line
if [ -z "$RUNNING_JOBS" ]; then
    NUM_RUNNING=0
fi
echo "$NUM_RUNNING running jobs"
if [ "$NUM_RUNNING" -gt 0 ]; then
    echo "Running jobs:"
    echo "$RUNNING_JOBS" | sed 's/^/  - /'
fi
echo ""

while IFS=';' read -r network_file settings_file_override || [ -n "$network_file" ]; do
    # Skip comments and empty lines
    [[ "$network_file" =~ ^#.*$ ]] && continue
    [[ -z "$network_file" ]] && continue
    
    # Trim whitespace
    network_file=$(echo "$network_file" | xargs)
    settings_file_override=$(echo "$settings_file_override" | xargs)
    
    # Determine settings files to use
    SETTINGS_TO_USE=()
    if [ -n "$settings_file_override" ]; then
        # Use explicit settings from testset file
        SETTINGS_TO_USE=("$settings_file_override")
    elif [ ${#AUTO_DETECTED_SETTINGS[@]} -gt 0 ]; then
        # Use auto-detected settings
        SETTINGS_TO_USE=("${AUTO_DETECTED_SETTINGS[@]}")
    else
        echo -e "${RED}Error: No settings specified for $network_file and no auto-detected settings${NC}"
        continue
    fi
    
    # Process each settings file for this network
    for settings_file in "${SETTINGS_TO_USE[@]}"; do
    
    # Extract instance and config names
    instance_name=$(basename "$network_file" .xml)
    config_name=$(basename "$settings_file" .toml)
    
    # Generate batch name per instance
    BATCH_NAME="${instance_name}"
    
    # Create unique job identifier
    job_id="${instance_name}-${config_name}"

    # Check if oracle_read settings require oracle CSV file
    if echo "$config_name" | grep -qi "oracle_read"; then
        oracle_csv="$SCRIPT_DIR/oracle/${instance_name}.csv"
        if [ ! -f "$oracle_csv" ]; then
            echo -e "${BLUE}Job $((JOB_COUNT+1))/$TOTAL_JOBS: $job_id${NC}"
            echo -e "  ${RED}✗ Skipped: Oracle file not found: $oracle_csv${NC}"
            echo -e "  ${YELLOW}Note: oracle_read settings require oracle CSV file${NC}"
            SKIP_ORACLE_MISSING_COUNT=$((SKIP_ORACLE_MISSING_COUNT+1))
            JOB_COUNT=$((JOB_COUNT+1))
            echo ""
            continue
        fi
    fi

    # Define output CSV (one per instance)
    output_csv="/home/donkiewicz/repos/git-or/benders-subproblem-selection/BendersNetworkDesign2/check/results/${job_id}-results.csv"
    
    # Check if job already completed (CSV exists and has content) - skip unless force mode
    if [ $FORCE -eq 0 ] && [ -f "$output_csv" ] && [ -s "$output_csv" ]; then
        # For oracle_write, also verify the oracle CSV was created
        if echo "$config_name" | grep -qi "oracle_write"; then
            oracle_csv="$SCRIPT_DIR/oracle/${instance_name}.csv"
            if [ ! -f "$oracle_csv" ]; then
                echo -e "${BLUE}Job $((JOB_COUNT+1))/$TOTAL_JOBS: $job_id${NC}"
                echo -e "  ${YELLOW}⚠ Resubmitting: Oracle file missing despite completed results${NC}"
                echo -e "  ${YELLOW}  Expected: $oracle_csv${NC}"
                # Don't skip, allow resubmission
            else
                echo -e "${BLUE}Job $((JOB_COUNT+1))/$TOTAL_JOBS: $job_id${NC}"
                echo -e "  ${YELLOW}⊙ Skipped: Already completed (CSV and oracle exist)${NC}"
                SKIP_COMPLETED_COUNT=$((SKIP_COMPLETED_COUNT+1))
                JOB_COUNT=$((JOB_COUNT+1))
                echo ""
                continue
            fi
        else
            echo -e "${BLUE}Job $((JOB_COUNT+1))/$TOTAL_JOBS: $job_id${NC}"
            echo -e "  ${YELLOW}⊙ Skipped: Already completed (CSV exists)${NC}"
            SKIP_COMPLETED_COUNT=$((SKIP_COMPLETED_COUNT+1))
            JOB_COUNT=$((JOB_COUNT+1))
            echo ""
            continue
        fi
    fi
    
    # Check if job is currently running - skip unless force mode
    if [ $FORCE -eq 0 ] && [ -n "$RUNNING_JOBS" ] && echo "$RUNNING_JOBS" | grep -q "^${job_id}$"; then
        echo -e "${BLUE}Job $((JOB_COUNT+1))/$TOTAL_JOBS: $job_id${NC}"
        echo -e "  ${YELLOW}⊙ Skipped: Already running in HTCondor${NC}"
        SKIP_RUNNING_COUNT=$((SKIP_RUNNING_COUNT+1))
        JOB_COUNT=$((JOB_COUNT+1))
        echo ""
        continue
    fi
    
    # For oracle_read jobs, check for oracle validation errors in .out file
    if echo "$config_name" | grep -qi "oracle_read"; then
        out_file="logs/${job_id}.out"
        oracle_csv="$SCRIPT_DIR/oracle/${instance_name}.csv"
        if [ -f "$out_file" ]; then
            if grep -q "OracleError: Oracle validation failed at" "$out_file"; then
                echo -e "${BLUE}Job $((JOB_COUNT+1))/$TOTAL_JOBS: $job_id${NC}"
                echo -e "  ${RED}✗ Skipped: Oracle validation error detected in previous run${NC}"
                echo -e "  ${YELLOW}Log file: $SCRIPT_DIR/$out_file${NC}"
                echo -e "  ${YELLOW}Note: Oracle CSV file preserved for inspection: $oracle_csv${NC}"
                SKIP_ORACLE_MISSING_COUNT=$((SKIP_ORACLE_MISSING_COUNT+1))
                JOB_COUNT=$((JOB_COUNT+1))
                echo ""
                continue
            fi
        fi
    fi
    
    # Create submission file from template
    submission_file="temp/${job_id}.sub"
    
    echo -e "${GREEN}Preparing job $((JOB_COUNT+1))/$TOTAL_JOBS: $job_id${NC}"
    echo "  Network: $network_file"
    echo "  Settings: $settings_file"
    echo "  Output CSV: $output_csv"

    # if a condor error log already exists, print its location
    if [ -f "logs/${job_id}.err" ]; then
        echo -e "  ${YELLOW}⚠ Note: An error log already exists for this job: logs/${job_id}.err${NC}"
    fi
    
    # Validate files exist
    if [ ! -f "$network_file" ]; then
        echo -e "${RED}  Error: Network file not found: $network_file${NC}"
        echo -e "${YELLOW}  Skipping this job...${NC}"
        echo ""
        continue
    else
        network_file=$(realpath "$network_file")
    fi
    
    if [ ! -f "$settings_file" ]; then
        echo -e "${RED}  Error: Settings file not found: $settings_file${NC}"
        echo -e "${YELLOW}  Skipping this job...${NC}"
        echo ""
        continue
    else
        settings_file=$(realpath "$settings_file")
    fi
    
    # Copy template and customize
    cp htcondor_template.sub "$submission_file"
    
    # Add job-specific settings
    cat >> "$submission_file" << EOF

# Job-specific settings (auto-generated by run_cluster_test.sh)
executable = /bin/bash
arguments = "-c 'ls -la /local && ls -la /home/donkiewicz/ && ls -la /home/donkiewicz/.juliaup && mkdir -p /local/tmp/.juliaup_tim/.juliaup_tim && ls -la /local/tmp; rsync -a --progress /home/donkiewicz/.juliaup/ /local/tmp/.juliaup_tim/; ln -sf /local/tmp/.juliaup_tim/bin/julialauncher /local/tmp/.juliaup_tim/bin/julia; /local/tmp/.juliaup_tim/bin/julia --startup-file=no --history-file=no $JULIA_PROJECT/check/test_instance.jl $network_file $settings_file $output_csv'"
environment = "HOME=$HOME GRB_LICENSE_FILE=/opt/gurobi/gurobi.lic JULIA_DEPOT_PATH=/local/tmp/.julia_tim JULIA_PROJECT=$JULIA_PROJECT"

+JobBatchName = "$BATCH_NAME"

output = logs/${job_id}.out
error = logs/${job_id}.err
log = logs/${job_id}.log

queue
EOF
    
    echo "  Submission file: $submission_file"
    
    # Submit job if HTCondor is available
    if [ $CONDOR_AVAILABLE -eq 1 ]; then
        if condor_submit "$submission_file" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✓ Job submitted successfully${NC}"
            SUBMIT_COUNT=$((SUBMIT_COUNT+1))
            # Remove submission file after successful submission
            rm -f "$submission_file"
        else
            echo -e "${RED}  ✗ Failed to submit job${NC}"
        fi
    else
        echo -e "${YELLOW}  → Submission file created (not submitted - HTCondor unavailable)${NC}"
    fi
    
    echo ""
    JOB_COUNT=$((JOB_COUNT+1))
    
    done  # End settings loop
done < "$TESTSET_FILE"

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Jobs processed: $JOB_COUNT"
echo "  - Skipped (already completed): $SKIP_COMPLETED_COUNT"
echo "  - Skipped (already running): $SKIP_RUNNING_COUNT"
echo "  - Skipped (missing oracle file): $SKIP_ORACLE_MISSING_COUNT"
echo "  - Total skipped: $((SKIP_COMPLETED_COUNT + SKIP_RUNNING_COUNT + SKIP_ORACLE_MISSING_COUNT))"
if [ $REMOVED_ORACLE_COUNT -gt 0 ]; then
    echo "Oracle files removed: $REMOVED_ORACLE_COUNT"
fi

if [ $CONDOR_AVAILABLE -eq 1 ]; then
    echo "Jobs submitted: $SUBMIT_COUNT"
    echo ""
    echo "To monitor jobs:"
    echo "  condor_q"
    echo ""
    echo "To monitor jobs for a specific instance:"
    echo "  condor_q -const 'JobBatchName == \"<instance>\"'"
    echo ""
    echo "To remove all jobs for a specific instance:"
    echo "  condor_rm -const 'JobBatchName == \"<instance>\"'"
else
    echo "Submission files created: $JOB_COUNT"
    echo ""
    echo -e "${YELLOW}Note: HTCondor not available - jobs were not submitted${NC}"
    echo "Submission files are in: temp/"
    echo "You can submit them manually when HTCondor is available using:"
    echo "  for f in temp/*.sub; do condor_submit \$f; done"
fi

echo ""
echo "Results will be written to: results/"
echo "Logs will be written to: logs/"
echo ""
echo -e "${GREEN}Done!${NC}"

./compile_instance_csv.sh -f