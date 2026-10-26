#!/system/bin/sh
# dsh-mcp-termux — 首次部署 / 修复脚本（幂等，可重复运行）
# 用法: su -c "sh <插件目录>/scripts/setup.sh"
set -u

# su/root 环境可能没有 DSH 的 LD_LIBRARY_PATH，而 Termux 前缀工具
# （dirname/id/curl 等）的 RUNPATH 指向 /data/data/com.termux/files/usr/lib。
# 先补一条库路径，避免在干净的 root 环境里误判“不是 root”。
if [ -z "${LD_LIBRARY_PATH:-}" ]; then
    for _lib in /data/data/com.termux/files/usr/lib /data/data/*/files/usr/lib; do
        if [ -d "$_lib" ]; then LD_LIBRARY_PATH="$_lib"; export LD_LIBRARY_PATH; break; fi
    done
fi

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
PKG_DIR=$(dirname "$SELF_DIR")
DIR=/data/adb/mcp_re_v6
TARBALL=/data/local/tmp/mcp-termux-src.tar.gz
UNPACK=/data/local/tmp/mcp-termux-unpack
VENDOR_LIB="$PKG_DIR/vendor/libc++_shared.so"

if [ "$(id -u)" != "0" ]; then
    echo "需要 root：su -c \"sh $0\"" >&2
    exit 1
fi

echo "=== dsh-mcp-termux setup ==="
echo "插件目录: $PKG_DIR"
echo "安装目录: $DIR"

# 1. 下载（优先用本仓库自带的 deploy/，所以绝大多数情况无需联网）
if [ ! -s "$TARBALL" ]; then
    if [ -d "$PKG_DIR/deploy" ]; then
        echo "[1/6] 使用本仓库自带的 deploy/ 目录"
    else
        echo "[1/6] 下载 mcp-termux 源码包..."
        curl -L --retry 3 -m 900 -o "$TARBALL" \
            "https://codeload.github.com/PhoenixHairpin/mcp-termux/tar.gz/refs/heads/main" || {
            echo "下载失败，检查网络。也可手动放置到 $TARBALL" >&2
            exit 1
        }
    fi
else
    echo "[1/6] 复用已下载的源码包"
fi

# 2. 解压 + 部署二进制（先停掉在跑的实例，否则 Text file busy）
echo "[2/6] 部署到 $DIR ..."
# 强杀可能仍在运行的实例：cp 覆盖正在执行的二进制会报 Text file busy
pkill -9 -x mcp 2>/dev/null
pkill -9 -x mcp_boot 2>/dev/null
sleep 2
mkdir -p "$DIR"
if [ -d "$PKG_DIR/deploy" ]; then
    cp -r "$PKG_DIR/deploy/." "$DIR/" || { echo "复制失败" >&2; exit 1; }
else
    rm -rf "$UNPACK"
    mkdir -p "$UNPACK"
    tar xzf "$TARBALL" -C "$UNPACK" --strip-components=1 || { echo "解压失败" >&2; exit 1; }
    cp -r "$UNPACK/deploy/." "$DIR/" || { echo "复制失败" >&2; exit 1; }
fi
chmod 755 "$DIR/mcp" "$DIR/mcp_boot" "$DIR/stackplz" "$DIR/paradise" 2>/dev/null
chmod 755 "$DIR/radare2/bin/"* 2>/dev/null
# 2b. 修复相对符号链接：git/zip 传输常丢 symlink，r2 依赖 libr_X.so -> libr_X.so.6.1.0
echo "[2b/6] 修复 radare2 符号链接 ..."
if [ -d "$DIR/radare2/lib" ]; then
    ( cd "$DIR/radare2/lib" && for f in *.so.6.1.0; do
        [ -e "$f" ] || continue
        ln -sf "$f" "${f%.0}"
        ln -sf "$f" "${f%.6.1.0}"
      done )
fi
for b in r2 r2p; do
    [ -e "$DIR/radare2/bin/$b" ] || ln -sf radare2 "$DIR/radare2/bin/$b"
done

# 3. 补 libc++_shared.so（原包只带不兼容的 libc++.so，缺 __ndk1 符号）
echo "[3/6] 准备 libc++_shared.so ..."
LIB_DST="$DIR/preload_libs/libc++_shared.so"
LIB_SRC=""
if [ -f "$VENDOR_LIB" ]; then
    LIB_SRC="$VENDOR_LIB"
else
    for c in /data/data/com.termux/files/usr/lib/libc++_shared.so /data/data/*/files/usr/lib/libc++_shared.so; do
        [ -f "$c" ] && LIB_SRC="$c" && break
    done
