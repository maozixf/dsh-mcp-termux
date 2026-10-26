#!/system/bin/sh
# 启动入口：在 root 侧判断部署状态（app 身份读不到 /data/adb）
# 用法: boot.sh <HOST_PID>
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
DIR=/data/adb/mcp_re_v6
HOST_PID="$1"

if [ -f "$DIR/ensure.sh" ]; then
    # 已部署：幂等启动 + 武装看门狗
    sh "$DIR/ensure.sh" "$HOST_PID"
elif [ -f "$SELF_DIR/setup.sh" ]; then
    # 未部署：首次自动部署，然后启动
    echo "[boot] not deployed -> running setup"
    sh "$SELF_DIR/setup.sh"
    [ -f "$DIR/ensure.sh" ] && sh "$DIR/ensure.sh" "$HOST_PID"
else
    echo "[boot] neither ensure.sh nor setup.sh found" >&2
    exit 1
fi
