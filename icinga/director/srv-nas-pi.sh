#!/bin/bash
# Director objects for monitoring srv-nas-pi (OMV) through the Icinga agent.
# Run on srv-monitor: sudo bash srv-nas-pi.sh
# Re-runnable: objects and templates are updated in place. Apply rules that already
# exist are skipped (the Director CLI cannot look them up by name); change those in
# the web UI under Director > Services > Service Apply Rules.
# Plugins and sudoers on the NAS: https://github.com/theking2/srv-nas-pi/tree/main/icinga
set -euo pipefail
export TERM=dumb
P=/usr/local/lib/nagios/plugins
HOST=srv-nas-pi.kingma

# obj <type> <name> <json> [host]: create, or update if it exists
obj() {
  local t=$1 n=$2 j=$3 h=${4:-}
  local hostarg=()
  [ -n "$h" ] && hostarg=(--host "$h")
  if [[ $j == *'"object_type":"apply"'* ]]; then
    if [ "$(mysql -N director -e "SELECT COUNT(*) FROM icinga_service WHERE object_type='apply' AND object_name='$n'")" != 0 ]; then
      echo "Apply rule '$n' exists, skipped"; return
    fi
    icingacli director "$t" create "$n" --json "$j"; return
  fi
  if icingacli director "$t" exists "$n" "${hostarg[@]}" >/dev/null 2>&1; then
    icingacli director "$t" set "$n" "${hostarg[@]}" --json "$j" --replace
  else
    icingacli director "$t" create "$n" --json "$j"
  fi
}

### Check commands (deployed to director-global, so the agent gets them)
obj command zpool '{"object_type":"object","methods_execute":"PluginCheck","command":"'$P'/check_zpool",
  "arguments":{"-p":{"value":"$zpool_name$"},"-w":{"value":"$zpool_warn$"},"-c":{"value":"$zpool_crit$"}}}'
obj command smart_disk '{"object_type":"object","methods_execute":"PluginCheck","command":"'$P'/check_smart_disk",
  "arguments":{"-D":{"value":"$smart_device$","required":true},"-d":{"value":"$smart_type$"},"-w":{"value":"$smart_temp_warn$"},"-c":{"value":"$smart_temp_crit$"}}}'
obj command pi_health '{"object_type":"object","methods_execute":"PluginCheck","command":"'$P'/check_pi_health",
  "arguments":{"-w":{"value":"$pi_temp_warn$"},"-c":{"value":"$pi_temp_crit$"}}}'
obj command memavail '{"object_type":"object","methods_execute":"PluginCheck","command":"'$P'/check_memavail",
  "arguments":{"-w":{"value":"$memavail_warn$"},"-c":{"value":"$memavail_crit$"}}}'
obj command units '{"object_type":"object","methods_execute":"PluginCheck","command":"'$P'/check_units",
  "arguments":{"units":{"value":"$units_list$","skip_key":true,"required":true}}}'

### Templates (named base-* because conf.d already defines generic-service)
obj host linux-agent '{"object_type":"template","check_command":"hostalive",
  "has_agent":"y","master_should_connect":"y","accept_config":"y",
  "max_check_attempts":"3","check_interval":"60","retry_interval":"30"}'
obj service base-service '{"object_type":"template","max_check_attempts":"3","check_interval":"300","retry_interval":"60"}'
obj service base-agent-service '{"object_type":"template","imports":["base-service"],"use_agent":"y"}'

### Base services for every host that imports linux-agent
LINUX='"linux-agent"=host.templates'
obj service disk '{"object_type":"apply","imports":["base-agent-service"],"check_command":"disk","assign_filter":"'"${LINUX//\"/\\\"}"'",
  "vars":{"disk_wfree":"15%","disk_cfree":"5%",
  "disk_exclude_type":["none","tmpfs","sysfs","proc","configfs","devtmpfs","devfs","mtmfs","tracefs","cgroup","cgroup2",
   "fuse.*","fdescfs","overlay","nsfs","squashfs","zfs","cifs","smb3","nfs","nfs4","autofs","ramfs","efivarfs"]}}'
obj service load '{"object_type":"apply","imports":["base-agent-service"],"check_command":"load","assign_filter":"'"${LINUX//\"/\\\"}"'"}'
obj service memory '{"object_type":"apply","imports":["base-agent-service"],"check_command":"memavail","assign_filter":"'"${LINUX//\"/\\\"}"'"}'
obj service swap '{"object_type":"apply","imports":["base-agent-service"],"check_command":"swap","assign_filter":"'"${LINUX//\"/\\\"}"'",
  "vars":{"swap_wfree":"40%","swap_cfree":"20%"}}'
