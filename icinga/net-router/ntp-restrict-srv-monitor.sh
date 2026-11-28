#!/bin/sh
# /config/scripts/post-config.d/ntp-restrict-srv-monitor.sh on net-router (EdgeOS)
#
# Lets srv-monitor (192.168.111.22) read ntpd's variables with mode 6 queries (ntpq -c rv),
# so Icinga can monitor offset, jitter and drift. The default restrict line
# ("kod notrap nomodify nopeer noquery limited") stays in force for every other client.
#
# EdgeOS regenerates /etc/ntp.conf at boot and on every commit under "system ntp".
# Scripts in /config/scripts/post-config.d run at the end of boot and survive firmware
# upgrades; after a "system ntp" commit, run this script again by hand:
#   sudo /config/scripts/post-config.d/ntp-restrict-srv-monitor.sh
LINE='restrict 192.168.111.22 nomodify notrap nopeer'
F=/etc/ntp.conf

grep -qxF "$LINE" "$F" && exit 0
printf '\n# added by %s: Icinga on srv-monitor may query ntpd\n%s\n' "$0" "$LINE" >> "$F"
/etc/init.d/ntp restart >/dev/null 2>&1
logger -t ntp-restrict "added query access for srv-monitor to $F, ntpd restarted"
