# dsh-mcp-termux

基于 [PhoenixHairpin/mcp-termux](https://github.com/PhoenixHairpin/mcp-termux) 的 fork，改造为 **DeepSeek Harness 插件**。

上游服务端（73 个 Android 逆向工具）完整保留在 `deploy/`、`src/`、`docs/`；插件层加在根目录，让 DSH 能部署、挂载并管理它。

## ⚠️ 先看门槛

**不满足以下条件的设备，装了也用不了，请不要安装：**

| 条件 | 说明 | 不满足的后果 |
|---|---|---|
| **Root** | KernelSU 或 Magisk，且**已授权 DSH 应用使用 su** | 无法部署、无法启动服务，全部工具不可用 |
| **架构** | 仅 aarch64（arm64） | x86 设备直接不可用 |
| **内核** | 5.10 / 5.15 / 6.1 / 6.6 / 6.12（仓库自带对应 `.ko`） | 内核模块加载失败，内存类工具不可用 |
| **Termux** | 设备上要有 Termux 的 `lib/libc++_shared.so` | `setup.sh` 找不到该库会直接退出 |

没有 root 的话，这个插件没有任何可用功能——它**不是**纯静态分析器，核心能力（eBPF 追踪、内存读写）全部依赖 root。

## 能给你什么

满足条件后，DSH 的工具列表里会出现 `mcp-termux_*`（共 73 个）：

| 类别 | 代表工具 |
|---|---|
| eBPF 动态追踪 | `trace_syscall`、`trace_uprobe`、`trace_offset`、`hw_breakpoint` |
| 内存操作 | `mem_read`、`mem_write`、`mem_scan`、`mem_maps`、`mem_dump` |
| radare2 静态分析 | `r2_info`、`r2_disasm`、`r2_decompile`、`r2_xrefs` |
| root 文件 / 进程 | `shell_exec`、`os_read_file`、`process_list` |
| 高级分析 | `find_jni_methods`、`scan_crypto_signatures`、`symbolic_deobfuscate` |

## 安装（一条命令）

```bash
dsh plugin --profile web add github:maozixf/dsh-mcp-termux
```

然后**重启 DSH**。首次启动时插件会在后台自动部署：

1. 检测到 `/data/adb/mcp_re_v6/ensure.sh` 不存在 → 用 `su` 执行 `scripts/setup.sh`
2. 从本仓库自带的 `deploy/` 复制二进制（**不额外下载** 90 MB）
3. 服务启动后，`mcp-client` 靠退避重试自动连上（重试窗口约 20 分钟）
4. 工具列表出现 `mcp-termux_*`

部署期间工具暂时不可见，属于正常现象。查看进度：

```bash
su -c "tail -f /data/adb/mcp_re_v6/mcp.log"
```

**如果自动部署失败**（没 root、KernelSU 未授权、找不到 `libc++_shared.so`），手动补一次：

```bash
su -c "sh ~/.dsh/profiles/web/node_modules/dsh-mcp-termux/scripts/setup.sh"
```

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
| `lib/index.js` | 首次部署、启动、dispose、传递 Host pid |
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

## 卸载与清理（点“卸载”即全清）

插件在 `dispose` 时做两件事：

1. 立即停掉 `mcp` / `mcp_boot`（原来就有）；
2. **延时 8 秒**后再执行一次根侧检查：如果插件包目录已经消失（也就是你真的卸载了），就调用
   `/data/adb/mcp_re_v6/uninstall.sh` 做全量清理。正常退出 DSH 时插件包还在，检查会直接跳过，不会误删。

清理范围（`scripts/uninstall.sh`）：

| 项目 | 处理 |
|---|---|
| `mcp` / `mcp_boot` / watchdog / stackplz 子进程 | 全部结束 |
| `paradise` 内核模块 | 已加载则 `rmmod`（失败会提示“重启后清除”） |
| `prefix-manifest.txt` 里登记的符号链接 | 按清单删除 |
| 部署目录 `/data/adb/mcp_re_v6` | `rm -rf` |
| `/data/data/com.termux` 兼容软链 | 仅当它确实指向某个 `files/usr` / `files/home` 时删除 |

**不清理**：jadx / openjdk 等通用工具、你自己的文件、其它应用数据。

手动执行（不装插件也能用）：

```sh
su -c "sh /data/adb/mcp_re_v6/uninstall.sh --dry-run"   # 先看会删什么
su -c "sh /data/adb/mcp_re_v6/uninstall.sh"             # 真删
```

## DSH 路径适配（v1.1 起不再依赖 `/data/data/com.termux`）

旧版把 Termux 前缀写死在二进制里（`/data/data/com.termux/files/usr`），所以在没有 Termux 的设备上必须造一个同名兼容软链，`termux_command` 还会因为写死 uid `10520` 而失效。

v1.1 的源码改为**启动时解析前缀**（`src/mcp_termux_v7.cpp`）：

1. `MCP_TERMUX_PREFIX` 环境变量（最高优先级）；
2. `$PREFIX`（且其 `bin/bash` 可执行）；
3. 真实 Termux 目录；
4. 第一个 `"/data/data/*/files/usr/bin/bash"` 命中的应用私有 prefix（DSH 就命中这一条）；
5. 都没有 → 回退到 Termux 默认路径。

`termux_command` 的身份也随之合理：前缀是 Termux 时用 `10520`，其它前缀（没有这个用户）用 `0`，并可用 `MCP_TERMUX_UID` 覆盖。

实测（本机 DSH，aarch64，无 Termux）：

```
Termux prefix: /data/data/com.dsharnessmobile.shell/files/usr
shell_exec  → PATH 直接指向该 prefix，r2 / python 可用
termux_command → uid=0，python3 3.14.8
```

因此 `deploy/mcp` 现在是**用源码重新编译**的版本；仓库不再需要等长字符串补丁。
> 如果设备上仍存在旧版创建的 `/data/data/com.termux/files/usr` 兼容软链，启动脚本会先
> `readlink -f` 它并导出 `MCP_TERMUX_PREFIX`，确保 PATH 与 `termux_command` 用的是
> 真实所有者前缀，而不是软链本身。

