# Download smartmontools from https://www.smartmontools.org/
# Requires SmartMontools 7.4 or later https://sourceforge.net/projects/smartmontools/files/smartmontools/7.4/
# IMPORTANT - Must be run from an ADMINISTRATOR PowerShell session
# Usage example: .\test-farm-device.ps1

# Set smartctl path
$smartctlPath = "C:\Program Files\smartmontools\bin\smartctl.exe"

# Function to get non-NVMe drives
function Get-NonNVMeDrives {
    $scanOutput = & $smartctlPath --scan
    $drives = @()
    
    foreach ($line in $scanOutput) {
        if ($line -match '^(/dev/\w+)\s+-d\s+(\w+).*$') {
            $device = $matches[1]
            $type = $matches[2]
            
            if ($type -ne "nvme") {
                $drives += $device
            }
        }
    }
    return $drives
}


# Function to test a single Drive
function Test-SmartDrive {
    param (
        [string]$Drive
    )

    Write-Host "=== Checking Drive: $Drive ==="
    
    # Get SMART hours
    $smartOutput = & $smartctlPath -a $Drive
    $smartHours = ($smartOutput | Select-String "Power_On_Hours").ToString() -replace '.*\s(\d+)$', '$1'
    
    # Parse device model and serial number and print them
    $deviceModel = ($smartOutput | Select-String "Device Model:").ToString() -replace '.*:\s*', ''
    $serialNumber = ($smartOutput | Select-String "Serial Number:").ToString() -replace '.*:\s*', ''
    # Display device information
    Write-Host "Device Model: $deviceModel"
    Write-Host "Serial Number: $serialNumber"
    # Get FARM hours - now handling array output properly
    $farmOutput = & $smartctlPath -l farm $Drive
    $farmHoursLine = $farmOutput | Select-String "Power on Hours:" | Select-Object -First 1
    if ($farmHoursLine) {
        $farmHours = $farmHoursLine.ToString() -replace '.*:\s*(\d+).*', '$1'
    }
    else {
        $farmHours = $null
    }
    
    # Check if FARM hours are available
    if ([string]::IsNullOrEmpty($farmHours)) {
        Write-Host "FARM data not available - likely not a Seagate drive (or an unsupported model)." -ForegroundColor Yellow
        Write-Host "SMART: $smartHours"
        Write-Host "FARM: N/A"
        Write-Host "RESULT: SKIP"
        Write-Host ""
        return
    }
    
    Write-Host "SMART: $smartHours"
    Write-Host "FARM: $farmHours"
    
    try {
        # Convert strings to integers and calculate absolute difference
        $smartHoursInt = [long]$smartHours
        $farmHoursInt = [long]$farmHours
        $diff = [math]::Abs($smartHoursInt - $farmHoursInt)
        
        if ($diff -le 1) {
            Write-Host "RESULT: PASS"
        }
        else {
            Write-Host "RESULT: FAIL"
        }
    }
    catch {
        Write-Host "Error calculating difference: $_"
        Write-Host "RESULT: ERROR"
    }
    Write-Host ""
}

# Check if smartctl exists
if (-not (Test-Path $smartctlPath)) {
    Write-Host "Error: smartctl not found. Please install smartmontools."
    exit 1
}

# Get all non-NVMe drives and test them
$drives = Get-NonNVMeDrives
if ($drives.Count -eq 0) {
    Write-Host "No non-NVMe drives found."
    exit 0
}

Write-Host "Found $($drives.Count) non-NVMe drives to test..."
foreach ($drive in $drives) {
    Test-SmartDrive $drive
}