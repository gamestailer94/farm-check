#!/bin/sh

if [ $# -eq 0 ]; then
    echo "Usage: $0 <block_device>"
    exit 1
fi

DEVICE=$1

if ! command -v smartctl &> /dev/null; then
    echo "Error: smartctl not found. Please install smartmontools."
    exit 1
fi

SMART_HOURS=$(smartctl -a "$DEVICE" | awk '/Power_On_Hours/{print $10}' | head -n 1)
FARM_HOURS=$(smartctl -l farm "$DEVICE" | awk '/Power on Hours:/{print $4}' | head -n 1)

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