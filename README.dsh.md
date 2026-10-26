# DSH plugin layer for mcp-termux

This fork adds a DeepSeek Harness plugin on top of the upstream mcp-termux server:

| Path | What it is |
|---|---|
| `package.json` | plugin manifest (`dsh.bundle.patch`) |
| `cordis.patch.yml` | mounts the server as `mcp-termux_*` + lifecycle row |
| `lib/index.js` | starts the root server with DSH, stops it on exit, watchdog for hard kills |
| `scripts/` | `setup.sh` deploy, `ensure.sh` idempotent start, `watchdog.sh` hard-kill cleanup |
| `locale/` | plugin-list title/description (en/zh) |
| `deploy/`, `src/`, `docs/` | upstream, unchanged |

## Install

```bash
dsh plugin --profile web add github:<owner>/mcp-termux
su -c "sh ~/.dsh/profiles/web/node_modules/dsh-mcp-termux/scripts/setup.sh"
# restart DSH
```

`setup.sh` prefers this repo's own `deploy/` directory, so no download is needed. Requires Android aarch64 + root. See upstream README below for the tool list and caveats.

---

