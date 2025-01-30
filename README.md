# HDD Farm Check

A tool to detect potentially fraudulent hard drives by comparing SMART and FARM power-on hours, as highlighted in the [Seagate HDD scandal](https://www.heise.de/en/news/Fraud-with-Seagate-hard-disks-Dozens-of-readers-report-suspected-cases-10259237.html).

## Background

Recent reports have revealed cases of used Seagate hard drives being sold as new. This tool helps identify such cases by comparing two different power-on hour counters:
- SMART Power-On Hours: The standard SMART attribute tracking total power-on time
- FARM Power-On Hours: A separate counter in Seagate's FARM log

In legitimate new drives, these values should be nearly identical. A significant difference between these counters may indicate a used drive being sold as new.

## Installation & Usage

### Standalone Usage

#### Requirements
- Linux system
- smartmontools version 7.4 or higher
- Root/admin privileges (needed for SMART access)
- A Seagate hard drive to check

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
sudo ./check.sh /dev/sdX
```
Replace `/dev/sdX` with your drive's device path (e.g., `/dev/sda`).

### Docker Usage

#### Requirements
- Docker
- Root/admin privileges
- A Seagate hard drive to check

#### Using Pre-built Image
```bash
docker pull ghcr.io/gamestailer94/farm-check:latest
docker run --privileged -v /dev:/dev ghcr.io/gamestailer94/farm-check:latest /dev/sdX
```
Replace `/dev/sdX` with your drive's device path (e.g., `/dev/sda`).

#### Building Locally
```bash
git clone https://github.com/gamestailer94/farm-check.git
cd farm-check
docker build -t farm-check .
docker run --privileged -v /dev:/dev farm-check /dev/sdX
```

## Output

The tool outputs:
- SMART: Power-on hours from SMART attributes
- FARM: Power-on hours from Seagate FARM log
- RESULT: 
  - PASS: If the difference between SMART and FARM hours is ≤ 1
  - FAIL: If the difference is > 1, suggesting potential fraud

## How it Works

1. Uses smartmontools to read both SMART and FARM power-on hour values
2. Calculates the absolute difference between these values
3. Reports PASS if the difference is 1 hour or less
4. Reports FAIL if the difference is greater, indicating possible tampering

## Security Note

Both standalone and Docker methods require root/admin privileges to read SMART data from drives. Only run this tool on systems you trust and control. The Docker container requires `--privileged` access.

## Disclaimer

This tool is provided as-is for informational purposes. Always purchase storage devices from reputable sources and validate warranty status through official channels.