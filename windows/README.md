# SMART/FARM Hours Comparison Tool

A PowerShell script that compares SMART and FARM Power-On-Hours for Seagate drives to verify data consistency.

## Prerequisites

- Windows operating system
- PowerShell
- Smartmontools installed (specifically smartctl.exe)
  - Default path: `C:\Program Files\smartmontools\bin\smartctl.exe`

## Installation

1. Download the script (`test-smart-device.ps1`)
2. Ensure Smartmontools is installed and `smartctl` path is set correctly
3. If Smartmontools is installed in a different location, update the `$smartctlPath` variable in the script

## Usage

```powershell
.\test-smart-device.ps1 <drive_letter> [drive_letter2 ...]
```

Example:

```powershell
.\test-smart-device.ps1 G:\ H:\
```

## Output Explanation

The script provides the following information for each drive:

- SMART Power-On-Hours value
- FARM Power-On-Hours value
- Result status:
  - PASS: Difference between SMART and FARM hours is ≤ 1
  - FAIL: Difference between SMART and FARM hours is > 1
  - SKIP: FARM data not available (non-Seagate drive or older Seagate Drives which dont support this)
  - ERROR: Error in calculation or data retrieval

Example output:

```
=== Checking device: G:\ ===
SMART: 5225
FARM: 5225
RESULT: PASS
```

## Error Handling

- Checks if smartctl.exe exists
- Validates drive existence
- Handles non-Seagate drives gracefully
- Includes error catching for integer conversions

## Limitations

- Only works with Seagate drives (some older seagate drives and other drives will be marked as SKIP)
- Requires administrative privileges to access SMART data
- Drive must be specified with correct path/letter format

## Troubleshooting

1. **"smartctl not found" error**

   - Verify Smartmontools is installed
   - Check if smartctl.exe is in the default path
   - Update `$smartctlPath` if installed in a different location

2. **"Access denied" error**

   - Run PowerShell as Administrator

3. **"FARM data not available" message**
   - Verify the drive is a Seagate drive
   - Ensure the drive supports FARM data reporting

## License

This script is provided "as is", without warranty of any kind.
