#!/bin/sh

# Initialize parameters
DEVICE_TYPE=""
DEBUG=0
VERBOSE=0
HIDE_SERIAL=0
BASIC_ONLY=0

# Colors
RED=""
GREEN=""
YELLOW=""
BLUE=""
NC=""

# set colors if terminal supports it
if [ -t 1 ]; then
    RED="\e[31m"
    GREEN="\e[32m"
    YELLOW="\e[33m"
    BLUE="\e[34m"
    NC="\e[0m" # No Color
fi

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -d)
            shift
            if [ $# -eq 0 ]; then
                echo "Error: -d requires a parameter"
                exit 1
            fi
            DEVICE_TYPE="$1"
            shift
            ;;
        --basic)
            BASIC_ONLY=1
            shift
            ;;
        --debug)
            DEBUG=1
            # implicitly set VERBOSE to 1
            VERBOSE=1
            shift
            ;;
        -v)
            VERBOSE=1
            shift
            ;;
        -ns)
            HIDE_SERIAL=1
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Usage: $0 [-d device_type] [-f factor] [-v] [--debug] [-ns] <block_device> [block_device2 ...]"
    echo "       Use ALL to try to find all block devices"
    echo "       Use -d to specify device type (see smartctl(8) for available types)"
    echo "       Use --basic to only show basic check result"
    echo "       Use -v to display verbose information"
    echo "       Use --debug to print full SMART data and FARM output for debugging"
    echo "       Use -ns to hide serial numbers in the output"
    exit 1
fi

if ! smartctl -V &> /dev/null; then
    echo "Error: smartctl not found. Please install smartmontools."
    exit 1
fi

# Check smartctl version
SMARTCTL_VERSION=$(smartctl -V | head -n 1 | awk '{print $2}')
if [ "$(printf '%s\n' "7.4" "$SMARTCTL_VERSION" | sort -V | head -n1)" != "7.4" ]; then
    echo "Error: smartctl version $SMARTCTL_VERSION is less than required version 7.4."
    exit 1
fi

format_output_column() {
    local value1=$1
    local value2=$2
    local value3=$3

    # add : to the value1 if it is not empty
    if [ -n "$value1" ]; then
        value1="$value1:"
    fi

    # if value1 is RESULT, colorize the value2
    if [ "$value1" = "RESULT:" ]; then
        if [ "$value2" = "PASS" ]; then
            value2=$(echo -e "${GREEN}$value2${NC}")
        elif [ "$value2" = "FAIL" ]; then
            value2=$(echo -e "${RED}$value2${NC}")
        fi
    elif [ "$value1" = "WARN:" ]; then
        value1=$(echo -e "${YELLOW}$value1${NC}")
    elif [ "$value1" = "INF:" ]; then
        value1=$(echo -e "${BLUE}$value1${NC}")
    elif [ "$value1" = "ERR:" ]; then
        value1=$(echo -e "${RED}$value1${NC}")
    fi

    if [ -n "$value3" ]; then
        printf "%-15s %-15s %s\n" "$value1" "$value2" "$value3"
    else
        printf "%-15s %s\n" "$value1" "$value2"
    fi
}


