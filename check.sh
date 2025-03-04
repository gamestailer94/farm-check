#!/bin/sh

# Initialize device type parameter
DEVICE_TYPE=""

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
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Usage: $0 [-d device_type] <block_device> [block_device2 ...]"
    echo "       Use ALL to try to find all block devices"
    echo "       Use -d to specify device type (see smartctl(8) for available types)"
    exit 1
fi

if ! command -v smartctl &> /dev/null; then
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
    FARM_HOURS=$($SMARTCTL_CMD -l farm "$DEVICE" | awk '/Power on Hours:/{print $4}' | head -n 1)

    # Check if FARM hours are available
    if [ -z "$FARM_HOURS" ]; then
        format_output_column "" "FARM data not available - likely not a Seagate drive"
        format_output_column "SMART" "$SMART_HOURS"
        format_output_column "FARM" "N/A"
        format_output_column "RESULT" "SKIP"
        echo
        return
    fi
    
    # Calculate absolute difference
    DIFF=$(( SMART_HOURS - FARM_HOURS ))
    ABS_DIFF=${DIFF#-}  # Remove negative sign
    
    # Determine result
    RESULT="FAIL"
    if [ $ABS_DIFF -le 1 ]; then
        RESULT="PASS"
    fi
    
    format_output_column "SMART" "$SMART_HOURS"
    format_output_column "FARM" "$FARM_HOURS"
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
