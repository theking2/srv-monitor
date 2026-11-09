# srv-monitor

Monitoring server `srv-monitor` on a Raspberry Pi 5 with Raspberry Pi OS (Debian 13 trixie). Icinga 2 with Icinga DB, Icinga Web 2 and Icinga Director monitors the network. Docker (managed with Portainer) runs the internal CA `step-ca`, an OCR pipeline for PDFs (`ipa-ocr`), a verification worker (`lj-worker`) and a packet loss test server (`performance`).

State of this documentation: 2026-11-09 18:35 CET, taken from a read-only inventory of the running host (3 minutes after a reboot) with [`inventory.sh`](docs/inventory-script.md). Secrets are replaced by `<redacted>`.

## Hardware

- Raspberry Pi 5 Model B Rev 1.0, 4 GB RAM, bootloader EEPROM of 2025-05-08 (update available)
- NVMe SSD SK900-256GB (SM2263XT controller) on the PCIe port
- Second network adapter on USB: ASIX AX88179 gigabit (`eth1`, assumed from `lsusb`, the only USB NIC)
- Bluetooth and WiFi (`wlan0`) are present, WiFi is down

### Disk

| Device | Size | FS | Mount |
|--------|------|----|-------|
| `nvme0n1p1` | 512M | vfat (`bootfs`) | `/boot/firmware` |
| `nvme0n1p2` | 238G | ext4 (`rootfs`, `noatime`) | `/` |

Swap is a 2 GB zram device (`/dev/zram0`, priority 100). Used: 9.4 GB of 235 GB.

### Boot configuration

[`config.txt`](config.txt) and [`cmdline.txt`](cmdline.txt) are the stock Raspberry Pi OS files. Nothing is added for the NVMe disk.

## Network

Two wired interfaces, both DHCP through NetworkManager (`Wired connection 1` and `2`). `systemd-networkd` is running, but reports all links as unmanaged, so `/etc/systemd/network/20-wired.network` (`DHCP=yes`) is not in effect.

| Interface | Address | Gateway | Metric | Notes |
|-----------|---------|---------|--------|-------|
| `eth0` | 192.168.111.22/26 | 192.168.111.30 | 101 | second default route |
| `eth1` | 192.168.0.22/24 | 192.168.0.1 | 100 | preferred default route |
| `wlan0` | | | | down |
| `docker0` and `br-*` | 172.17.0.0/16 to 172.20.0.0/16 | | | Docker networks |

- DNS: 9.9.9.9, 149.112.112.112, then 192.168.111.2. Search domains `home` and `kingma`.
- Time: `systemd-timesyncd` with `NTP=ntp.kingma` (see [`etc/systemd/timesyncd.conf`](etc/systemd/timesyncd.conf)).
- Hostname `srv-monitor`, mDNS through `avahi-daemon`.
- Time zone `Europe/Zurich`, locale `en_GB.UTF-8`, X11 layout `gb` (intl).

