# Seagate HDD Farm Check

A tool to detect potentially fraudulent hard drives by comparing SMART and FARM power-on hours, as highlighted in the [possible Seagate hard disk fraud investigation reported by heise](https://www.heise.de/en/news/Fraud-with-Seagate-hard-disks-Dozens-of-readers-report-suspected-cases-10259237.html).

**IMPORTANT**: This tool is specifically designed for Seagate hard drives only. While it can read basic SMART data from any drive, the tool is practically useless for non-Seagate drives as the core FARM verification functionality is exclusively available for Seagate drives. Non-Seagate drives will be skipped during verification.

## Background

Recent reports have revealed cases of used Seagate hard drives being sold as new. This tool helps identify such cases by comparing two different power-on hour counters that are specific to Seagate drives:
- SMART Power-On Hours: The standard SMART attribute tracking total power-on time
- FARM Power-On Hours: A separate counter in Seagate's proprietary FARM log

In legitimate new Seagate drives, these values should be nearly identical. A significant difference between these counters may indicate a used drive being sold as new.

## Installation & Usage

### Standalone Usage

#### Requirements
- Linux system
- smartmontools version 7.4 or higher
- Root/admin privileges (needed for SMART access)

#### Installation
Install smartmontools (version ≥ 7.4):
```bash
# Ubuntu/Debian
apt-get update && apt-get install smartmontools

# Fedora
dnf install smartmontools
```

#### Running the Check
```bash
chmod +x check.sh
# Check a single drive
sudo ./check.sh /dev/sdX

# Check multiple drives
sudo ./check.sh /dev/sda /dev/sdb

# Check all drives
sudo ./check.sh ALL
```
Replace `/dev/sdX` with your drive's device path (e.g., `/dev/sda`).

### Docker Usage

#### Requirements
- Docker
- Root/admin privileges

#### Using Pre-built Image
```bash
docker pull ghcr.io/gamestailer94/farm-check:latest
# Check a single drive
docker run --rm --privileged -v /dev:/dev ghcr.io/gamestailer94/farm-check:latest /dev/sdX

# Check multiple drives
docker run --rm --privileged -v /dev:/dev ghcr.io/gamestailer94/farm-check:latest /dev/sda /dev/sdb

# Check all drives
docker run --rm --privileged -v /dev:/dev ghcr.io/gamestailer94/farm-check:latest ALL
```
Replace `/dev/sdX` with your drive's device path (e.g., `/dev/sda`).

#### Building Locally
```bash
git clone https://github.com/gamestailer94/farm-check.git
cd farm-check
docker build -t farm-check .
docker run --rm --privileged -v /dev:/dev farm-check /dev/sdX
```

## Output

The tool outputs:
- Device: Name of the device being checked
- SMART: Power-on hours from SMART attributes
- FARM: Power-on hours from Seagate FARM log (N/A for non-Seagate drives)
- RESULT: 
  - PASS: If the difference between SMART and FARM hours is ≤ 1
  - FAIL: If the difference is > 1, suggesting potential fraud
  - SKIP: If the drive is not a Seagate drive (no FARM data available)

## How it Works

1. Uses smartmontools to read both SMART and FARM power-on hour values
2. Detects if the drive is a Seagate drive by checking for FARM data
3. For Seagate drives:
   - Calculates the absolute difference between SMART and FARM values
   - Reports PASS if the difference is 1 hour or less
   - Reports FAIL if the difference is greater, indicating possible tampering
4. For non-Seagate drives:
   - Reports SKIP as FARM data is not available
   - Still displays SMART hours for reference

## Windows Implementation

### System Requirements

- Windows 10 or later
- PowerShell 5.1 or PowerShell Core 7.x
- Smartmontools for Windows (v7.4 or later)
- Administrator privileges

### Installation & Setup

1. Download and install Smartmontools from the official website:
   - [Smartmontools for Windows](https://www.smartmontools.org/wiki/Download#InstalltheWindowspackage)
   - Default installation path: `C:\Program Files\smartmontools\`

2. Download the PowerShell script from the `windows` directory
3. Run PowerShell as Administrator
4. Enable script execution if needed:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

For detailed instructions and usage examples, refer to the [Windows Documentation](./windows/README.md).

## Security Warning

⚠️ **IMPORTANT SECURITY NOTICE** ⚠️

Both standalone and Docker methods require root/admin privileges to read SMART data from drives. The Docker container requires `--privileged` access, which gives the container full access to all devices on your host system. This is a significant security risk if misused.

**NEVER run untrusted containers with --privileged access!** This gives the container complete control over your host system, including:
- Full access to all devices and drives
- Ability to modify system settings
- Potential to compromise your entire system

Only run this tool:
- On systems you fully trust and control
- With containers you've built yourself or obtained from verified sources
- When you understand the security implications of privileged access

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
````
