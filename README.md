# dsh-mcp-termux

基于 [PhoenixHairpin/mcp-termux](https://github.com/PhoenixHairpin/mcp-termux) 的 fork，改造为 **DeepSeek Harness 插件**。

上游服务端（73 个 Android 逆向工具）完整保留在 `deploy/`、`src/`、`docs/`；插件层加在根目录，让 DSH 能部署、挂载并管理它。

## 能给你什么

安装后 DSH 的工具列表里会出现 `mcp-termux_*`（共 73 个），包括：

| 类别 | 代表工具 |
|---|---|
| eBPF 动态追踪 | `trace_syscall`、`trace_uprobe`、`trace_offset`、`hw_breakpoint` |
| 内存操作 | `mem_read`、`mem_write`、`mem_scan`、`mem_maps`、`mem_dump` |
| radare2 静态分析 | `r2_info`、`r2_disasm`、`r2_decompile`、`r2_xrefs` |
| root 文件 / 进程 | `shell_exec`、`os_read_file`、`process_list` |
| 高级分析 | `find_jni_methods`、`scan_crypto_signatures`、`symbolic_deobfuscate` |

## 前提条件

| 条件 | 说明 |
|---|---|
| **Root** | paradise 需要 insmod 内核模块，stackplz 需要 eBPF；无 root 时大部分工具不可用 |
| **架构** | 仅 aarch64（arm64） |
| **内核** | 随包提供 5.10 / 5.15 / 6.1 / 6.6 / 6.12 的 `.ko`，不匹配则内存类工具不可用 |
| **curl** | 仅当仓库内 `deploy/` 缺失时才需要下载 |

## 安装

```bash
# 1. 安装插件
dsh plugin --profile web add github:maozixf/mcp-termux

# 2. 首次部署（需要 root，约 90 MB 部署体积）
su -c "sh ~/.dsh/profiles/web/node_modules/dsh-mcp-termux/scripts/setup.sh"

# 3. 重启 DSH
```

`setup.sh` 直接使用本仓库自带的 `deploy/` 目录，**不会额外下载** 90 MB 上游压缩包。

## 生命周期

| 事件 | 行为 |
|---|---|
| DSH 启动 | 幂等拉起服务（已在运行则跳过，不打断进行中的任务） |
| 插件卸载 / DSH 正常退出 | 立即 `pkill -x mcp; pkill -x mcp_boot` |
| DSH 被强杀 / 划掉后台 | 看门狗轮询 Host 进程 pid，约 5 秒内停止服务 |

## 目录结构

| 路径 | 作用 |
|---|---|
| `package.json` | 插件清单（`dsh.bundle.patch`） |
| `cordis.patch.yml` | 挂载 73 个工具为 `mcp-termux_*`，并插入生命周期行 |
| `lib/index.js` | 启动 / dispose / 传递 Host pid |
| `scripts/setup.sh` | 从 `deploy/` 部署，修 libc++ 与 Termux 路径 |
| `scripts/ensure.sh` | 幂等启动 + 武装看门狗 |
| `scripts/watchdog.sh` | Host 进程消失后停止服务 |
| `locale/{en,zh}.json` | 插件列表的标题与描述 |
| `deploy/`、`src/`、`docs/` | 上游内容，未改动 |

## 实现原理

服务端只实现了 HTTP 传输（没有 stdio），且 `/data/adb` 对 app 域禁止执行（`SELinux untrusted_app`），所以插件无法把它当 stdio 子进程管理。实际做法是：

1. 插件在 Host 启动时执行 `su -c ensure.sh <host-pid>`，由 root 侧拉起服务；
2. `cordis.patch.yml` 里的 `mcp-client` 行连接 `http://127.0.0.1:65534/mcp`，带指数退避重试；
3. 看门狗盯着 Host pid，进程消失即停服务，覆盖 `SIGKILL` 收不到 `dispose` 的情况。

## 卸载

```bash
dsh plugin --profile web remove dsh-mcp-termux
su -c "pkill -x mcp; pkill -x mcp_boot; rm -rf /data/adb/mcp_re_v6"
```

## 上游

- 服务端能力、工具语义与已知限制：见 [PhoenixHairpin/mcp-termux](https://github.com/PhoenixHairpin/mcp-termux)。
- 上游 README 保留在本仓库的 git 历史中，也可通过上面的链接查看。
- 仓库**不内置** `libc++_shared.so`：上游的 `libc++.so` 缺 `__ndk1` 符号，`setup.sh` 会从设备 Termux 的 `lib/` 复制一份可用的。

## 免责声明

上游标注「仅供学习研究使用」。请仅对自己拥有或已获授权的设备与应用使用。加载内核模块存在变砖风险，请确认有恢复手段后再安装。

## 许可

插件层代码为 MIT。上游 mcp-termux、radare2、stackplz、paradise 各自遵循其原有许可。
