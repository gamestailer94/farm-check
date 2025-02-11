#!/usr/bin/env bash

colors=(
    "\e[0m"  # 0 - Reset
    "\e[31m" # 1 - Red
    "\e[32m" # 2 - Green
)

if [[ ${#} -eq 0 ]]; then
    echo "Usage: $0 <block_device> [block_device2 ...]"
    echo "       Use ALL to automatically check all block devices"
    exit 1
fi

if ! command -v smartctl &> /dev/null; then
    echo "Error: smartctl not found. Please install smartmontools."
    exit 1
fi

function check_vendor {
    local device="${1}"
    
    # Skip if device doesn't exist
    if [[ ! -e "${device}" ]]; then
        return 1
    fi
    
    # Skip if not a block device
    if [[ ! -b "${device}" ]]; then
        return 1
    fi
    
    vendor="$(<"/sys/block/${device##*/}/device/vendor")"
    vendor="${vendor// /}"
    if ! [[ "${vendor}" == "SEAGATE" ]]; then
        echo "Device [${device}] does not appear to be a Seagate drive"
        return 1
    fi
}

function check_device {
    local device="${1}"
    
    echo "=== Checking device: ${device} ==="
    
    while read -r smart_hours; do
        if [[ "${smart_hours}" =~ ^.*"Accumulated power on time, hours:minutes".*$ ]]; then
            smart_hours="${smart_hours##* }"
            smart_hours="${smart_hours%:*}"
            break
        fi
    done < <(smartctl -a "${device}")
    while read -r farm_hours; do
        if [[ "${farm_hours}" =~ ^.*"Power on Hour".*$ ]]; then
            farm_hours="${farm_hours##* }"
            break
        fi
    done < <(smartctl -l farm "${device}")
    
    # Check if SMART hours are available
    if [[ -z "${smart_hours}" ]]; then
        echo "Unable to retrieve SMART hours for device [${device}]"
        return 0
    fi
    # Check if FARM hours are available
    if [[ -z "${farm_hours}" ]]; then
        echo "Unable to retrieve FARM hours for device [${device}]"
        return 0
    fi
    
    echo "SMART hours reported: ${smart_hours}"
    echo "FARM hours reported:  ${farm_hours}"
    
    # Calculate absolute difference
    diff=$(( smart_hours - farm_hours ))
    abs_diff=${diff#-}  # Remove negative sign
    
    if [[ "${abs_diff}" -le "1" ]]; then
        echo -e "Device check:         ${colors[2]}PASS${colors[0]}"
    else
        echo -e "Device check:         ${colors[1]}FAIL${colors[0]}"
    fi
    echo
}

# Handle ALL case
if [[ "${1^^}" = "ALL" ]]; then
    # /dev/sd* block devices
    for device in /dev/sd*; do
        # Skip partition devices (e.g., /dev/sda1)
        if [[ "${device}" =~ /dev/sd[a-z]$ ]]; then
            if check_vendor "${device}"; then
                list+=("${device}")
            fi
        fi
    done

    # Synology /dev/sata* block devices
    for device in /dev/sata*; do
        # Skip partition devices (e.g., /dev/sata1p1)
        if [[ "${device}" =~ ^/dev/sata[0-9]+$ ]]; then
            if check_vendor "${device}"; then
                list+=("${device}")
            fi
        fi
    done

    # Synology /dev/sas* block devices
    for device in /dev/sas*; do
        # Skip partition devices (e.g., /dev/sas1p1)
        if [[ "${device}"  =~ ^/dev/sas[0-9]+$ ]]; then
            if check_vendor "${device}"; then
                list+=("${device}")
            fi
        fi
    done
else
    # Handle explicit device arguments
    for device in "${@}"; do
        if check_vendor "${device}"; then
            list+=("${device}")
        fi
    done
fi

for device in "${list[@]}"; do
    check_device "${device}"
done

exit 0
