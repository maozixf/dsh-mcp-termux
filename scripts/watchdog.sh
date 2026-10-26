#!/system/bin/sh
# 看门狗：监视 DSH Host 进程，消失后停止 mcp（覆盖 SIGKILL 等 dispose 收不到的情况）
DIR=/data/adb/mcp_re_v6
HOST_PID="$1"

[ -z "$HOST_PID" ] && exit 1

while kill -0 "$HOST_PID" 2>/dev/null; do
    sleep 5
done

pkill -x mcp 2>/dev/null
pkill -x mcp_boot 2>/dev/null
echo "$(date '+%F %T') host pid=$HOST_PID gone -> mcp stopped" >> "$DIR/autostart.log"
rm -f "$DIR/watchdog.pid"
