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
 *   Host pid disappears (SIGKILL never reaches dispose);
 * - uninstall cleanup: when the package itself disappears (GUI or `dsh plugin
 *   remove`), dispose schedules a root-side script that waits a few seconds and
 *   then verifies the package is really gone before wiping the deployment.
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

/** This package's root — used by the uninstall check. */
const PACKAGE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');

/** Root-side teardown shipped with the deployment (not with this package). */
const UNINSTALL_SCRIPT = '/data/adb/mcp_re_v6/uninstall.sh';

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

  const cleanupOnUninstall = config.cleanupOnUninstall !== false;
  const cleanupDelayMs = Number.isFinite(config.cleanupDelayMs)
    ? Math.max(1000, config.cleanupDelayMs)
    : 2000;
  // Uninstall cleanup runs *after* the package is gone: dispose fires before the
  // plugin manager removes the directory, so the script waits, then checks for
  // package.json before touching anything. A normal host shutdown keeps the
  // package in place, so nothing is deleted by accident.
  const cleanupCommand =
    `unset LD_LIBRARY_PATH LD_PRELOAD; /system/bin/sh -c "sleep ${Math.round(cleanupDelayMs / 1000)}; ` +
    `/system/bin/su -c 'sh ${UNINSTALL_SCRIPT} --if-orphan ${PACKAGE_DIR}'"`;

  if (runDetached(startCommand, (error) => warn(`spawn failed: ${error?.message}`))) {
    ctx.logger?.info?.('dsh-mcp-termux: boot dispatched');
  }

  let disposed = false;
  const stop = () => {
    if (disposed) return;
    disposed = true;
    runDetached(stopCommand, (error) => warn(`stop failed: ${error?.message}`));
    if (cleanupOnUninstall) {
      runDetached(cleanupCommand, (error) => warn(`cleanup failed: ${error?.message}`));
    }
  };
  ctx.on?.('dispose', stop);
}
