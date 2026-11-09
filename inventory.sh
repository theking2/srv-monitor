#!/usr/bin/env bash
#
# inventory.sh - read-only inventory of a Raspberry Pi OS / Debian host
#
# Collects hardware, OS, storage, network, services, packages, containers,
# users and locally changed configuration, and writes it to a directory
# (plus a .tar.gz) laid out like theking2/srv-nas-pi:
#
#   inventory.md              everything that is command output
#   files/boot/firmware/      config.txt, cmdline.txt
#   files/containers/<dir>/   compose files, Dockerfiles, env files (redacted)
#   files/systemd/            hand-made units, timers, drop-ins
#   files/etc/...             changed or unpackaged config files (redacted)
#   files/packages-manual.txt manually installed packages
#
# It changes nothing on the host: no installs, no writes outside the output
# directory, no network traffic. Run with sudo to see everything
# (ss -p, crontabs of all users, root-only configs).
#
# Secrets are redacted on a best-effort basis (see redact()). Review the
# output before you share it.
#
# Usage: sudo ./inventory.sh [-o OUTDIR] [-h]

set -u
umask 077

VERSION=2
OUT=""

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

ALLOW_NONROOT=0
while getopts "o:nh" opt; do
  case $opt in
    o) OUT=$OPTARG ;;
    n) ALLOW_NONROOT=1 ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done

if [ "$(id -u)" -ne 0 ] && [ "$ALLOW_NONROOT" -ne 1 ]; then
  echo "inventory.sh needs root for a complete inventory (service configs, firewall, sudoers, ss -p)." >&2
  echo "Run: sudo $0 ${OUT:+-o $OUT}    (or pass -n to run incomplete without root)" >&2
  exit 1
fi

HOST=$(hostname -s 2>/dev/null || echo unknown)
OUT=${OUT:-./inventory-$HOST-$(date +%F)}
mkdir -p "$OUT/files" || { echo "cannot create $OUT" >&2; exit 1; }
OUT=$(cd "$OUT" && pwd)
MD="$OUT/inventory.md"
: > "$MD"

IS_ROOT=0
[ "$(id -u)" -eq 0 ] && IS_ROOT=1

# ---------------------------------------------------------------- helpers --

have() { command -v "$1" >/dev/null 2>&1; }

# Best-effort secret removal. Replaces the value of any key whose name
# contains pass/pwd/secret/token/key/psk/credential/salt, credentials in
# URLs and DSNs, and whole private-key blocks. Keys that end in
# path/file/location/dir (KEY_LOCATION=/etc/x.key) hold paths and are kept.
# Over-redacts rather than under-redacts.
redact() {
  sed -E \
    -e '/-----BEGIN [A-Z ]*PRIVATE KEY-----/,/-----END [A-Z ]*PRIVATE KEY-----/c\<private key block removed>' \
    -e 's#(://[^/:@[:space:]]+):[^/@[:space:]]+@#\1:<redacted>@#g' \
    -e 's#([[:alnum:]_.-]+):[^@/[:space:]]+@(tcp|unix)\(#\1:<redacted>@\2(#g' \
    -e "/^[[:space:]-]*['\"]?[[:alnum:]_.-]*(path|file|location|dir)['\"]?[[:space:]]*[=:]/Ib" \
    -e "s/^([[:space:]-]*['\"]?[[:alnum:]_.-]*(pass|pwd|secret|token|key|psk|credential|salt)[[:alnum:]_.-]*['\"]?[[:space:]]*[=:][[:space:]]*).+\$/\\1<redacted>/I"
}

say() { printf '%s\n' "$*" >> "$MD"; }

section() { printf '\n## %s\n' "$1" >> "$MD"; echo "[*] $1" >&2; }

# run '<shell command>'   -> fenced block in inventory.md, redacted
run() {
  local first=${1%% *}
  printf '\n### `%s`\n\n```\n' "$1" >> "$MD"
  if ! have "$first"; then
    printf '(skipped: %s not installed)\n' "$first" >> "$MD"
  else
    timeout 60 bash -c "$1" 2>&1 | redact >> "$MD"
  fi
  printf '```\n' >> "$MD"
}

