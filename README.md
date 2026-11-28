# srv-monitor

Monitoring server `srv-monitor` on a Raspberry Pi 5 with Raspberry Pi OS (Debian 13 trixie). Icinga 2 with Icinga DB, Icinga Web 2 and Icinga Director monitors the network. Docker (managed with Portainer) runs the internal CA `step-ca`, an OCR pipeline for PDFs (`ipa-ocr`), a verification worker (`lj-worker`) and a packet loss test server (`performance`).

State of this documentation: 2026-11-10 07:45 CET, based on read-only inventories of the running host (last full inventory 2026-11-09 20:22, after a reboot) and the repairs of 2026-11-10 with [`inventory.sh`](docs/inventory-script.md). Secrets are replaced by `<redacted>`.

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

[`config.txt`](config.txt) is the stock Raspberry Pi OS file; nothing is added for the NVMe disk. [`cmdline.txt`](cmdline.txt) is stock plus `cgroup_enable=memory` (2026-11-28), so Docker can enforce memory limits.

## Network

Two wired interfaces, both DHCP through NetworkManager (`Wired connection 1` and `2`). `systemd-networkd` is running, but reports all links as unmanaged, so `/etc/systemd/network/20-wired.network` (`DHCP=yes`) is not in effect.

| Interface | Address | Gateway | Metric | Notes |
|-----------|---------|---------|--------|-------|
| `eth0` | 192.168.111.22/26 | 192.168.111.30 | 100 | preferred default route |
| `eth1` | 192.168.0.22/24 | 192.168.0.1 | 200 | second default route |
| `wlan0` | | | | down |
| `docker0` and `br-*` | 172.17.0.0/16 to 172.20.0.0/16 | | | Docker networks |

- DNS: 192.168.111.2, then 9.9.9.9 and 149.112.112.112. Search domains `home` and `kingma`.
- Time: `systemd-timesyncd` with `NTP=ntp.kingma`, synchronized (see [`etc/systemd/timesyncd.conf`](etc/systemd/timesyncd.conf)).
- Hostname `srv-monitor`, mDNS through `avahi-daemon`.
- Time zone `Europe/Zurich`, locale `en_GB.UTF-8`, X11 layout `gb` (intl).

The metrics are pinned in the NetworkManager profiles `eth0` and `eth1` (`nmcli con mod <profile> ipv4.route-metric <n>`), so the order survives a reboot.

### Listening ports

| Port | Process | Bound to | Purpose |
|------|---------|----------|---------|
| 22 | sshd | all | SSH |
| 80 | apache2 | all | Icinga Web 2 at `/icingaweb2`; `/` redirects there ([`icingaweb2-root-redirect.conf`](etc/apache2/conf-available/icingaweb2-root-redirect.conf)), so `http://srv-monitor/` and `monitor.kingma.ch` open Icinga Web |
| 111 | rpcbind | all | RPC portmapper |
| 3306 | mariadbd | 127.0.0.1 | MariaDB |
| 5353 | avahi-daemon | all | mDNS |
| 5665 | icinga2 | all | Icinga 2 API |
| 6379 | redis-server | 127.0.0.1, ::1 | Redis (general) |
| 6380 | redis-server | all | Redis for Icinga DB |
| 8000, 9443 | docker-proxy | all | Portainer (edge agent, UI over HTTPS) |
| 2003 | docker-proxy | 127.0.0.1 | Graphite carbon (Icinga 2 GraphiteWriter) |
| 8080 | docker-proxy | 127.0.0.1 | graphite-web (Icinga Web graphite module) |
| 9000 | docker-proxy | all | step-ca (`https://ca.kingma:9000`) |

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
| `icinga2/constants.conf` | `NodeName` and `ZoneName` set to `srv-monitor`; `TicketSalt` is set (for agent tickets) |
| `icinga2/zones.conf` | zones `srv-monitor`, `global-templates`, `director-global` |
| `icinga2/conf.d/api-users.conf` | API users for Icinga DB Web and the Director |
| `icinga2/features-available/icingadb.conf` | Icinga DB feature, Redis on `127.0.0.1:6380` |
| `icingadb/config.yml` | Icinga DB daemon: MariaDB on `localhost`, Redis on `localhost` |
| `icingaweb2/` | resources (databases `icingaweb2`, `icingadb`, `director`), DB authentication, modules `icingadb` and `director` |
| `redis/redis-icingadb.conf` | second Redis instance on port 6380 |

