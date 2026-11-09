# Containers

Docker 29.9.2 with the compose plugin. Portainer CE manages the stacks. Portainer keeps the stack files in its data volume: `/var/lib/docker/volumes/portainer_data/_data/compose/<id>/` on the host, `/data/compose/<id>/` inside Portainer.

## Stacks

| Stack | Id | Container | Image | State | Notes |
|-------|----|-----------|-------|-------|-------|
| `ipa-ocr` | 3 | `ipa-ocr` | `ipa-ocr:3` (local build) | up, healthy | no network, 2 GB memory limit, OCR loop |
| | | `ipa-log` | `ipa-ocr:3` | up | no network, tails `/logs/ocr.log` read-only |
| | | `ipa-sync` | `rclone/rclone:latest` | up | every 600 s: PDFs from a Dropbox folder to `/data`, `*-OCR.pdf` results back |
| `performance` | 2 | `openpacketloss` | `openpacketloss/openpacketloss-server:latest` | `Created`, never started | port 9000 is taken by `step-ca`, see [open issues](../README.md#open-issues) |
| `lj-worker` | 1 | `lj-worker` | `lj-worker:latest` (built by Portainer from a Git repository) | up, healthy | verification worker, no published ports, runs read-only with all capabilities dropped |

Compose files: [`ipa-ocr/docker-compose.yml`](ipa-ocr/docker-compose.yml), [`performance/docker-compose.yml`](performance/docker-compose.yml). The `lj-worker` stack is deployed from Git through Portainer and is not mirrored here. The Dockerfile of the image `ipa-ocr:3` is not on this host.

`ipa-ocr` uses these directories on the host (all three are bind mounts):

| Host path | In container | Used by |
|-----------|--------------|---------|
| `/srv/ipa-ocr/data` | `/data` | `ipa-ocr`, `ipa-sync` |
| `/srv/ipa-ocr/logs` | `/logs` | `ipa-ocr`, `ipa-sync`, `ipa-log` (read-only) |
| `/srv/ipa-ocr/rclone` | `/config` | `ipa-sync` (rclone configuration, not documented here) |

## Standalone containers

Both were started without a compose file, the original command is not recorded. The values below are read from `docker inspect`.

| | `portainer` | `step-ca` |
|---|-------------|-----------|
| Image | `portainer/portainer-ce:latest` | `smallstep/step-ca:latest` |
| Restart policy | `always` | `no` |
| State on 2026-11-09 | up | `Exited (0)` since the reboot |
| Ports | 8000/tcp, 9443/tcp | 9000/tcp |
| Volumes | `portainer_data` on `/data`, `/var/run/docker.sock` | `step-ca` on `/home/step` |
| Environment | | `DOCKER_STEPCA_INIT_NAME=kingma`, `DOCKER_STEPCA_INIT_DNS_NAMES=ca.kingma`, `DOCKER_STEPCA_INIT_REMOTE_MANAGEMENT=true` |

## Networks

| Name | Subnet | Bridge | State |
|------|--------|--------|-------|
| `bridge` | 172.17.0.0/16 | `docker0` | up (`portainer`, `step-ca`) |
| `lj-worker_net` | 172.18.0.0/16 | `br-1135c8f679b1` | up |
| `performance_default` | 172.19.0.0/16 | `br-f3385ecff2b3` | no carrier |
| `ipa-ocr_default` | 172.20.0.0/16 | `br-c6c9cc83d61b` | up |

## Volumes

`lj-worker_data`, `portainer_data`, `step-ca`.