# grab <path> [dest-relative-to-files/]  -> redacted copy of a small text file
grab() {
  local src=$1 rel=${2:-$1} dst
  [ -f "$src" ] && [ -r "$src" ] || return 0
  case "$src" in
    *shadow*|*ssh_host_*|*.key|*.pem|*.p12|*.pfx|*.kdbx|*id_rsa*|*id_ed25519*|*id_ecdsa*) return 0 ;;
  esac
  [ "$(stat -Lc %s "$src" 2>/dev/null || echo 0)" -le 262144 ] || { say "(skipped, larger than 256 KiB: $src)"; return 0; }
  grep -Iq . "$src" 2>/dev/null || return 0
  dst="$OUT/files/${rel#/}"
  mkdir -p "$(dirname "$dst")"
  redact < "$src" > "$dst"
}

# ----------------------------------------------------------------- header --

{
  echo "# Inventory of $HOST"
  echo
  echo "- generated: $(date -Is)"
  echo "- script: inventory.sh v$VERSION"
  echo "- run as root: $([ $IS_ROOT -eq 1 ] && echo yes || echo 'no (some sections are incomplete)')"
  echo "- redaction is best-effort: review before sharing"
} >> "$MD"
[ $IS_ROOT -eq 1 ] || echo "[!] not root: ss -p, crontabs, some configs will be incomplete" >&2

# ------------------------------------------------------------------- host --

section "Host and hardware"
run 'hostnamectl'
run 'cat /etc/os-release'
run 'cat /etc/debian_version'
run 'tr -d "\0" < /proc/device-tree/model; echo'
run 'uname -a'
run 'uptime -p; uptime -s'
run 'lscpu | grep -E "Model name|Architecture|^CPU\(s\)|Max MHz"'
run 'free -h'
run 'vcgencmd version'
run 'vcgencmd get_throttled'
run 'vcgencmd measure_temp'
run 'rpi-eeprom-update'
run 'timedatectl'
run 'localectl status'
run 'cat /etc/hostname /etc/hosts'
run 'lsusb'
run 'lspci'

for f in /boot/firmware/config.txt /boot/firmware/cmdline.txt /boot/config.txt /boot/cmdline.txt; do
  # newer images leave a "DO NOT EDIT" stub at the old location
  grep -q "DO NOT EDIT THIS FILE" "$f" 2>/dev/null && continue
  grab "$f"
done

# ---------------------------------------------------------------- storage --

section "Storage"
run 'lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,TRAN'
run 'df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay'
run 'findmnt --real'
run 'cat /etc/fstab'
run 'swapon --show'
run 'zpool list'
run 'zpool status'
run 'zfs list'
run 'cat /proc/mdstat'
run 'smartctl --scan'
run 'mount | grep -E " type (nfs|nfs4|cifs|fuse\.[a-z]+) "'
grab /etc/fstab
grab /etc/exports
grab /etc/samba/smb.conf

# ---------------------------------------------------------------- network --

section "Network"
run 'ip -br a'
run 'ip -4 route'
run 'ip -6 route'
run 'cat /etc/resolv.conf'
run 'resolvectl status'
run 'nmcli -t -f NAME,TYPE,DEVICE,AUTOCONNECT connection show'
run 'networkctl'
run 'ss -tulpn'
run 'ss -s'
run 'nft list ruleset'
run 'iptables -S'
run 'ufw status verbose'
run 'timedatectl timesync-status'
run 'chronyc tracking'
run 'chronyc sources'
run 'sshd -T | grep -E "^(port|listenaddress|permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers|allowgroups|x11forwarding|usepam) "'

