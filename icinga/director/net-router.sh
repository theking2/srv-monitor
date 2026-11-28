#!/bin/bash
# Director objects for net-router (Ubiquiti EdgeRouter, EdgeOS): gateway of the LAN and NTP server
# (ntp.kingma, also a member of the NTP pool). Agentless: every check runs on srv-monitor.
# Run on srv-monitor: sudo bash net-router.sh   (re-runnable: objects are updated in place)
# Needs on net-router: /config/scripts/post-config.d/ntp-restrict-srv-monitor.sh (icinga/net-router/)
# Needs on srv-monitor: /usr/local/lib/nagios/plugins/check_ntpd (icinga/plugins/)
set -euo pipefail
export TERM=dumb
P=/usr/local/lib/nagios/plugins
HOST=net-router.kingma

obj() {
  local t=$1 n=$2 j=$3 h=${4:-}
  local hostarg=()
  [ -n "$h" ] && hostarg=(--host "$h")
  if icingacli director "$t" exists "$n" "${hostarg[@]}" >/dev/null 2>&1; then
    icingacli director "$t" set "$n" "${hostarg[@]}" --json "$j" --replace
  else
    icingacli director "$t" create "$n" --json "$j"
  fi
}
J() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d.update({"object_type":"object","host":sys.argv[2]}); print(json.dumps(d))' "$1" "$HOST"; }
svc() { obj service "$1" "$2" "$HOST"; }

obj command ntpd '{"object_type":"object","methods_execute":"PluginCheck","command":"'$P'/check_ntpd",
  "arguments":{"-H":{"value":"$ntpd_address$"},"-m":{"value":"$ntpd_mode$","required":true},
  "-w":{"value":"$ntpd_warn$"},"-c":{"value":"$ntpd_crit$"}},
  "vars":{"ntpd_address":"$address$"}}'

# devices without an Icinga agent (routers, switches, appliances)
obj host network-device '{"object_type":"template","check_command":"hostalive",
  "max_check_attempts":"3","check_interval":"60","retry_interval":"30"}'

obj host "$HOST" '{"object_type":"object","imports":["network-device"],"display_name":"net-router (EdgeRouter)",
  "address":"192.168.111.30","vars":{"role":"router"}}'

svc "ping" "$(J '{"imports":["base-service"],"check_command":"ping4","check_interval":"60","retry_interval":"30"}')"
svc "ssh"  "$(J '{"imports":["base-service"],"check_command":"ssh"}')"

# thresholds: offset ms, jitter ms, drift |ppm| (ntpd can correct at most 500 ppm), sync = min usable peers
ntp() { svc "ntp $1" "$(J '{"imports":["base-service"],"check_command":"ntpd","vars":{"ntpd_mode":"'$1'","ntpd_warn":"'$2'","ntpd_crit":"'$3'"}}')"; }
ntp offset 10 50
ntp jitter 5 20
ntp drift 200 450
ntp sync 3 1

icingacli director config deploy
