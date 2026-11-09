# srv-monitor

Monitoring server `srv-monitor` on a Raspberry Pi 5 with Raspberry Pi OS (Debian 13 trixie). Icinga 2 with Icinga DB, Icinga Web 2 and Icinga Director monitors the network. Docker (managed with Portainer) runs the internal CA `step-ca`, an OCR pipeline for PDFs (`ipa-ocr`), a verification worker (`lj-worker`) and a packet loss test server (`performance`).

State of this documentation: 2026-11-09, taken from a read-only inventory of the running host with [`inventory.sh`](docs/inventory-script.md). Secrets are replaced by `<redacted>`.

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
| `eth0` | 192.168.111.22/26 | 192.168.111.30 | 103 | preferred default route |
| `eth1` | 192.168.0.22/24 | 192.168.0.1 | 104 | second default route |
| `wlan0` | | | | down |
| `docker0` and `br-*` | 172.17.0.0/16 to 172.20.0.0/16 | | | Docker networks |

- DNS: 192.168.111.2, then 9.9.9.9 and 149.112.112.112. Search domains `kingma` and `home`.
- Time: `systemd-timesyncd` with `NTP=ntp.kingma` (see [`etc/systemd/timesyncd.conf`](etc/systemd/timesyncd.conf)), stratum 2, synchronized.
- Hostname `srv-monitor`, mDNS through `avahi-daemon`.
- Time zone `Europe/London`, locale `en_GB.UTF-8`, X11 layout `gb` (intl).

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
| 9000 | docker-proxy | all | step-ca |

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

| Component | Installed | Available |
|-----------|-----------|-----------|
| Kernel | 6.18.50+rpt-rpi-2712 | 6.18.60 |
| Icinga 2 | 2.16.5 | 2.16.6 |
| Icinga DB | 1.5.1 | 1.6.0 |
| Icinga DB Web | 1.4.0 | 1.5.0 |
| Icinga Web 2 | 2.14.0 | 2.14.1 |
| Icinga Director | 1.12.1 | |
| MariaDB | 11.8.6 | |
| PHP | 8.4.27 (Apache `mod_php`, `mpm_prefork`) | |
| Docker | 29.9.2 | 29.9.3 |

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

State of 2026-11-09.

| Issue | Detail |
|-------|--------|
| `icingadb.service` failed | Down since 2026-10-22. MariaDB rejects the user `icingadb`: `Error 1045 Access denied for user 'icingadb'@'localhost' (using password: YES)`. The password in `/etc/icingadb/config.yml` does not match the database. Without Icinga DB the Icinga DB Web module has no data. |
| Redis on 6380 read-only | `redis-cli -p 6380 ping` answers `MISCONF`: Redis cannot persist RDB snapshots and refuses writes. Cause is not yet identified (log: `/var/log/redis/redis-icingadb.log`, directory `/var/lib/icingadb-redis`). |
| `performance` stack not started | `openpacketloss` is in state `Created`. The stack publishes `9000:80`, but port 9000 is taken by `step-ca`. The container was also created with `NAT_1TO1_IP=192.168.0.15`, while the stack file says `192.168.1.12`. |
| `cert-renewer@.service` unused | The template exists, but there is no instance, no timer, and neither `/etc/step` nor `/etc/step-ca`. `step-ca` itself runs as a container with `restart=no`. |
| Updates pending | 35 packages (kernel, Docker, Icinga packages and others) and a bootloader EEPROM update. |
| Locale and time zone | `Europe/London` and `en_GB` on a host in Switzerland. |
| `auto-update` inactive | See above. If it is made executable, the host reboots every day after the upgrade. |

## Files that differ from the package defaults

`/etc/skel/.bashrc`, `/etc/login.defs`, `/etc/default/useradd`, `/etc/avahi/avahi-daemon.conf`, `/etc/initramfs-tools/initramfs.conf`, `/etc/systemd/timesyncd.conf`, `/etc/icinga2/constants.conf` and `/etc/icinga2/features-available/icingadb.conf`. The first five are not mirrored here.

## Inventory

`inventory.sh` rebuilds the data this documentation is based on. See [docs/inventory-script.md](docs/inventory-script.md).