obj service procs '{"object_type":"apply","imports":["base-agent-service"],"check_command":"procs","assign_filter":"'"${LINUX//\"/\\\"}"'",
  "vars":{"procs_warning":"700","procs_critical":"1000"}}'
obj service apt '{"object_type":"apply","imports":["base-agent-service"],"check_command":"apt","assign_filter":"'"${LINUX//\"/\\\"}"'",
  "check_interval":"3600","retry_interval":"600"}'
obj service ping '{"object_type":"apply","imports":["base-service"],"check_command":"ping4","assign_filter":"'"${LINUX//\"/\\\"}"'",
  "check_interval":"60","retry_interval":"30"}'
obj service ssh '{"object_type":"apply","imports":["base-service"],"check_command":"ssh","assign_filter":"'"${LINUX//\"/\\\"}"'"}'

### The NAS
obj host "$HOST" '{"object_type":"object","imports":["linux-agent"],"display_name":"srv-nas-pi (OMV)","address":"192.168.111.11",
  "vars":{"os":"Linux","role":"nas"}}'

svc() { obj service "$1" "$2" "$HOST"; }
J() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d.update({"object_type":"object","host":sys.argv[2]}); print(json.dumps(d))' "$1" "$HOST"; }

svc "zpool pool0" "$(J '{"imports":["base-agent-service"],"check_command":"zpool","vars":{"zpool_name":"pool0"}}')"
for id in ata-WD_Red_SA500_2.5_4TB_2446BMD00017 ata-WD_Red_SA500_2.5_4TB_2446BMD00094 \
          ata-WD_Red_SA500_2.5_4TB_2446BMD00135 ata-WD_Red_SA500_2.5_4TB_2446BMD00538; do
  svc "smart ${id##*_}" "$(J '{"imports":["base-agent-service"],"check_command":"smart_disk","check_interval":"1800",
    "vars":{"smart_type":"sat","smart_device":"/dev/disk/by-id/'$id'"}}')"
done
# Seagate 1.5 TB backup HDD on USB/eSATA; vendor temperature limit is 55C
svc "smart backup-hdd" "$(J '{"imports":["base-agent-service"],"check_command":"smart_disk","check_interval":"1800",
  "vars":{"smart_type":"usbsunplus","smart_device":"/dev/disk/by-id/usb-ST315003_41AS_00038d5d-0:0","smart_temp_warn":"50","smart_temp_crit":"55"}}')"
svc "pi health" "$(J '{"imports":["base-agent-service"],"check_command":"pi_health","check_interval":"120"}')"
svc "systemd units" "$(J '{"imports":["base-agent-service"],"check_command":"units",
  "vars":{"units_list":["openmediavault-engined","docker","smartmontools","zfs-zed","nginx","php8.4-fpm","ssh","nut-monitor","collectd","monit"]}}')"

# Web services, checked from srv-monitor against the LAN address (not the WAN hairpin)
web() { svc "$1" "$(J '{"imports":["base-service"],"check_command":"http","vars":'"$2"'}')"; }
web "web OMV"          '{"http_vhost":"srv-nas-pi.kingma","http_port":"8443","http_ssl":true}'
web "web NPM admin"    '{"http_vhost":"npm.kingma","http_ssl":true,"http_sni":true}'
web "web Nextcloud"    '{"http_vhost":"office.kingma.ch","http_ssl":true,"http_sni":true,"http_uri":"/status.php","http_string":"\"maintenance\":false"}'
web "web OnlyOffice"   '{"http_vhost":"cloud.kingma.ch","http_ssl":true,"http_sni":true,"http_uri":"/healthcheck","http_string":"true"}'
web "web Lyrion"       '{"http_port":"9000"}'
web "web HomeAssistant" '{"http_port":"8123"}'
web "web Speedtest"    '{"http_vhost":"speed.kingma.ch","http_ssl":true,"http_sni":true}'
cert() { svc "cert $1" "$(J '{"imports":["base-service"],"check_command":"http","check_interval":"21600",
  "vars":{"http_vhost":"'$1'","http_ssl":true,"http_sni":true,"http_certificate":"21,7"}}')"; }
for n in office.kingma.ch office.king.ma cloud.kingma.ch speed.kingma.ch home-assistant.kingma.ch; do cert $n; done

icingacli director config deploy
