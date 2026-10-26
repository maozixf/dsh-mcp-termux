# 更新日志

插件层的变化记录在这里；服务端能力与上游变更请见 [PhoenixHairpin/mcp-termux](https://github.com/PhoenixHairpin/mcp-termux)。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本。

## [1.1.0] - 2026-10-26

### 新增

- 卸载全量清理：`scripts/uninstall.sh`。插件 `dispose` 时延时 8 秒做一次根侧复查（`--if-orphan`），确认插件包确实已移除后才清理；清理进程、`paradise` 内核模块、部署目录与 `/data/data/com.termux` 兼容软链。
- `docs/uninstall.md`：清理范围、手动用法、常见问题。

### 变更

- 服务端改为**启动时解析前缀**：`MCP_TERMUX_PREFIX` → `$PREFIX` → 真实 Termux → 应用私有 prefix；不再依赖写死的 `/data/data/com.termux/files/usr`。
- `termux_command` 身份：前缀为 Termux 时用 uid `10520`，其它前缀用 `0`，可用 `MCP_TERMUX_UID` 覆盖。
- `deploy/mcp` 用源码重新编译（clang 21 / NDK r30 / Android 24），RUNPATH 指向运行时解析到的前缀。
- `ensure.sh`：检测到兼容软链时用 `readlink -f` 解析真实前缀并导出 `MCP_TERMUX_PREFIX`，避免路径与身份被软链带偏。

### 修复

- 重启后 `termux_command` 偶发回退到 uid `10520`、`python3` 不可用（前缀被兼容软链抢先匹配）。
- 从仓库部署时，radare2 的相对符号链接（`libr_*.so` → `libr_*.so.6.1.0`、`r2`/`r2p` → `radare2`）在 git/zip 传输中丢失，导致 r2 系列工具报 `CANNOT LINK ... libr_cons.so`；`setup.sh` 现在部署后自动重建这些链接。

## [1.0.1] - 2026-10-26

### 新增

- 首次启动自动部署，`mcp-client` 重连窗口放宽到约 20 分钟。

### 修复

- 部署状态判断移到 root 侧：app 域无法 `stat /data/adb`。

## [1.0.0] - 2026-10-26

### 新增

- MCP Termux 以 DSH 插件形式发布：部署、随 Host 启停、73 个工具挂载为 `mcp-termux_*`。
