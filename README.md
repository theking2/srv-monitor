# srv-monitor

Documentation and configuration of `srv-monitor.kingma`, a Raspberry Pi OS (Debian) based server. The layout follows [srv-nas-pi](https://github.com/theking2/srv-nas-pi): a README for hardware, network and storage, `config.txt` for the boot configuration, `containers/<name>/` for compose files and env files, and one folder per hand-made systemd unit set.

The documentation is derived from a read-only inventory of the running host (`inventory.sh`).

## Inventory

`inventory.sh` collects the state of the host and changes nothing: no installs, no writes outside its output directory, no network traffic.

```bash
git clone https://github.com/theking2/srv-monitor
cd srv-monitor
less inventory.sh          # read it first
sudo ./inventory.sh        # writes ./inventory-<hostname>-<date>/ and a .tar.gz
```

The script requires root and exits otherwise. Without root, firewall rules, sudoers, effective sshd settings, `ss -p`, user crontabs and root-only service configs (for example `/etc/icinga2`) are missing. `-n` forces an incomplete run without root.

### What it collects

| Area | Content |
|------|---------|
| Host | OS, kernel, Pi model, CPU, memory, firmware, throttling, time zone, `config.txt`, `cmdline.txt` |
| Storage | `lsblk`, mounts, `fstab`, swap, ZFS/mdadm if present, network mounts |
| Network | addresses, routes, DNS, NetworkManager/dhcpcd/netplan/networkd config, listening ports, firewall, time sync, effective sshd settings |
| Services | running and enabled units, timers, failed units with status and journal tail, cron of all users, hand-made units and drop-ins |
| Applications | config trees of known services if present (Icinga, Redis, MariaDB, Apache/nginx, Grafana, Prometheus, Zabbix, step-ca, samba and others), plus version and feature output |
| Certificates | cert-renewer units and timers, subject, issuer, validity and SANs of `/etc/step/certs/*.crt` |
| Packages | manually installed packages, apt command history, held and locally installed packages, apt sources, pip/npm/snap/flatpak/cargo, `/usr/local/bin`, `/opt`, `/srv` |
| Containers | containers, images, ports, mounts, networks, volumes, compose files, Dockerfiles, env files (stacks kept in a Portainer volume are resolved to their host path) |
| Users | UID 0 and UID >= 1000 accounts, relevant groups, sudoers, `authorized_keys` fingerprints |
| Drift | `/etc` conffiles that differ from the package default, files under `/etc` that no package ships |

### Output

```
inventory-<hostname>-<date>/
├── inventory.md              all command output
└── files/
    ├── boot/firmware/        config.txt, cmdline.txt
    ├── containers/<project>/ compose.yaml, *.env, Dockerfile
    ├── systemd/              hand-made units, timers, drop-ins
    ├── etc/                  changed or unpackaged config files
    └── packages-manual.txt
```

### Secrets

Values of keys whose name contains `pass`, `pwd`, `secret`, `token`, `key`, `psk`, `credential` or `salt` are replaced with `<redacted>`, as are credentials in URLs and private key blocks. Private keys, SSH host keys, `shadow` and `*.pem` files are never copied. Redaction is best-effort and over-redacts on purpose. Check `files/` before sharing or committing the result.

Raw inventory output is excluded from git through `.gitignore`. Only the reviewed documentation belongs in the repository.
