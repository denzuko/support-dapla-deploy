# chat-dapla-deploy

Roswell/Consfigurator deploy of [Stoat](https://stoat.chat) (formerly Revolt)
at `chat.dapla.net`. Stoat is a self-hosted, open-source Discord alternative
with text channels, roles, bots, and iOS/Android/web clients.

## Architecture

```
Cloudflare edge
  └── HAProxy (TLS termination, WebSocket upgrade routing, security headers)
        ├── stoat:3000       (API + web client, 127.0.0.1 only)
        ├── stoat:3001       (WebSocket events endpoint, 127.0.0.1 only)
        └── stoat-files:3003 (S3-compatible file server, 127.0.0.1 only)
              ↕ internal network
              stoat-db    (mongo:6)
              stoat-cache (KeyDB/Redis-compatible)
```

All containers run rootless under the `stoat` service account. Four
AES-256-GCM-encrypted ZFS datasets back the service account home, MongoDB,
file uploads, and the KeyDB cache. Images are mirrored via `oci.dapla.net`.

Voice (LiveKit/WebRTC) is out of scope for this deploy. UDP ports 50000–50100
and TCP 7881 are not provisioned here.

## Repository Layout

```
chat-dapla-deploy.ros   Thin Roswell entry point
chat-dapla-deploy.asd   Umbrella ASDF system definition
qlfile                   Qlot dependency pins
src/deploy.lisp          Consfigurator properties and DEFHOST
src/docs.lisp            40ants-doc sections
t/e2e.lisp               Post-deploy FiveAM smoke tests
docs.ros                 Documentation generator
Makefile                 build / test / doc / dist / clean
```

## Prerequisites

- Roswell with SBCL
- Qlot (`ros install qlot`)
- Rootless Podman ≥ 4.4 with quadlet support
- Systemd user session with lingering enabled
- HAProxy ≥ 2.6 (WebSocket tunnel timeout configured globally)
- ZFS with `storage/users` and `storage/containers` pools
- `oci.dapla.net` mirrors for `mongo:6`, `eqalpha/keydb`, `stoatchat/autumn`, `stoatchat/backend`

## Installation

```sh
ros install qlot
qlot add cl-inix consfigurator fiveam dexador
./chat-dapla-deploy.ros
```

The script provisions via Consfigurator over a `:local` connection: ZFS datasets
(encrypted), service account, linger, secrets file, Revolt.toml, image pulls,
five quadlet units (network + four containers), and the HAProxy vhost.

## Client Access

| Platform | How |
|----------|-----|
| Web      | `https://chat.dapla.net` |
| Desktop  | Stoat app → Settings → Custom instance URL |
| iOS/Android | Stoat app → Settings → Custom instance URL |

## Runbook

```sh
machinectl shell stoat@ -- systemctl --user status stoat-db stoat-cache stoat-files stoat
machinectl shell stoat@ -- journalctl --user -u stoat -f
machinectl shell stoat@ -- systemctl --user restart stoat
machinectl shell stoat@ -- podman auto-update
```

Redeploy by re-running `./chat-dapla-deploy.ros`. Consfigurator's check/apply
cycle is idempotent; only changed properties are applied.

## Playbook

### ZFS replication (rsync.net)

```sh
for ds in stoat-db stoat-files stoat-cache; do
  zfs snapshot storage/containers/${ds}@$(date +%Y%m%d)
  zfs send -w storage/containers/${ds}@$(date +%Y%m%d) | \
    ssh user@rsync.net zfs receive backup/${ds}
done
```

Key files under `/etc/zfs-keys/` must be backed up separately from the ZFS snapshots.

## Decommission

```sh
machinectl shell stoat@ -- systemctl --user stop stoat stoat-files stoat-cache stoat-db
machinectl shell stoat@ -- systemctl --user disable stoat stoat-files stoat-cache stoat-db
# Destroy datasets only when data loss is acceptable:
zfs destroy -r storage/users/stoat
zfs destroy -r storage/containers/stoat-db
zfs destroy -r storage/containers/stoat-files
zfs destroy -r storage/containers/stoat-cache
```

## License

BSD 3-Clause. See [LICENSE](LICENSE).
