# Download smartmontools from https://www.smartmontools.org/
# Requires SmartMontools 7.4 or later https://sourceforge.net/projects/smartmontools/files/smartmontools/7.4/
# IMPORTANT - Must be run from an ADMINISTRATOR PowerShell session
# Usage: .\test-smart-device.ps1 G:\ H:\

# Set smartctl path
$smartctlPath = "C:\Program Files\smartmontools\bin\smartctl.exe"

# Function to test a single Drive
function Test-SmartDrive {
    param (
        [string]$Drive
    )
    
    # Skip if Drive doesn't exist
    if (-not (Test-Path $Drive)) {
        return
    }

    Write-Host "=== Checking Drive: $Drive ==="
    
    # Get SMART hours
    $smartOutput = & $smartctlPath -a $Drive
    $smartHours = ($smartOutput | Select-String "Power_On_Hours").ToString() -replace '.*\s(\d+)$', '$1'
    
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
        Write-Host "FARM data not available - likely not a Seagate drive"
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
        $smartHoursInt = [int]$smartHours
        $farmHoursInt = [int]$farmHours
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

# Check if no arguments provided
if ($args.Count -eq 0) {
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) <physical_drive> [physical_drive2 ...]"
    exit 1
}

# Handle Drive arguments
foreach ($Drive in $args) {
    Test-SmartDrive $Drive
}