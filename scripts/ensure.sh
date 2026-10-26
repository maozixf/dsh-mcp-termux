#!/system/bin/sh
# mcp-termux 幂等启动 + 生命周期看门狗
# 用法: ensure.sh [HOST_PID]
DIR=/data/adb/mcp_re_v6
# The binary resolves TERMUX_PREFIX itself, but the compatibility symlink at
# /data/data/com.termux/files/usr can win before the app-private prefix.
# Point it at the real owner so PATH and termux_command use that identity.
if [ -z "${MCP_TERMUX_PREFIX:-}" ] && [ -L /data/data/com.termux/files/usr ]; then
    _real=$(readlink -f /data/data/com.termux/files/usr 2>/dev/null)
    [ -n "$_real" ] && export MCP_TERMUX_PREFIX="$_real"
fi
HOST_PID="$1"

# 回收旧看门狗（Host 重启时由新实例接管）
if [ -f "$DIR/watchdog.pid" ]; then
    OLD=$(cat "$DIR/watchdog.pid" 2>/dev/null)
    [ -n "$OLD" ] && kill "$OLD" 2>/dev/null
    rm -f "$DIR/watchdog.pid"
fi

if pidof mcp >/dev/null 2>&1; then
    echo "$(date '+%F %T') already running pid=$(pidof mcp)" >> "$DIR/autostart.log"
else
    export LD_LIBRARY_PATH=$DIR/preload_libs
    cd $DIR || exit 1
    nohup ./mcp -h 127.0.0.1 -p 65534 > mcp.log 2>&1 &
    nohup ./mcp_boot > boot.log 2>&1 &
    sleep 2
    iptables -I INPUT -p tcp --dport 65534 ! -i lo -j DROP 2>/dev/null
    iptables -I INPUT -p tcp --dport 65533 ! -i lo -j DROP 2>/dev/null
    echo "$(date '+%F %T') DSH-triggered start pid=$(pidof mcp)" >> "$DIR/autostart.log"
fi

# 绑定到当前 Host 进程：Host 消失（含强杀）则停服务
if [ -n "$HOST_PID" ]; then
    nohup sh "$DIR/watchdog.sh" "$HOST_PID" >/dev/null 2>&1 &
    echo $! > "$DIR/watchdog.pid"
    echo "$(date '+%F %T') watchdog armed for host pid=$HOST_PID" >> "$DIR/autostart.log"
fi
