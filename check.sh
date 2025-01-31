#!/bin/sh

if [ $# -eq 0 ]; then
    echo "Usage: $0 <block_device> [block_device2 ...]"
    echo "       Use ALL to automatically check all block devices"
    exit 1
fi

if ! command -v smartctl &> /dev/null; then
    echo "Error: smartctl not found. Please install smartmontools."
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
    
    SMART_HOURS=$(smartctl -a "$DEVICE" | awk '/Power_On_Hours/{print $10}' | head -n 1)
    FARM_HOURS=$(smartctl -l farm "$DEVICE" | awk '/Power on Hours:/{print $4}' | head -n 1)
    
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
