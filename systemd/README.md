# systemd

Units and drop-ins that were written by hand. They live in `/etc/systemd/system/`.

| File | Target | Purpose |
|------|--------|---------|
| [`icingadb-redis.service`](icingadb-redis.service) | `/etc/systemd/system/icingadb-redis.service` | Second Redis instance for Icinga DB: `redis-server /etc/redis/redis-icingadb.conf`, user `redis`, port 6380, `Restart=always`. Configuration: [`../icinga/redis/redis-icingadb.conf`](../icinga/redis/redis-icingadb.conf) |
| [`icinga2.service.d/limits.conf`](icinga2.service.d/limits.conf) | `/etc/systemd/system/icinga2.service.d/limits.conf` | `TasksMax=infinity` for Icinga 2 |
