/**
 * dsh-mcp-termux — lifecycle half of the MCP Termux plugin.
 *
 * The server itself (/data/adb/mcp_re_v6/mcp) is an external root daemon that
 * only speaks HTTP, so it cannot be mounted as a stdio child. This row binds
 * its lifecycle to the DSH Host through one root-side entry point:
 *
 * - boot.sh decides deployment state on the root side (the app domain cannot
 *   even stat /data/adb, so the plugin must not try): it runs setup.sh on the
 *   first launch, then hands over to the idempotent ensure.sh;
 * - start: ensure.sh starts the server (skipped when already running) and arms
 *   a watchdog bound to this Host pid;
 * - stop: kill it on dispose (plugin unload / graceful shutdown);
 * - hard-kill fallback: the watchdog stops the server within ~5 s after the
 *   Host pid disappears (SIGKILL never reaches dispose).
 *
 * @module dsh-mcp-termux
 */
import { existsSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const name = 'dsh-mcp-termux';

/** No hard service dependencies: the MCP client row owns the connection. */
export const inject = [];

/** Root-side entry shipped with this package (readable by the app domain). */
const BOOT_SCRIPT = join(dirname(fileURLToPath(import.meta.url)), '..', 'scripts', 'boot.sh');

/**
 * Run one command fully detached so it survives this Host's exit.
 * @param command - `/system/bin/sh -c` payload.
 * @param onError - spawn-failure sink; never throws to the caller.
 * @returns whether the spawn was issued.
 */
function runDetached(command, onError) {
  try {
    const child = spawn('/system/bin/sh', ['-c', command], {
      detached: true,
      stdio: 'ignore',
      env: { ...process.env, PATH: '/system/bin:/system/xbin' },
    });
    child.on('error', (error) => onError?.(error));
    child.unref();
    return true;
  } catch (error) {
    onError?.(error);
    return false;
  }
}

/**
 * @param ctx - Cordis context (logger optional).
 * @param config - optional `{ boot }` override.
 */
export function apply(ctx, config = {}) {
  const boot = config.boot || BOOT_SCRIPT;
  const warn = (message) => {
    try {
      ctx.logger?.warn?.(`dsh-mcp-termux: ${message}`);
    } catch {
      /* logging must never break lifecycle */
    }
  };

  // Only the plugin's own package is readable here; /data/adb is not.
  if (!existsSync(boot)) {
    warn(`boot script missing at ${boot} — reinstall the plugin`);
    return;
  }

  const hostPid = process.pid;
  // Absolute paths only: the Host PATH is Termux-flavoured, and inheriting the
  // app-domain LD_LIBRARY_PATH makes /system/bin binaries fail to link.
  const startCommand = `unset LD_LIBRARY_PATH LD_PRELOAD; /system/bin/su -c 'sh ${boot} ${hostPid}'`;
  const stopCommand =
    "unset LD_LIBRARY_PATH LD_PRELOAD; /system/bin/su -c 'pkill -x mcp; pkill -x mcp_boot'";

  if (runDetached(startCommand, (error) => warn(`spawn failed: ${error?.message}`))) {
    ctx.logger?.info?.('dsh-mcp-termux: boot dispatched');
  }

  let disposed = false;
  const stop = () => {
    if (disposed) return;
    disposed = true;
    runDetached(stopCommand, (error) => warn(`stop failed: ${error?.message}`));
  };
  ctx.on?.('dispose', stop);
}