fi
if [ -n "$LIB_SRC" ]; then
    cp -f "$LIB_SRC" "$LIB_DST"
    chmod 644 "$LIB_DST"
    echo "  来源: $LIB_SRC"
else
    echo "  错误: 未找到 libc++_shared.so（Termux 的 lib/ 下应有）" >&2
    echo "  可手动放置后重跑: cp <path>/libc++_shared.so $LIB_DST" >&2
    exit 1
fi

# 4. 建 Termux 兼容路径（MCP 硬编码 /data/data/com.termux/files/usr）
echo "[4/6] 建立 Termux 兼容路径 ..."
TERMUX_PREFIX=""
for p in "${PREFIX:-}" /data/data/com.termux/files/usr /data/data/com.dsharnessmobile.shell/files/usr; do
    if [ -n "$p" ] && [ -d "$p/bin" ]; then TERMUX_PREFIX="$p"; break; fi
done
[ -z "$TERMUX_PREFIX" ] && TERMUX_PREFIX=$(ls -d /data/data/*/files/usr 2>/dev/null | head -1)
if [ -n "$TERMUX_PREFIX" ]; then
    REAL_PREFIX=$(readlink -f "$TERMUX_PREFIX" 2>/dev/null)
    [ -z "$REAL_PREFIX" ] && REAL_PREFIX="$TERMUX_PREFIX"
    if [ "$REAL_PREFIX" != "/data/data/com.termux/files/usr" ]; then
        mkdir -p /data/data/com.termux/files
        ln -sfn "$REAL_PREFIX" /data/data/com.termux/files/usr
    fi
    mkdir -p /data/data/com.termux/files/usr/tmp
    chmod 777 /data/data/com.termux/files/usr/tmp
    echo "  前缀: $REAL_PREFIX"
else
    echo "  警告: 未找到 Termux prefix，shell 类工具可能失败" >&2
fi

# 5. 安装启停脚本
echo "[5/6] 安装启停脚本 ..."
cp "$SELF_DIR/ensure.sh" "$DIR/ensure.sh"
cp "$SELF_DIR/watchdog.sh" "$DIR/watchdog.sh"
cp "$SELF_DIR/uninstall.sh" "$DIR/uninstall.sh"
chmod 755 "$DIR/ensure.sh" "$DIR/watchdog.sh" "$DIR/uninstall.sh"

# 6. 启动 + 自检
echo "[6/6] 启动并自检 ..."
pkill -x mcp 2>/dev/null
pkill -x mcp_boot 2>/dev/null
sh "$DIR/ensure.sh"
sleep 3
if curl -s -m 5 http://127.0.0.1:65534/health | grep -q '"status":"ok"'; then
    echo ""
    echo "=== 部署成功 ==="
    echo "服务: http://127.0.0.1:65534/mcp"
    echo "下一步: 重启 DSH，插件会自动接管启停并挂载工具。"
    echo "卸载: 在 DSH 插件管理器点“卸载”即可；dispose 会延时调用"
    echo "      $DIR/uninstall.sh 做全量清理（进程/内核模块/目录/兼容软链）。"
else
    echo "健康检查失败，查看 $DIR/mcp.log 排查：" >&2
    tail -15 "$DIR/mcp.log" 2>/dev/null >&2
    exit 1
fi