- Enabled features: `api`, `checker`, `graphite`, `icingadb`, `mainlog`, `notification`.
- The configuration validates (`icinga2 daemon -C`): 1 host, 12 services, 13 notifications, 250 check commands.
- Icinga Web 2 stores its configuration, authentication and the Director in MariaDB. Databases: `icingaweb2`, `icingadb`, `director` (194 MB in `/var/lib/mysql`).
- `icinga-director.service` runs the Director daemon. The Director is kickstarted (2026-11-28) from `modules/director/kickstart.ini`: it owns endpoint and zone `srv-monitor` and deploys to the master.
- Director schema migrated to the 1.12 level on 2026-11-28 (4 migrations were pending; dumps in `/var/backups/director-*.sql.gz`).

### Agents and Director objects

Remote hosts are managed in the Director only. Hand-written files in `conf.d` cover the master itself.

| Object | Kind | Purpose |
|--------|------|---------|
| `linux-agent` | host template | `hostalive`, Icinga agent, master connects, accepts config |
| `base-service` | service template | 5 min interval, 1 min retry, 3 attempts (`generic-service` is taken by `conf.d/templates.conf`) |
| `base-agent-service` | service template | `base-service`, runs on the agent |
| `disk`, `load`, `memory`, `swap`, `procs`, `apt`, `ping`, `ssh` | apply rules | every host that imports `linux-agent` |
| `zpool`, `smart_disk`, `pi_health`, `memavail`, `units` | check commands | plugins in `/usr/local/lib/nagios/plugins` on the agent |

`/etc/icinga2/conf.d/services.conf`: the example rules `ping4`, `ping6` and `ssh` have `ignore where host.name != NodeName`, so they no longer clash with Director hosts.

