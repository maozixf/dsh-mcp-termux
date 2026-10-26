#!/system/bin/sh
# dsh-mcp-termux — 彻底卸载（root 侧）
#
# usage: uninstall.sh [--if-orphan <plugin-package-dir>] [--keep-env] [--dry-run]
#
# 清理范围：
#   1. 停止 mcp / mcp_boot / watchdog / stackplz 子进程
#   2. 卸载 paradise 内核模块（若已加载）
#   3. 按 manifest 删除本插件在 Termux 前缀里建立的符号链接
#   4. 删除部署目录 /data/adb/mcp_re_v6
#   5. 删除 /data/data/com.termux 兼容软链（仅当它指向某个 files/usr|files/home）
# 不清理：jadx/openjdk 等通用工具、设备上的其它数据、用户自己的文件。
set -u

DIR=/data/adb/mcp_re_v6
MANIFEST="$DIR/prefix-manifest.txt"

# 本脚本可能就住在 $DIR 里，删除自身会导致后续行读不到：先搬到 /data/local/tmp
case "$0" in
  "$DIR"/*)
    TMP=/data/local/tmp/.dsh_mcp_uninstall.sh
    cp -f "$0" "$TMP" 2>/dev/null && chmod 700 "$TMP" 2>/dev/null && exec /system/bin/sh "$TMP" "$@"
    ;;
esac

IF_ORPHAN_PKG=""
KEEP_ENV=0
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --if-orphan) IF_ORPHAN_PKG="${2:-}"; shift 2 ;;
    --keep-env) KEEP_ENV=1; shift ;;
    --dry-run) DRY=1; shift ;;
    *) shift ;;
  esac
done

say() { echo "[uninstall] $*"; }
run() { if [ "$DRY" = 1 ]; then echo "  would: $*"; else "$@"; fi }

[ "$(id -u)" = 0 ] || { echo "需要 root：su -c \"sh $0\"" >&2; exit 1; }

# 只在“插件包已不在”时继续；供插件 dispose 延时调用，避免正常退出时误清
if [ -n "$IF_ORPHAN_PKG" ] && [ -e "$IF_ORPHAN_PKG/package.json" ]; then
  say "plugin still installed at $IF_ORPHAN_PKG — nothing to do"
  exit 0
fi

say "stopping processes"
run pkill -x mcp
run pkill -x mcp_boot
run pkill -f "$DIR/watchdog.sh"
[ -f "$DIR/watchdog.pid" ] && run kill "$(cat "$DIR/watchdog.pid" 2>/dev/null)" 2>/dev/null
run pkill -f "$DIR/stackplz"
sleep 1

if lsmod 2>/dev/null | grep -q '^paradise '; then
  say "unloading paradise kernel module"
  if [ "$DRY" = 1 ]; then
    echo "  would: rmmod paradise"
  elif rmmod paradise 2>/dev/null; then
    say "  paradise unloaded"
  else
    say "  rmmod failed (module busy?) — a reboot clears it"
  fi
fi

if [ "$KEEP_ENV" = 0 ] && [ -f "$MANIFEST" ]; then
  say "removing plugin-owned symlinks in the Termux prefix"
  while IFS= read -r p; do
    [ -n "$p" ] && [ -L "$p" ] && run rm -f "$p"
  done < "$MANIFEST"
fi

say "removing deployment directory $DIR"
run rm -rf "$DIR"

# 兼容软链：只在它确实指向某个 files/usr|files/home 时删除，避免误删真实 Termux
for l in /data/data/com.termux/files/usr /data/data/com.termux/files/home; do
  if [ -L "$l" ]; then
    tgt=$(readlink "$l" 2>/dev/null)
    case "$tgt" in
      */files/usr|*/files/home) run rm -f "$l" ;;
    esac
  fi
done
run rmdir /data/data/com.termux/files 2>/dev/null
run rmdir /data/data/com.termux 2>/dev/null

rm -f /data/local/tmp/.dsh_mcp_uninstall.sh 2>/dev/null
say "done. 插件目录可随后从 DSH 插件管理器移除。"
