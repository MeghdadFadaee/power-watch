# Power-Watch: Safe Shutdown on Mains Outage

## Idea & Motivation

This script is designed for home servers running on Ubuntu Desktop (or
any Linux distribution with `systemd`).\
The main goal is to **safely shutdown the system when mains power is
lost** and the server is running on a UPS,\
but only after a configurable delay (e.g., 20 minutes).

Why?\
- UPS can keep the server alive for some time (e.g., 20 minutes).\
- We want to prevent data loss by shutting down before the UPS battery
is fully drained.\
- However, if a user is actively working on the machine, we **do not
want** to shutdown.

Thus the script combines two checks: 1. **Detect power outage** → by
checking if the home modem/router (plugged into mains, not UPS) is
offline.\
2. **Check user activity** → if a user session is active and not idle,
skip shutdown.

------------------------------------------------------------------------

## How It Works

-   The script pings your modem's IP address.
    -   If the modem is unreachable, it assumes mains power is down.\
-   It keeps a counter of consecutive failed checks.\
-   Once the outage lasts longer than the configured threshold (e.g., 20
    minutes), it prepares to shutdown.\
-   Before shutting down, it checks `systemd-logind` to ensure no active
    user session is in use.\
-   If no one is active → the server shuts down via
    `systemctl poweroff`.

------------------------------------------------------------------------

## Setup Instructions

### 1. Install the script

Save the script into `/usr/local/sbin/power-watch.sh` and make it
executable:

``` bash
sudo install -m 755 -o root -g root power-watch.sh /usr/local/sbin/power-watch.sh
sudo mkdir -p /var/lib/power-watch
sudo chmod 700 /var/lib/power-watch
```

### 2. Configure systemd service & timer

Create `/etc/systemd/system/power-watch.service`:

``` ini
[Unit]
Description=Detect mains outage via modem reachability and shutdown safely
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/power-watch.sh
SyslogIdentifier=power-watch
User=root
Group=root
```

Create `/etc/systemd/system/power-watch.timer`:

``` ini
[Unit]
Description=Run power-watch every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=5s
Unit=power-watch.service
Persistent=true

[Install]
WantedBy=timers.target
```

Enable & start:

``` bash
sudo systemctl daemon-reload
sudo systemctl enable --now power-watch.timer
```

Check status:

``` bash
systemctl status power-watch.timer
journalctl -u power-watch.service -f
```

### 3. Optional: Using cron instead of systemd

``` bash
sudo crontab -e
```

Add:

    * * * * * /usr/local/sbin/power-watch.sh >/dev/null 2>&1

------------------------------------------------------------------------

## Configuration

Inside the script you can adjust: - `MODEM_IP="192.168.1.1"` → your
modem/router IP (must be powered by mains).\
- `OUTAGE_MINUTES=20` → how long the outage must persist before
shutdown.\
- `CHECK_INTERVAL=60` → interval between checks (in seconds).\
- `EXTRA_PROBE="1.1.1.1"` → optional extra internet ping (can set empty
string if not needed).

------------------------------------------------------------------------

## Notes

-   The modem **must not** be powered by UPS, otherwise the outage won't
    be detected.\
-   User activity detection uses `systemd-logind`. If any active
    non-idle session exists, shutdown is postponed.\
-   If your UPS has USB/LAN interface, consider using **NUT** or
    **apcupsd** for more reliable monitoring.

------------------------------------------------------------------------

## License

MIT License