# Function to validate head hours
validate_head_hours() {
    local FARM_OUTPUT="$1"
    
    # Extract Write Power On values by Head
    # Format 1 smartctl >7.4
    WRITE_POWER_ON_LINES=$(echo "$FARM_OUTPUT" | grep "Write Power On (sec) by Head")
    # Format 2 smartctl 7.4
    if [ -z "$WRITE_POWER_ON_LINES" ]; then
        WRITE_POWER_ON_LINES=$(echo "$FARM_OUTPUT" | grep "Write Power On (hrs) by Head")
    fi
    if [ -z "$WRITE_POWER_ON_LINES" ]; then
        # No head data found
        format_output_column "HEAD" "N/A (No head data found)"
        return 0
    fi
    
    # Initialize variables for tracking the maximum and minimum values
    MAX_HEAD_HOURS=0
    MAX_HEAD_NUMBER=""
    MIN_HEAD_HOURS=999999999  # Start with a very high number
    MIN_HEAD_NUMBER=""
    
    # Create a temporary file to store head data
    TEMP_HEAD_DATA=$(mktemp)
    
    # Process each head's write power on time
    echo "$WRITE_POWER_ON_LINES" > "$TEMP_HEAD_DATA"
    
    while read -r line; do
        # Extract head number and seconds value
        HEAD_NUMBER=$(echo "$line" | awk '{print $7}')
        SECONDS_VALUE=$(echo "$line" | awk '{print $8}')
        # remove : from the head number
        HEAD_NUMBER=${HEAD_NUMBER%:}
        
        # Convert seconds to hours (integer division)
        HOURS_VALUE=$(( SECONDS_VALUE / 3600 ))
        
        # Check if this is the maximum value so far
        if [ "$HOURS_VALUE" -gt "$MAX_HEAD_HOURS" ]; then
            MAX_HEAD_HOURS=$HOURS_VALUE
            MAX_HEAD_NUMBER=$HEAD_NUMBER
        fi
        
        # Check if this is the minimum value so far (only if hours > 0)
        if [ "$HOURS_VALUE" -gt 0 ] && [ "$HOURS_VALUE" -lt "$MIN_HEAD_HOURS" ]; then
            MIN_HEAD_HOURS=$HOURS_VALUE
            MIN_HEAD_NUMBER=$HEAD_NUMBER
        fi
        
        if [ $VERBOSE -eq 1 ]; then
            format_output_column "Head $HEAD_NUMBER" "$SECONDS_VALUE seconds" "~$HOURS_VALUE hours"
        fi
    done < "$TEMP_HEAD_DATA"
    
    # Clean up temporary file
    rm -f "$TEMP_HEAD_DATA"

    HEAD_FLYING_HOURS=$(echo "$FARM_OUTPUT" | awk '/Head Flight Hours/{print $4}')
    
    # Validate that the maximum head hours is less than total power on hours
    if [ "$MAX_HEAD_HOURS" -gt "$HEAD_FLYING_HOURS" ]; then
        format_output_column "WARN" "The Highest Head Power On Hours ($MAX_HEAD_HOURS hrs on Head $MAX_HEAD_NUMBER) is greater than the Head Flying Hours ($HEAD_FLYING_HOURS hrs)"
        format_output_column "WARN" "This MAY indicate a fraudulent or tampered drive"
        return 1
    fi
    # Check for substantial difference between min and max hours
    # Only if we have valid min and max values
    if [ "$MIN_HEAD_HOURS" -ne 999999999 ] && [ "$MAX_HEAD_HOURS" -gt 0 ]; then
        # Calculate the difference
        # We want to check if: (max - min) / min > MAX_RATIO
        # To avoid floating point math in shell, we'll use a scaled integer approach
        # Multiply both sides by 1000 to handle decimal factors
        # (max - min) * 1000 / min > MAX_RATIO * 1000
        DIFF=$(( MAX_HEAD_HOURS - MIN_HEAD_HOURS ))

        MAX_RATIO=30000 # 30.0
        
        # Calculate (max - min) * 1000 / min
        RATIO=$(awk "BEGIN {printf \"%.0f\", $DIFF * 1000 / $MIN_HEAD_HOURS}")

        # Convert RATIO to floating point
        ACTUAL_RATIO=$(awk "BEGIN {printf \"%.2f\", $RATIO / 1000}")

        format_output_column "Min" "$MIN_HEAD_HOURS hrs on Head $MIN_HEAD_NUMBER"
        format_output_column "Max" "$MAX_HEAD_HOURS hrs on Head $MAX_HEAD_NUMBER"
        format_output_column "Difference" "$DIFF hrs"
        format_output_column "Ratio" "$ACTUAL_RATIO (Threshold: 30)"

        if [ "$RATIO" -gt "$MAX_RATIO" ]; then
            echo
            format_output_column "WARN" "The difference between the Highest and Lowest Head Power On Hours ($DIFF hrs) is rather large"
            format_output_column "WARN" "This MAY indicate a fraudulent or tampered drive"
            format_output_column "WARN" "Run with -v for more details"
        fi
        return 0
    else
        format_output_column "INF" "Couldn't determine minimum head hours"
        format_output_column "INF" "Either the drive is factory new, or there is only one head"
        echo
        format_output_column "Max" "$MAX_HEAD_HOURS hrs on Head $MAX_HEAD_NUMBER"
        return 0
    fi
}


