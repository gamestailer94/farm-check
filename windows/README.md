# Seagate Drive SMART/FARM Verification Tool

A PowerShell script for detecting potentially fraudulent Seagate drives by comparing SMART and FARM Power-On-Hours counters.

## Prerequisites

- Windows 10 or later
- PowerShell 5.1 or PowerShell Core 7.x
- Smartmontools v7.4 or later
  - Download from: [Smartmontools for Windows](https://www.smartmontools.org/wiki/Download#InstalltheWindowspackage)
  - Default path: `C:\Program Files\smartmontools\bin\smartctl.exe`
- Administrator privileges

## Installation

1. Install Smartmontools for Windows
2. Download `test-smart-device.ps1` to your preferred location
3. Open PowerShell as Administrator
4. Enable script execution (if needed):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

## Usage

The script automatically detects and tests all non-NVMe drives in the system:

```powershell
.\test-smart-device.ps1
```

## Output Format

For each drive, the script displays:

- Device path/identifier
- Device Model
- Serial Number
- SMART Power-On-Hours value
- FARM Power-On-Hours value
- Test result:
  - PASS: Difference between SMART and FARM hours ≤ 1
  - FAIL: Difference > 1 (potential fraud indicator)
  - SKIP: Non-Seagate drive or FARM data unavailable
  - ERROR: Data retrieval/calculation error

Example output:
```
=== Checking Drive: /dev/sda ===
Device Model: ST4000DM004-2CV104
Serial Number: ZFN2ABCD
SMART: 5225
FARM: 5225
RESULT: PASS

=== Checking Drive: /dev/sdb ===
Device Model: WD40EFAX-68JH4N0
Serial Number: 2GHJA9BC
FARM data not available - likely not a Seagate drive (or an unsupported model).
SMART: 1205
FARM: N/A
RESULT: SKIP
```

## Troubleshooting

### Common Issues

1. **"smartctl not found" error**
   - Verify Smartmontools installation
   - Check installation path: `C:\Program Files\smartmontools\bin\smartctl.exe`
   - If installed elsewhere, modify `$smartctlPath` in the script

2. **Access Denied Errors**
   - Ensure PowerShell is running as Administrator
   - Verify drive permissions
   - Check if another process is locking the drive

3. **"FARM data not available" Message**
   - Expected for non-Seagate drives
   - Some older Seagate models don't support FARM
   - Verify drive is a supported Seagate model

4. **No Drives Found**
   - Script only detects non-NVMe drives
   - Verify drives are visible in Disk Management
   - Check if drives require special drivers

## Security Notice

⚠️ This script requires administrator privileges to:
- Access SMART data
- Read FARM data
- Scan system drives

Only run this script on trusted systems and verify script contents before execution.

## Support

This tool specifically targets Seagate drives and relies on:
- SMART data availability
- FARM data support (Seagate-specific)
- Administrator access
- Smartmontools v7.4+ compatibility

## License

This script is provided "as is", without warranty of any kind. Use at your own risk.
