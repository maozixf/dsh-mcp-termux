# 卸载与全量清理

## 一句话

在 DSH 插件管理器点「卸载」即可。插件在 `dispose` 里延时 8 秒做一次根侧检查，确认插件包真的没了才全量清理；正常退出 DSH 不会误删。

## 触发链路

```
DSH 插件管理器「卸载」
   └─ 移除插件包目录 + 调用插件 dispose
        ├─ 立即：su -c 'pkill -x mcp; pkill -x mcp_boot'
        └─ 延时 8s：su -c 'sh /data/adb/mcp_re_v6/uninstall.sh --if-orphan <包目录>'
              └─ 若 <包目录>/package.json 仍存在 → 跳过（说明只是正常退出）
              └─ 否则 → 全量清理
```

为什么延时：`dispose` 触发时包目录通常还没被删掉，立即判断会误判成“仍在安装”。延时 + 复查 `package.json` 是这套方案的关键。

## 清理了什么

| 项目 | 说明 |
|---|---|
| 进程 | `mcp`、`mcp_boot`、watchdog、`stackplz` 子进程 |
| 内核模块 | `paradise`（`rmmod`；被占用时提示重启清除） |
| 前缀里的符号链接 | 安装时登记在 `/data/adb/mcp_re_v6/prefix-manifest.txt` |
| 部署目录 | `/data/adb/mcp_re_v6`（含日志、二进制、模块） |
| 兼容软链 | `/data/data/com.termux`（仅当它指向某个 `files/usr` / `files/home`） |

## 没清理什么（有意为之）

- `jadx` / `openjdk` / `aapt2` 等通用工具——它们是设备级工具，不属于这个插件；
- 你自己的文件、其它应用数据；
- DSH 本体与其它插件。

## 手动用法

```sh
# 1) 预演：只打印将要执行的动作
su -c "sh /data/adb/mcp_re_v6/uninstall.sh --dry-run"

# 2) 只清环境登记、保留部署（调试用）
su -c "sh /data/adb/mcp_re_v6/uninstall.sh --keep-env"

# 3) 真删
su -c "sh /data/adb/mcp_re_v6/uninstall.sh"
```

## 常见问题

| 现象 | 处理 |
|---|---|
| 卸载后 `/data/adb/mcp_re_v6` 还在 | 插件包可能仍在（检查目录里有没有 `package.json`），或 dispose 未执行（强杀/DISABLE）。手动跑一次 uninstall.sh |
| `rmmod paradise` 失败 | 模块仍被占用；重启后自然清除，或先 `pkill -f stackplz` 再试 |
| 想留档再卸载 | 先 `su -c "cp -r /data/adb/mcp_re_v6 /sdcard/mcp_re_v6_backup"` |
| 重装后工具没出现 | 重启 DSH；首次启动会在后台重新部署，等 1–2 分钟 |
