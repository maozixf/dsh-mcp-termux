# dsh-mcp-termux

Fork of [PhoenixHairpin/mcp-termux](https://github.com/PhoenixHairpin/mcp-termux), converted into a **DeepSeek Harness plugin**.

The upstream server (73 Android reverse-engineering tools) is kept intact under `deploy/`, `src/`, `docs/`; a plugin layer is added on top so DSH can deploy, mount and manage it.

## What you get

After install, DSH's tool list gains `mcp-termux_*` (73 tools):

| Category | Examples |
|---|---|
| eBPF tracing | `trace_syscall`, `trace_uprobe`, `trace_offset`, `hw_breakpoint` |
| Memory | `mem_read`, `mem_write`, `mem_scan`, `mem_maps`, `mem_dump` |
| radare2 | `r2_info`, `r2_disasm`, `r2_decompile`, `r2_xrefs` |
| root/process | `shell_exec`, `os_read_file`, `process_list` |
| advanced | `find_jni_methods`, `scan_crypto_signatures`, `symbolic_deobfuscate` |

## Requirements

| Item | Detail |
|---|---|
| **Root** | paradise needs an insmod'd kernel module, stackplz needs eBPF |
| **Arch** | aarch64 only |
| **Kernel** | `.ko` shipped for 5.10 / 5.15 / 6.1 / 6.6 / 6.12 |
| **curl** | used by `setup.sh` only when `deploy/` is absent |

## Install

```bash
dsh plugin --profile web add github:maozixf/mcp-termux
su -c "sh ~/.dsh/profiles/web/node_modules/dsh-mcp-termux/scripts/setup.sh"
# restart DSH
```

`setup.sh` uses this repo's own `deploy/` directory, so it does **not** download the 90 MB upstream archive.

## Lifecycle

| Event | Behavior |
|---|---|
| DSH boots | idempotent start (skipped if already running, so a reload never kills an in-flight session) |
| plugin unload / graceful exit | `pkill -x mcp; pkill -x mcp_boot` |
| DSH hard-killed | watchdog polls the Host pid; stops the server within ~5 s |

## Layout

| Path | Role |
|---|---|
| `package.json` | plugin manifest (`dsh.bundle.patch`) |
| `cordis.patch.yml` | mounts the server as `mcp-termux_*` + lifecycle row |
| `lib/index.js` | start / dispose / pid handoff |
| `scripts/setup.sh` | deploy from `deploy/`, fix libc++ and Termux prefix |
| `scripts/ensure.sh` | idempotent start + watchdog arming |
| `scripts/watchdog.sh` | stops the server when the Host pid dies |
| `locale/{en,zh}.json` | plugin-list title and description |
| `deploy/`, `src/`, `docs/` | upstream, unchanged |

## How it works

The server only speaks HTTP (no stdio transport), and `/data/adb` is exec-forbidden to the app domain (`SELinux untrusted_app`). So the plugin cannot own it as a stdio child; instead it dispatches `su -c ensure.sh <host-pid>` and the MCP client row connects to `http://127.0.0.1:65534/mcp` with backoff retry.

## Uninstall

```bash
dsh plugin --profile web remove dsh-mcp-termux
su -c "pkill -x mcp; pkill -x mcp_boot; rm -rf /data/adb/mcp_re_v6"
```

## Upstream

- Server, tool semantics and caveats: see [PhoenixHairpin/mcp-termux](https://github.com/PhoenixHairpin/mcp-termux).
- Upstream README is preserved in this repo's git history and at the upstream link above.
- `libc++_shared.so` is not vendored: `setup.sh` copies it from the device's Termux `lib/` because the upstream `libc++.so` lacks `__ndk1` symbols.

## Disclaimer

Upstream is marked "仅供学习研究使用" (study and research only). Use only on devices and applications you own or are authorized to inspect. Loading kernel modules carries bricking risk.

## License

Plugin layer: MIT. Upstream mcp-termux, radare2, stackplz and paradise keep their own licenses.