| Host | Agent | Defined by |
|------|-------|------------|
| `srv-nas-pi.kingma` (OMV, `192.168.111.11`) | 2.16.6, since 2026-11-28 | [`icinga/director/srv-nas-pi.sh`](icinga/director/srv-nas-pi.sh), plugins and setup in [srv-nas-pi/icinga](https://github.com/theking2/srv-nas-pi/tree/main/icinga) |
| `net-router.kingma` (EdgeRouter, `192.168.111.30`, `ntp.kingma`) | none (agentless) | [`icinga/director/net-router.sh`](icinga/director/net-router.sh) |

net-router runs ntpd (stratum 2, also serves the NTP pool). EdgeOS allows ntpd queries from localhost only (`restrict default ... noquery limited`), so [`icinga/net-router/ntp-restrict-srv-monitor.sh`](icinga/net-router/ntp-restrict-srv-monitor.sh) in `/config/scripts/post-config.d/` adds `restrict 192.168.111.22 nomodify notrap nopeer` to `/etc/ntp.conf` after every boot. All other clients keep the default restrictions. After a commit under `system ntp` EdgeOS rewrites `ntp.conf`: run the script again by hand. [`icinga/plugins/check_ntpd`](icinga/plugins/check_ntpd) (on srv-monitor) reads the system variables with NTP mode 6, like `ntpq -c rv`, no `ntpq` package needed. Upstream servers (in `config.boot` since 2026-11-28, BEV dropped): `ntp11`, `ntp12`, `ntp13.metas.ch` and `time1`, `time2.uni-konstanz.de`, all stratum 1. Services `ntp offset` (warn 10, crit 50 ms), `ntp jitter` (5, 20 ms), `ntp drift` (\|frequency\| 200, 450 ppm), `ntp sync` (stratum, system peer, usable peers: warn below 3, crit below 1); graphs from [`templates/ntp.ini`](icinga/icingaweb2/modules/graphite/templates/ntp.ini).

New agent: create the host in the Director (import `linux-agent`), deploy, get a ticket with `sudo icinga2 pki ticket --cn <host>`, then run `icinga2 node setup` on the agent with parent endpoint `srv-monitor,192.168.111.22,5665`.
- `icingadb-redis.service` is a hand-made unit, see [`systemd/`](systemd).

### Graphs

Performance data goes to Graphite, and Icinga Web 2 shows it as graphs on each host and service page (set up 2026-11-28).

- `GraphiteWriter` ([`features-available/graphite.conf`](icinga/icinga2/features-available/graphite.conf)) sends to carbon on `127.0.0.1:2003`, with thresholds (`enable_send_thresholds`). Metric path: `icinga2.<host>.services.<service>.<command>.perfdata.<label>.<value|warn|crit|min|max>`, dots and spaces in names become `_`.
- Graphite runs in the container `graphite` ([`containers/graphite`](containers/graphite)), data in `/srv/graphite/storage` (whisper files are preallocated, about 0.8 MB per metric).
- Retention ([`storage-schemas.conf`](containers/graphite/storage-schemas.conf)) follows the check interval: 5 min for 90 days, 30 min for 1 year, 2 h for 5 years; SMART checks start at 30 min, `apt` at 1 h, certificate checks at 6 h. A finer archive than the check interval would leave gaps that graphite-web does not draw. Rules apply to new metrics only; existing files need `whisper-resize.py`.
- Icinga Web module `graphite` 1.2.4 (Debian package `icingaweb2-module-graphite`), [`config.ini`](icinga/icingaweb2/modules/graphite/config.ini) points at `http://127.0.0.1:8080`. Graph templates for the own check commands (`zpool`, `smart_disk`, `pi_health`, `memavail`): [`templates/custom.ini`](icinga/icingaweb2/modules/graphite/templates/custom.ini).
- Carbon creates at most 50 new metrics per minute, so a new host shows all its graphs after a few minutes.

## Containers

See [`containers/`](containers/README.md). Portainer manages three stacks and runs next to a standalone `step-ca`; `graphite` is a compose stack in `/srv/graphite`.

## Scheduled jobs

Systemd timers: `apt-daily`, `apt-daily-upgrade`, `dpkg-db-backup`, `e2scrub_all`, `fstrim`, `logrotate`, `man-db`, `phpsessionclean`, `rpi-zram-writeback`. There are no user crontabs.

[`etc/cron.daily/auto-update`](etc/cron.daily/auto-update) runs `apt-get update` and `apt-get upgrade -y` once a day through `cron.daily`. It reboots only when a newer kernel of the running flavor (`2712`) is installed.

## Open issues

Tracked as [GitHub issues](https://github.com/theking2/srv-monitor/issues).

## Changes

Solved on 2026-11-09: time zone changed from `Europe/London` to `Europe/Zurich`; all pending package updates installed (Icinga 2.16.6, Icinga DB 1.6.0, Docker 29.9.3); time synchronization and DNS order (internal resolver first) are correct after the reboot.

Solved on 2026-11-10: `icingadb.service` runs. Causes were a broken `/etc/icingadb/config.yml` (stray text in line 1, empty password), a database password that did not match MariaDB (changed, also set in the `icingadb` resource of Icinga Web 2), the pending schema migration `1.6.0.sql` (schema v7 to v8, after the package update) and Redis on port 6380 refusing writes (`MISCONF`) until `/var/lib/icingadb-redis` was recreated with owner `redis`. Config and history sync complete. `step-ca` was started again (it had exited on the reboot with `restart=no`) and its restart policy set to `unless-stopped`.

Solved on 2026-11-10 (evening): `auto-update` reboots only after a kernel update of the running flavor, no longer daily ([#6](https://github.com/theking2/srv-monitor/issues/6)).

Solved on 2026-11-11: route metrics are pinned in NetworkManager (`eth0` 100, `eth1` 200; profiles renamed from `Wired connection N` and bound to their interface) ([#1](https://github.com/theking2/srv-monitor/issues/1)); `NetworkManager-wait-online` no longer fails on boot ([#2](https://github.com/theking2/srv-monitor/issues/2)); the `performance` stack (openpacketloss) was removed, which frees port 9000 for `step-ca` ([#3](https://github.com/theking2/srv-monitor/issues/3)); `cert-renewer@.service` was removed because TLS certificates come from the nginx-proxy on srv-nas-pi (Let's Encrypt) and this host manages none ([#4](https://github.com/theking2/srv-monitor/issues/4)); the bootloader EEPROM is up to date ([#5](https://github.com/theking2/srv-monitor/issues/5)).

Solved on 2026-11-28: the Director is set up (kickstart, schema migrations, API user, `TicketSalt`) and srv-nas-pi is monitored through an Icinga agent; Graphite and the Icinga Web graphite module show performance data as graphs.

Solved on 2026-11-28 (afternoon): Docker memory limits are enforced. The firmware adds `cgroup_disable=memory` to the kernel command line (Raspberry Pi default); [`cmdline.txt`](cmdline.txt) now ends with `cgroup_enable=memory`, which comes later and wins. After the reboot `graphite` (512 MiB) and `ipa-ocr` (2 GiB) were recreated, because Docker stores a limit of 0 for containers created while limits were unsupported. `lj-worker` got its 512 MiB with `docker update --memory 512m --memory-swap 1g`: "Update the stack" in Portainer does not recreate a container whose compose file is unchanged.

## Files that differ from the package defaults

`/etc/skel/.bashrc`, `/etc/login.defs`, `/etc/default/useradd`, `/etc/avahi/avahi-daemon.conf`, `/etc/initramfs-tools/initramfs.conf`, `/etc/systemd/timesyncd.conf`, `/etc/icinga2/constants.conf`, `/etc/icinga2/conf.d/api-users.conf`, `/etc/icinga2/conf.d/services.conf`, `/etc/icinga2/features-available/graphite.conf`, `/etc/apache2/conf-available/icingaweb2-root-redirect.conf` (enabled with `a2enconf`) and `/etc/icinga2/features-available/icingadb.conf`. The first five are not mirrored here.

## Inventory

`inventory.sh` rebuilds the data this documentation is based on. See [docs/inventory-script.md](docs/inventory-script.md).