check_device() {
    local DEVICE=$1
    
    # Skip if device doesn't exist
    if [ ! -e "$DEVICE" ]; then
        return
    fi
    
    # Skip if not a block device
    if [ ! -b "$DEVICE" ]; then
        return
    fi
    
    echo "=== Checking device: $DEVICE ==="

    # Prepare smartctl command with device type if specified
    SMARTCTL_CMD="smartctl"
    if [ -n "$DEVICE_TYPE" ]; then
        SMARTCTL_CMD="$SMARTCTL_CMD -d $DEVICE_TYPE"
    fi

    # Get all SMART data once and store it
    SMART_DATA=$($SMARTCTL_CMD -a "$DEVICE")
    
    # Get FARM data for debugging
    FARM_OUTPUT=$($SMARTCTL_CMD -l farm "$DEVICE")
    
    # Print debug information if requested
    if [ $DEBUG -eq 1 ]; then
        DEBUG_OUTPUT=$($SMARTCTL_CMD -x -l farm "$DEVICE")
        echo "=== DEBUG: Full SMART and FARM data for $DEVICE ==="
        echo "$DEBUG_OUTPUT"
        echo "=== END DEBUG ==="
        echo
    fi
    
    # Extract information from the stored SMART data using awk to get only the values
    FAMILY=$(echo "$SMART_DATA" | awk -F':' '/Model Family/{gsub(/^[ \t]+/, "", $2); print $2}')
    if [ -z "$FAMILY" ]; then
        FAMILY="N/A (device does not report Model Family)"
    fi
    
    MODEL=$(echo "$SMART_DATA" | awk -F':' '/Device Model/{gsub(/^[ \t]+/, "", $2); print $2}')
    if [ -z "$MODEL" ]; then
        MODEL="N/A (device does not report Device Model)"
    fi
    
    SERIAL=$(echo "$SMART_DATA" | awk -F':' '/Serial Number/{gsub(/^[ \t]+/, "", $2); print $2}')
    if [ -z "$SERIAL" ]; then
        SERIAL="N/A (device does not report Serial Number)"
    fi
    
    format_output_column "Model Family" "$FAMILY"
    format_output_column "Device Model" "$MODEL"
    if [ $HIDE_SERIAL -eq 1 ]; then
        SERIAL="[hidden]"
    fi
    format_output_column "Serial Number" "$SERIAL"
    echo

    # Extract Power On Hours from SMART and FARM data

    SMART_HOURS=$(echo "$SMART_DATA" | awk '/Power_On_Hours/{print $10}' | head -n 1)
    FARM_HOURS=$(echo "$FARM_OUTPUT" | awk '/Power on Hours:/{print $4}' | head -n 1)

    # Check if FARM hours are available
    if [ -z "$FARM_HOURS" ]; then
        format_output_column "INF" "FARM data not available - likely not a Seagate drive"

        format_output_column "RESULT" "SKIP"
        echo
        echo
        return
    fi
    
    # Calculate absolute difference for power on hours
    DIFF=$(( SMART_HOURS - FARM_HOURS ))
    DIFF=${DIFF#-}  # Remove negative sign

    # Determine power on hours difference result 
    RESULT="FAIL"
    if [ $DIFF -le 1 ]; then
        RESULT="PASS"
    fi

    format_output_column "Basic Check" ""
    format_output_column "RESULT" "$RESULT"
    echo

    if [ $BASIC_ONLY -eq 1 ]; then
        echo
        return $([ $RESULT = "PASS" ])
    fi

    format_output_column "Detailed Values" ""
    echo
    
    format_output_column "Power on hours" ""
    format_output_column "SMART" "$SMART_HOURS"
    format_output_column "FARM" "$FARM_HOURS"
    format_output_column "DIFF" "$DIFF"
    if [ $DIFF -gt 1 ]; then
        format_output_column "ERR" "Power On Hours differ by more than 1 hour"
        format_output_column "ERR" "This is very likely a fraudulent or tampered drive"
    fi
    echo

    # Extract Head Flying Hours from SMART and FARM data
    SMART_FLYING_HOURS=$(echo "$SMART_DATA" | awk '/Head_Flying_Hours/{split($10, a, "h"); print a[1]}' | head -n 1)
    FARM_FLYING_HOURS=$(echo "$FARM_OUTPUT" | awk '/Head Flight Hours:/{print $4}')

    # Calculate absolute difference for head flying hours
    DIFF_FLYING=$(( SMART_FLYING_HOURS - FARM_FLYING_HOURS ))
    DIFF_FLYING=${DIFF_FLYING#-}  # Remove negative sign

    format_output_column "Head Flying Hours" ""
    format_output_column "SMART" "$SMART_FLYING_HOURS"
    format_output_column "FARM" "$FARM_FLYING_HOURS"
    format_output_column "DIFF" "$DIFF_FLYING"
    if [ $DIFF_FLYING -gt 10 ]; then
        format_output_column "WARN" "Head Flying Hours differ by more than 10 hours"
        format_output_column "WARN" "This MAY indicate a fraudulent or tampered drive"
        format_output_column "WARN" "But can also be due to different measurement methods"
    fi
    echo
    format_output_column "Write Power On by Head" ""
    validate_head_hours "$FARM_OUTPUT"
    echo
    format_output_column "Additional Information" ""
    format_output_column "INF" "These Values might help determine if a drive is genuine or not"

    # Extract Assembly Date from FARM
    ASSEMBLY_DATE=$(echo "$FARM_OUTPUT" | awk '/Assembly Date \(YYWW\):/{print $4}')
    # split and reverse
    ASSEMBLY_YEAR=$(echo "$ASSEMBLY_DATE" | cut -c 1-2 | rev)
    ASSEMBLY_WEEK=$(echo "$ASSEMBLY_DATE" | cut -c 3-4 | rev)
    # convert to full year
    ASSEMBLY_YEAR=$(( 2000 + ASSEMBLY_YEAR ))

    format_output_column "Assembly" "Week $ASSEMBLY_WEEK of $ASSEMBLY_YEAR"
    format_output_column "Reallocated" $(echo "$FARM_OUTPUT" | awk '/Number of Reallocated Sectors:/{print $5}')
    POWER_CYCLES=$(echo "$SMART_DATA" | awk '/Power_Cycle_Count/{print $10}')
    format_output_column "Power Cycles" "$POWER_CYCLES"
    START_STOP_COUNT=$(echo "$SMART_DATA" | awk '/Start_Stop_Count/{print $10}')
    format_output_column "Start Stops" "$START_STOP_COUNT"

    echo 
    format_output_column "Error Rates (Normalized)" ""
    format_output_column "Read" $(echo "$SMART_DATA" | awk '/Raw_Read_Error_Rate/{print $4}')
    format_output_column "Seek" $(echo "$SMART_DATA" | awk '/Seek_Error_Rate/{print $4}')

    echo
    format_output_column "Data" ""
    LOGICAL_SECTOR_SIZE=$(echo "$FARM_OUTPUT" | awk '/Logical Sector Size:/{print $4}')
    LBA_READ=$(echo "$FARM_OUTPUT" | awk '/Logical Sectors Read:/{print $4}')
    LBA_WRITE=$(echo "$FARM_OUTPUT" | awk '/Logical Sectors Written:/{print $4}')
    TB_READ=$(( LBA_READ * LOGICAL_SECTOR_SIZE / 1024 / 1024 / 1024 / 1024))
    TB_WRITE=$(( LBA_WRITE * LOGICAL_SECTOR_SIZE / 1024 / 1024 / 1024 / 1024))
    format_output_column "LBA Size" "$LOGICAL_SECTOR_SIZE bytes"
    format_output_column "Read" "$LBA_READ sectors ($TB_READ TB)"
    format_output_column "Write" "$LBA_WRITE sectors ($TB_WRITE TB)"

    echo
    return $([ $RESULT = "PASS" ])
}

HAS_FAILED=0

# Handle ALL case
if [ "$1" = "ALL" ]; then
    echo "Trying to detect all block devices..."
    echo "This only works for /dev/sd*, /dev/sata* and /dev/sas* devices."
    echo "For other devices, please specify the device explicitly."
    echo

    # /dev/sd* block devices
    for device in /dev/sd*; do
        # Skip partition devices (e.g., /dev/sda1)
        if ! echo "$device" | grep -q '[0-9]$'; then
            check_device "$device"
            if [ $? -ne 0 ]; then
                HAS_FAILED=1
            fi
        fi
    done

    # Synology /dev/sata* block devices
    for device in /dev/sata*; do
        # Skip partition devices (e.g., /dev/sata1p1)
        if echo "$device" | grep -q -E 'sata[0-9][0-9]?[0-9]?$'; then
            check_device "$device"
            if [ $? -ne 0 ]; then
                HAS_FAILED=1
            fi
        fi
    done

    # Synology /dev/sas* block devices
    for device in /dev/sas*; do
        # Skip partition devices (e.g., /dev/sas1p1)
        if echo "$device" | grep -q -E 'sas[0-9][0-9]?[0-9]?$'; then
            check_device "$device"
            if [ $? -ne 0 ]; then
                HAS_FAILED=1
            fi
        fi
    done
else
    # Handle explicit device arguments
    for device in "$@"; do
        check_device "$device"
        if [ $? -ne 0 ]; then
            HAS_FAILED=1
        fi
    done
fi

if [ $HAS_FAILED -eq 1 ]; then
    exit 2
fi