for f in /etc/network/interfaces /etc/network/interfaces.d/* /etc/dhcpcd.conf \
         /etc/netplan/*.yaml /etc/systemd/network/* /etc/NetworkManager/NetworkManager.conf \
         /etc/NetworkManager/system-connections/* /etc/wpa_supplicant/wpa_supplicant.conf \
         /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* /etc/chrony/chrony.conf \
         /etc/systemd/timesyncd.conf /etc/nftables.conf /etc/ufw/user.rules; do
  grab "$f"
done

# --------------------------------------------------------------- services --

section "Services and scheduling"
run 'systemctl list-units --type=service --state=running --no-pager --plain'
run 'systemctl list-unit-files --state=enabled --no-pager --plain'
run 'systemctl list-timers --all --no-pager'
run 'systemctl --failed --no-pager'
run 'for u in $(systemctl list-units --state=failed --plain --no-legend | awk "{print \$1}"); do echo "[$u]"; systemctl status "$u" --no-pager -l | head -15; journalctl -u "$u" -n 25 --no-pager; done'
run 'loginctl list-users'

# hand-made units and drop-ins (regular files, not the symlinks of enable)
if [ -d /etc/systemd/system ]; then
  while IFS= read -r f; do
    grab "$f" "systemd/${f#/etc/systemd/system/}"
  done < <(find /etc/systemd/system -type f \( -name '*.service' -o -name '*.timer' -o -name '*.mount' \
             -o -name '*.automount' -o -name '*.socket' -o -name '*.path' -o -name '*.conf' \) 2>/dev/null)
fi
run 'ls -la /etc/systemd/system | grep -v "^l"'

run 'cat /etc/crontab'
run 'ls -la /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly'
run 'for u in $(cut -d: -f1 /etc/passwd); do crontab -l -u "$u" 2>/dev/null | sed "s/^/[$u] /"; done'
for f in /etc/cron.d/*; do grab "$f"; done

# --------------------------------------------------------------- packages --

section "Packages and software"
run 'dpkg -l | grep -c "^ii"'
run 'apt-mark showhold'
run 'apt list --installed 2>/dev/null | grep -F "[installed,local]"'
run 'apt list --upgradable 2>/dev/null'
run 'cat /etc/apt/sources.list'
run 'ls -la /etc/apt/sources.list.d /etc/apt/keyrings /usr/share/keyrings'
run 'grep -h "^Commandline:" /var/log/apt/history.log'
run 'zgrep -h "^Commandline:" /var/log/apt/history.log.*.gz'
run 'pip3 list --not-required'
run 'npm ls -g --depth=0'
run 'snap list'
run 'flatpak list'
run 'cargo install --list'
run 'ls -la /usr/local/bin /usr/local/sbin /opt /srv'
run 'ls -la /var/www'
run 'du -sh /opt/* /srv/* /var/www/* 2>/dev/null'
run 'find /srv /opt /var/www -maxdepth 3 -not -path "*/node_modules*" -not -path "*/.git/*" | sort | head -200'

if have apt-mark; then
  apt-mark showmanual 2>/dev/null | sort > "$OUT/files/packages-manual.txt"
fi
for f in /etc/apt/sources.list /etc/apt/sources.list.d/* /etc/apt/preferences /etc/apt/preferences.d/* \
         /etc/apt/apt.conf.d/*; do
  grab "$f"
done

# ------------------------------------------------------------- containers --

section "Containers"
if have docker; then
  run 'docker version --format "docker {{.Server.Version}}"'
  run 'docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
  run 'docker compose ls -a'
  run 'docker network ls'
  run 'docker volume ls'
  run 'docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"'
  run 'docker system df'

  say ""
  say "### per container"
  say ""
  say '```'
  for c in $(docker ps -aq 2>/dev/null); do
    {
      docker inspect "$c" --format '{{.Name}}  image={{.Config.Image}}  restart={{.HostConfig.RestartPolicy.Name}}  network_mode={{.HostConfig.NetworkMode}}'
      docker inspect "$c" --format '  compose project={{index .Config.Labels "com.docker.compose.project"}} workdir={{index .Config.Labels "com.docker.compose.project.working_dir"}} files={{index .Config.Labels "com.docker.compose.project.config_files"}}'
      docker inspect "$c" --format '{{range $p,$b := .NetworkSettings.Ports}}  port {{$p}} -> {{$b}}{{println}}{{end}}'
      docker inspect "$c" --format '{{range .Mounts}}  mount {{.Type}} {{.Source}} -> {{.Destination}} ({{if .RW}}rw{{else}}ro{{end}}){{println}}{{end}}'
      docker inspect "$c" --format '{{range .Config.Env}}  {{println .}}{{end}}'
      echo
    } 2>&1 | redact >> "$MD"
  done
  say '```'
else
  say ""
  say "(docker not installed)"
fi
run 'podman ps -a'
grab /etc/docker/daemon.json

# compose projects: files from container labels plus a filesystem search,
# stored as files/containers/<directory-name>/<file> like srv-nas-pi
declare -A DIRMAP=()
declare -A SEEN=()

# Portainer and similar tools keep stacks inside a volume and report the
# container-side path (/data/compose/3). Translate it to the host path through
# the mounts of all containers, accepting the first candidate that holds a
# compose file.
map_into_mounts() {
  local p=$1 c dest src cand
  for c in $(docker ps -aq 2>/dev/null); do
    while IFS='|' read -r dest src; do
      [ -n "$dest" ] || continue
      case "$p" in
        "$dest"|"$dest"/*)
          cand="$src${p#"$dest"}"
          if compgen -G "$cand/compose*.y*ml" >/dev/null || compgen -G "$cand/docker-compose*.y*ml" >/dev/null; then
            echo "$cand"; return 0
          fi ;;
      esac
    done < <(docker inspect "$c" --format '{{range .Mounts}}{{.Destination}}|{{.Source}}{{println}}{{end}}' 2>/dev/null)
  done
  return 1
}

# stash_compose_dir <host dir> [name]   name defaults to the directory name
stash_compose_dir() {
  local d=$1 name n=1 base
  [ -d "$d" ] || return 0
  [ -n "${SEEN[$d]:-}" ] && return 0
  SEEN[$d]=1
  base=${2:-$(basename "$d")}
  name=$base
  while [ -n "${DIRMAP[$name]:-}" ] && [ "${DIRMAP[$name]}" != "$d" ]; do
    n=$((n+1)); name="$base-$n"
  done
  DIRMAP[$name]=$d
  local f
  for f in "$d"/compose*.y*ml "$d"/docker-compose*.y*ml "$d"/*.compose.y*ml "$d"/Dockerfile \
           "$d"/.env "$d"/*.env "$d"/*.yml "$d"/*.yaml "$d"/README.md; do
    [ -f "$f" ] && grab "$f" "containers/$name/$(basename "$f")"
  done
}

if have docker; then
  while IFS='|' read -r proj wd; do
    [ -n "$wd" ] || continue
    if [ -d "$wd" ]; then
      stash_compose_dir "$wd" "$proj"
    elif hostdir=$(map_into_mounts "$wd"); then
      stash_compose_dir "$hostdir" "$proj"
    else
      say "(compose directory of project $proj not reachable from the host: $wd)"
    fi
  done < <(docker ps -aq 2>/dev/null | xargs -r docker inspect \
             --format '{{index .Config.Labels "com.docker.compose.project"}}|{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null | sort -u)
fi
while IFS= read -r f; do
  stash_compose_dir "$(dirname "$f")"
done < <(find / -maxdepth 7 \
           \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /var/lib/docker \
              -o -path /var/lib/containerd -o -path /usr -o -path /lib -o -path /snap -o -path '*/node_modules' -o -path "$OUT" \) -prune \
           -o -type f \( -name 'compose*.y*ml' -o -name 'docker-compose*.y*ml' \) -print 2>/dev/null)

