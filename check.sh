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

    FAMILY=$($SMARTCTL_CMD -a "$DEVICE" | grep 'Model Family')
    if [ -z "$FAMILY" ]; then
        FAMILY="Model Family: N/A (smartmontools does not know this device or device does not report Model Family)"
    fi
    MODLE=$($SMARTCTL_CMD -a "$DEVICE" | grep 'Device Model')
    if [ -z "$MODLE" ]; then
        MODLE="Device Model: N/A (smartmontools does not know this device or device does not report Device Model)"
    fi
    SERIAL=$($SMARTCTL_CMD -a "$DEVICE" | grep 'Serial Number')
    if [ -z "$SERIAL" ]; then
        SERIAL="Serial Number: N/A (smartmontools does not know this device or device does not report Serial Number)"
    fi
    
    echo "$FAMILY"
    echo "$MODLE"
    echo "$SERIAL"

    SMART_HOURS=$($SMARTCTL_CMD -a "$DEVICE" | awk '/Power_On_Hours/{print $10}' | head -n 1)
    FARM_HOURS=$($SMARTCTL_CMD -l farm "$DEVICE" | awk '/Power on Hours:/{print $4}' | head -n 1)

    # Check if FARM hours are available
    if [ -z "$FARM_HOURS" ]; then
        echo "FARM data not available - likely not a Seagate drive"
        echo "SMART: $SMART_HOURS"
        echo "FARM: N/A"
        echo "RESULT: SKIP"
        echo
        return
    fi
    
    echo "SMART: $SMART_HOURS"
    echo "FARM: $FARM_HOURS"
    
    # Calculate absolute difference
    DIFF=$(( SMART_HOURS - FARM_HOURS ))
    ABS_DIFF=${DIFF#-}  # Remove negative sign
    
    if [ $ABS_DIFF -le 1 ]; then
        echo "RESULT: PASS"
    else
        echo "RESULT: FAIL"
    fi
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
