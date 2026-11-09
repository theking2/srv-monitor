# systemd

Units and drop-ins that were written by hand. They live in `/etc/systemd/system/`.

| File | Target | Purpose |
|------|--------|---------|
| [`icingadb-redis.service`](icingadb-redis.service) | `/etc/systemd/system/icingadb-redis.service` | Second Redis instance for Icinga DB: `redis-server /etc/redis/redis-icingadb.conf`, user `redis`, port 6380, `Restart=always`. Configuration: [`../icinga/redis/redis-icingadb.conf`](../icinga/redis/redis-icingadb.conf) |
| [`icinga2.service.d/limits.conf`](icinga2.service.d/limits.conf) | `/etc/systemd/system/icinga2.service.d/limits.conf` | `TasksMax=infinity` for Icinga 2 |
| [`cert-renewer@.service`](cert-renewer@.service) | `/etc/systemd/system/cert-renewer@.service` | Template from the step-ca documentation: renews `/etc/step/certs/<name>.crt` with `step ca renew` if it needs renewal, then reloads `<name>.service`. Currently unused: no instance, no timer, the directories `/etc/step` and `/etc/step-ca` do not exist. |

`cert-renewer@.service` needs a matching `cert-renewer@.timer` to run periodically (see `step-ca_renew/` in [srv-nas-pi](https://github.com/theking2/srv-nas-pi) for an example).