say ""
say "### compose directories found"
say ""
say '```'
for k in "${!DIRMAP[@]}"; do printf 'containers/%s  <-  %s\n' "$k" "${DIRMAP[$k]}" >> "$MD"; done
say '```'

# ------------------------------------------------------------------ users --

section "Users and access"
run 'getent passwd | awk -F: "\$3==0 || (\$3>=1000 && \$3<65534) {print \$1\":\"\$3\":\"\$4\":\"\$6\":\"\$7}"'
run 'getent group sudo docker adm video gpio i2c spi dialout plugdev'
run 'grep -rhv "^[[:space:]]*#\|^[[:space:]]*$" /etc/sudoers /etc/sudoers.d/'
run 'ls -la /home'
run 'for h in /root /home/*; do [ -f "$h/.ssh/authorized_keys" ] && { echo "[$h]"; ssh-keygen -lf "$h/.ssh/authorized_keys"; }; done'

# ----------------------------------------------------------- config drift --

section "Configuration changed from package defaults"
run 'dpkg -V 2>/dev/null | grep -E "^.{2}5.{6} +c /etc/"'

if have dpkg && have dpkg-query; then
  tmp=$(mktemp -d)
  dpkg-query -W -f='${Package}\n' 2>/dev/null | xargs -r dpkg -L 2>/dev/null | sort -u > "$tmp/pkgfiles"
  find /etc \( -type f -o -type l \) 2>/dev/null | sort > "$tmp/etcfiles"
  # generated or default files that every Debian host has
  NOISE='^/etc/(ssl/|ca-certificates|alternatives/|selinux/|ld\.so\.cache|passwd|group|gshadow|shadow|subuid|subgid|machine-id|mtab|resolv\.conf|\.pwd\.lock|\.updated|ssh/ssh_host_|systemd/system/.*\.wants/|systemd/user/.*\.wants/|rc[0-9S]\.d/|init\.d/|fstab|motd|issue|localtime|shells|dpkg/origins|security/|ppp/|runit/|xml/|sgml/|python3/|fonts/|console-setup/cached_|php/[0-9.]+/mods-available/|nagios-plugins/config/|apparmor\.d/|pam\.d/common-|locale\.gen|rpi-issue|cifs-utils/)'
  comm -13 "$tmp/pkgfiles" "$tmp/etcfiles" | grep -Ev "$NOISE" \
    | while IFS= read -r f; do
        # enable-style symlinks (mods-enabled, conf.d) that point back into /etc add no information
        if [ -L "$f" ]; then
          case "$(readlink -f "$f" 2>/dev/null)" in /etc/*) continue ;; esac
        fi
        printf '%s\n' "$f"
      done > "$tmp/unpackaged"

  say ""
  say "### files under /etc that no package ships (names only; text files are copied to files/etc)"
  say ""
  say '```'
  head -400 "$tmp/unpackaged" >> "$MD"
  say '```'

  # copy changed conffiles and unpackaged text files (cap: 250)
  {
    dpkg -V 2>/dev/null | awk '$0 ~ /^.{2}5.{6} +c \/etc\// {print $NF}'
    head -150 "$tmp/unpackaged"
  } | sort -u | head -250 | while IFS= read -r f; do grab "$f"; done
  rm -rf "$tmp"
fi

# ---------------------------------------------------- application configs --

section "Application configuration"

# Whole config trees of services that are commonly installed on a monitoring
# or web host. Only those that exist are copied (text files, redacted, <= 300).
APP_DIRS=(/etc/icinga2 /etc/icingaweb2 /etc/icingadb /etc/icinga-director /etc/redis /etc/mysql
          /etc/apache2/sites-enabled /etc/apache2/conf-enabled /etc/nginx/sites-enabled /etc/nginx/conf.d
          /etc/grafana /etc/prometheus /etc/zabbix /etc/telegraf /etc/loki /etc/step /etc/step-ca
          /etc/samba /etc/postfix /etc/msmtprc /etc/fail2ban /etc/rclone)
count=0
for d in "${APP_DIRS[@]}"; do
  [ -e "$d" ] || continue
  say ""
  say "### $d"
  say ""
  say '```'
  ls -laR "$d" 2>&1 | head -150 | redact >> "$MD"
  say '```'
  while IFS= read -r f; do
    [ "$count" -ge 300 ] && break
    grab "$f"; count=$((count+1))
  done < <(find "$d" \( -type f -o -type l \) 2>/dev/null | sort)
done

run 'icinga2 --version'
run 'icinga2 feature list'
run 'icinga2 daemon -C'
run 'icingacli module list'
run 'icingacli version'
run 'icingadb --version'
run 'mariadb -N -e "show databases"'
run 'du -sh /var/lib/mysql'
run 'redis-cli -p 6379 ping'
run 'redis-cli -p 6380 ping'
run 'apache2ctl -S'
run 'apache2ctl -M'
run 'php -v'

# ------------------------------------------------------------ certificates --

section "Certificates"
run 'systemctl list-units "cert-renewer@*" --all --no-pager --plain'
run 'systemctl list-timers "cert-renewer@*" --all --no-pager'
run 'ls -la /etc/step /etc/step/certs /etc/step-ca'
run 'for c in /etc/step/certs/*.crt /etc/ssl/local/*.crt; do [ -f "$c" ] || continue; echo "[$c]"; openssl x509 -in "$c" -noout -subject -issuer -dates -ext subjectAltName; done'
run 'step ca health'

# ---------------------------------------------------------------- finish --

( cd "$OUT/.." && tar czf "$OUT.tar.gz" "$(basename "$OUT")" ) 2>/dev/null

echo >&2
echo "[done] $OUT/inventory.md" >&2
echo "[done] $OUT.tar.gz ($(du -h "$OUT.tar.gz" 2>/dev/null | cut -f1))" >&2
echo "Review files/ for leftover secrets, then attach the .tar.gz." >&2
