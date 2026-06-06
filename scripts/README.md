#
If you want, I can also produce `launchd` plist files instead of cron entries (recommended on macOS).

- The installer sets `ICLOUD_EVICT_ENABLE=0` by default in the crontab to avoid accidental mass-eviction. Enable it deliberately when you have verified reports.
- Eviction removes the local cached copies but keeps the data in iCloud. It can free local disk and iCloud "family" area usage if files are taking local space due to duplicates; verify reports before enabling automated eviction.
- `icloud_evict.sh` uses `brctl evict` which is a macOS private utility. It may not exist on all systems; the script checks and exits if `brctl` is missing.

Notes and safety:

  ```
  crontab -l
  ./scripts/install_cron.sh

```shellscript

```

```shellscript

- Install cron jobs (interactive):

```

# Evict files older than 90 days
  ICLOUD_EVICT_ENABLE=1 ./scripts/icloud_evict.sh 90

```shellscript

- Run eviction manually (non-interactive):

```

tail -n 200 ~/icloud-reports/report-*.txt
  ./scripts/icloud_report.sh

```shellscript

- Generate a report now:

Usage:

- `install_cron.sh` — interactive installer that appends safe cron entries for daily report, weekly eviction (disabled by default), and monthly cleanup summary.
- `cleanup_summary.sh` — a short summary of common caches (brew, pip, npm, Xcode). Writes to `~/icloud-reports/`.

  `0 4 * * 0 ICLOUD_EVICT_ENABLE=1 /path/to/icloud_evict.sh >> ~/icloud-reports/evict.log 2>&1`

- `icloud_evict.sh` — non-interactive eviction of iCloud local copies older than N days. **Disabled by default**. You must enable it by setting `ICLOUD_EVICT_ENABLE=1` in the crontab line (see below), e.g.
- `icloud_report.sh` — produce a timestamped report of iCloud usage and large files. Writes to `~/icloud-reports/`.

Files:

This directory contains helper scripts to inspect iCloud usage and optionally evict local copies.
```