Until the reboot of 2026-11-09 the order was the other way round: `eth0` metric 103 before `eth1` metric 104, and the internal DNS server 192.168.111.2 first. NetworkManager assigns the metrics (`Wired connection 1` is `eth0`, `Wired connection 2` is `eth1`), the DNS order follows them. See [open issues](#open-issues).

### Listening ports

| Port | Process | Bound to | Purpose |
|------|---------|----------|---------|
| 22 | sshd | all | SSH |
| 80 | apache2 | all | Icinga Web 2 at `/icingaweb2`, default page in `/var/www/html` |
| 111 | rpcbind | all | RPC portmapper |
| 3306 | mariadbd | 127.0.0.1 | MariaDB |
| 5353 | avahi-daemon | all | mDNS |
| 5665 | icinga2 | all | Icinga 2 API |
| 6379 | redis-server | 127.0.0.1, ::1 | Redis (general) |
| 6380 | redis-server | all | Redis for Icinga DB |
| 8000, 9443 | docker-proxy | all | Portainer (edge agent, UI over HTTPS) |
| 9000 | docker-proxy | all | step-ca (only while the container runs, see [open issues](#open-issues)) |

## Access

One administrative account in the groups `sudo`, `docker`, `adm`, `video`, `gpio`, `i2c`, `spi`, `dialout` and `plugdev`, with login by SSH key. `sudoers` is the Debian default.

## Software

Repositories: Debian trixie (main, contrib, non-free, non-free-firmware, with updates and security), Raspberry Pi (`archive.raspberrypi.com`), Docker CE, Smallstep, Icinga (`icinga-trixie`).

Installed by hand (from the apt history):

| Area | Packages |
|------|----------|
| Icinga | `icinga2`, `icingacli`, `icingadb`, `icingadb-redis`, `icingadb-web`, `icingaweb2`, `icinga-director`, `monitoring-plugins` |
| Database and cache | `mariadb-server`, `redis-server` |
| Containers | `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-compose-plugin`, `docker-ce-rootless-extras`, `docker-buildx-plugin`, `docker-model-plugin` |
| PKI | `step-cli` (`/usr/local/bin/step` links to it) |
| Tools | `rclone`, `poppler-utils`, `btop`, `fastfetch`, `raspi-config` |

`/usr/local/bin` also holds Redis binaries (`redis-server`, `redis-cli`, `redis-benchmark`, dated 2 August 2026) that are not managed by apt.

### Versions

| Component | Installed | |
|-----------|-----------|---|
| Kernel (running) | 6.18.50+rpt-rpi-2712 | |
| Icinga 2 | 2.16.6 | |
| Icinga DB | 1.6.0 | |
| Icinga DB Web | 1.5.0 | |
| Icinga Web 2 | 2.14.1 | |
| Icinga Director | 1.12.1 | |
| MariaDB | 11.8.6 | |
| PHP | 8.4.27 (Apache `mod_php`, `mpm_prefork`) | |
| Docker | 29.9.3 | |

## Icinga

Single node: `NodeName` and `ZoneName` are both `srv-monitor`. The configuration lives in [`icinga/`](icinga):

| File | Content |
|------|---------|
| `icinga2/constants.conf` | `NodeName` and `ZoneName` set to `srv-monitor`; `TicketSalt` is empty |
| `icinga2/zones.conf` | zones `srv-monitor`, `global-templates`, `director-global` |
| `icinga2/conf.d/api-users.conf` | API user for Icinga DB Web |
| `icinga2/features-available/icingadb.conf` | Icinga DB feature, Redis on `127.0.0.1:6380` |
| `icingadb/config.yml` | Icinga DB daemon: MariaDB on `localhost`, Redis on `localhost` |
| `icingaweb2/` | resources (databases `icingaweb2`, `icingadb`, `director`), DB authentication, modules `icingadb` and `director` |
| `redis/redis-icingadb.conf` | second Redis instance on port 6380 |

- Enabled features: `api`, `checker`, `icingadb`, `mainlog`, `notification`.
- The configuration validates (`icinga2 daemon -C`): 1 host, 12 services, 13 notifications, 250 check commands.
- Icinga Web 2 stores its configuration, authentication and the Director in MariaDB. Databases: `icingaweb2`, `icingadb`, `director` (194 MB in `/var/lib/mysql`).
- `icinga-director.service` runs the Director daemon.
- `icingadb-redis.service` is a hand-made unit, see [`systemd/`](systemd).

## Containers

See [`containers/`](containers/README.md). Portainer manages three stacks and runs next to a standalone `step-ca`.

## Scheduled jobs

Systemd timers: `apt-daily`, `apt-daily-upgrade`, `dpkg-db-backup`, `e2scrub_all`, `fstrim`, `logrotate`, `man-db`, `phpsessionclean`, `rpi-zram-writeback`. There are no user crontabs.

[`etc/cron.daily/auto-update`](etc/cron.daily/auto-update) runs `apt-get upgrade -y` and then `reboot`. The file is not executable (`-rw-r--r--`), so `run-parts` skips it and it is inactive.

## Open issues

State of 2026-11-09, 18:35 CET.

| Issue | Detail |
|-------|--------|
| `icingadb.service` does not start | Line 1 of `/etc/icingadb/config.yml` on the host begins with the text `vim -r /etc/icingadb/config.yml` in front of the comment, so the YAML is invalid: `can't parse YAML file /etc/icingadb/config.yml: [1:1] unexpected key name`. The copy in [`icinga/icingadb/config.yml`](icinga/icingadb/config.yml) has this prefix removed. Before the edit the service failed since 2026-10-22 with `Error 1045 Access denied for user 'icingadb'@'localhost'`. Whether the database password in the file matches MariaDB is not yet known, because the daemon does not get that far. The same password is used in `/etc/icingaweb2/resources.ini` (resource `icingadb`). |
| `step-ca` is stopped | The container has `restart=no` and exited on the reboot (`Exited (0)`), so port 9000 is not served and the internal CA is offline. |
| Default route and DNS order | After the reboot NetworkManager ranks `eth1` (metric 100) before `eth0` (101), and `/etc/resolv.conf` lists the public resolvers before the internal one (192.168.111.2). |
| Time not synchronized | `timedatectl` reports `System clock synchronized: no`, and `timesync-status` shows `Server: n/a (ntp.kingma)` with 0 packets. Probably a consequence of the DNS order above: `ntp.kingma` is an internal name. Not verified: the host had been up for 3 minutes. |
| `performance` stack not started | `openpacketloss` is in state `Created`. The stack publishes `9000:80`, which is the port of `step-ca`. The container was also created with `NAT_1TO1_IP=192.168.0.15`, while the stack file says `192.168.1.12`. |
| `cert-renewer@.service` unused | The template exists, but there is no instance, no timer, and neither `/etc/step` nor `/etc/step-ca`. |
| Bootloader update | EEPROM of 2025-05-08, version of 2026-10-30 available (`rpi-eeprom-update`). |
| `auto-update` inactive | [`etc/cron.daily/auto-update`](etc/cron.daily/auto-update) is not executable. If it is made executable, the host reboots every day after the upgrade. |

Solved on 2026-11-09: Redis on port 6380 answered `MISCONF` before the reboot and answers `PONG` since; time zone changed from `Europe/London` to `Europe/Zurich`; all pending package updates installed (Icinga 2.16.6, Icinga DB 1.6.0, Docker 29.9.3).

## Files that differ from the package defaults

`/etc/skel/.bashrc`, `/etc/login.defs`, `/etc/default/useradd`, `/etc/avahi/avahi-daemon.conf`, `/etc/initramfs-tools/initramfs.conf`, `/etc/systemd/timesyncd.conf`, `/etc/icinga2/constants.conf` and `/etc/icinga2/features-available/icingadb.conf`. The first five are not mirrored here.

## Inventory

`inventory.sh` rebuilds the data this documentation is based on. See [docs/inventory-script.md](docs/inventory-script.md).
