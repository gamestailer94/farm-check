#!/bin/sh

# Initialize parameters
DEVICE_TYPE=""
DEBUG=0

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
        --debug)
            DEBUG=1
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Usage: $0 [-d device_type] [--debug] <block_device> [block_device2 ...]"
    echo "       Use ALL to try to find all block devices"
    echo "       Use -d to specify device type (see smartctl(8) for available types)"
    echo "       Use --debug to print full SMART data and FARM output for debugging"
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
    local name=$1
    local value=$2
    # add : to the name if it is not empty
    if [ -n "$name" ]; then
        name="$name:"
    fi
    printf "%-15s %s\n" "$name" "$value"
}


# Function to validate head hours
validate_head_hours() {
    local FARM_OUTPUT="$1"
    local SMART_HOURS="$2"
    
    # Extract Write Power On values by Head
    WRITE_POWER_ON_LINES=$(echo "$FARM_OUTPUT" | grep "Write Power On (hrs) by Head")
    if [ -z "$WRITE_POWER_ON_LINES" ]; then
        # No head data found
        format_output_column "HEAD" "N/A (No head data found)"
        return 0
    fi
    
    # Initialize variables for tracking the maximum value
    MAX_HEAD_HOURS=0
    MAX_HEAD_NUMBER=""
    
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
        # Only divide by 3600 if smartctl version is exactly 7.4
        # Newer versions don't have the display problem
        if [ "$SMARTCTL_VERSION" = "7.4" ]; then
            HOURS_VALUE=$(( SECONDS_VALUE / 3600 ))
        else
            HOURS_VALUE=$SECONDS_VALUE
        fi
        
        # Check if this is the maximum value so far
        if [ "$HOURS_VALUE" -gt "$MAX_HEAD_HOURS" ]; then
            MAX_HEAD_HOURS=$HOURS_VALUE
            MAX_HEAD_NUMBER=$HEAD_NUMBER
        fi
        
        # Debug output if requested
        if [ $DEBUG -eq 1 ]; then
            format_output_column "Head $HEAD_NUMBER" "$SECONDS_VALUE seconds = $HOURS_VALUE hours"
        fi
    done < "$TEMP_HEAD_DATA"
    
    # Clean up temporary file
    rm -f "$TEMP_HEAD_DATA"
    
    # Validate that the maximum head hours is less than total power on hours
    if [ "$MAX_HEAD_HOURS" -gt "$SMART_HOURS" ]; then
        format_output_column "HEAD" "FAIL (Head $MAX_HEAD_NUMBER: $MAX_HEAD_HOURS hrs > Total: $SMART_HOURS hrs)"
        return 1
    else
        format_output_column "HEAD" "PASS (Max: $MAX_HEAD_HOURS hrs)"
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
        echo "=== DEBUG: Full SMART data for $DEVICE ==="
        echo "$SMART_DATA"
        echo
        echo "=== DEBUG: Full FARM output for $DEVICE ==="
        echo "$FARM_OUTPUT"
        echo
    fi
    
    # Extract information from the stored SMART data using awk to get only the values
    FAMILY=$(echo "$SMART_DATA" | awk -F':' '/Model Family/{gsub(/^[ \t]+/, "", $2); print $2}')
    if [ -z "$FAMILY" ]; then
        FAMILY="N/A (smartmontools does not know this device or device does not report Model Family)"
    fi
    
    MODEL=$(echo "$SMART_DATA" | awk -F':' '/Device Model/{gsub(/^[ \t]+/, "", $2); print $2}')
    if [ -z "$MODEL" ]; then
        MODEL="N/A (smartmontools does not know this device or device does not report Device Model)"
    fi
    
    SERIAL=$(echo "$SMART_DATA" | awk -F':' '/Serial Number/{gsub(/^[ \t]+/, "", $2); print $2}')
    if [ -z "$SERIAL" ]; then
        SERIAL="N/A (smartmontools does not know this device or device does not report Serial Number)"
    fi
    
    format_output_column "Model Family" "$FAMILY"
    format_output_column "Device Model" "$MODEL"
    format_output_column "Serial Number" "$SERIAL"
    echo

    SMART_HOURS=$(echo "$SMART_DATA" | awk '/Power_On_Hours/{print $10}' | head -n 1)
    FARM_HOURS=$(echo "$FARM_OUTPUT" | awk '/Power on Hours:/{print $4}' | head -n 1)

    # Check if FARM hours are available
    if [ -z "$FARM_HOURS" ]; then
        format_output_column "" "FARM data not available - likely not a Seagate drive"
        format_output_column "SMART" "$SMART_HOURS"
        format_output_column "FARM" "N/A"
        format_output_column "HEAD" "N/A"
        format_output_column "RESULT" "SKIP"
        echo
        return
    fi
    
    # Calculate absolute difference
    DIFF=$(( SMART_HOURS - FARM_HOURS ))
    ABS_DIFF=${DIFF#-}  # Remove negative sign
    
    # Determine hours difference result
    HOURS_RESULT="FAIL"
    if [ $ABS_DIFF -le 1 ]; then
        HOURS_RESULT="PASS"
    fi
    
    # Validate head hours
    HEAD_RESULT=$(validate_head_hours "$FARM_OUTPUT" "$SMART_HOURS")
    HEAD_STATUS=$?
    
    # Determine overall result
    RESULT="PASS"
    if [ "$HOURS_RESULT" = "FAIL" ] || [ $HEAD_STATUS -ne 0 ]; then
        RESULT="FAIL"
    fi
    
    format_output_column "SMART" "$SMART_HOURS"
    format_output_column "FARM" "$FARM_HOURS"
    echo "$HEAD_RESULT"
    format_output_column "RESULT" "$RESULT"
    
    echo
}

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
        fi
    done

    # Synology /dev/sata* block devices
    for device in /dev/sata*; do
        # Skip partition devices (e.g., /dev/sata1p1)
        if echo "$device" | grep -q -E 'sata[0-9][0-9]?[0-9]?$'; then
            check_device "$device"
        fi
    done

    # Synology /dev/sas* block devices
    for device in /dev/sas*; do
        # Skip partition devices (e.g., /dev/sas1p1)
        if echo "$device" | grep -q -E 'sas[0-9][0-9]?[0-9]?$'; then
            check_device "$device"
        fi
    done
else
    # Handle explicit device arguments
    for device in "$@"; do
        check_device "$device"
    done
fi
