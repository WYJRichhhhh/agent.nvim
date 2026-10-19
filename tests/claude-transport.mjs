import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createInterface } from 'node:readline';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const opts = { git_fallback: true, worktrees: true, restrict_to_cwd: true, max_diff_bytes: 1048576, max_snapshot_bytes: 8388608 };
const hookPath = new URL('../scripts/claude-hook.mjs', import.meta.url);
function hook(env, payload) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [hookPath.pathname], { env: { ...process.env, ...env } });
    let stdout = '', stderr = '';
    child.stdout.on('data', c => stdout += c); child.stderr.on('data', c => stderr += c);
    child.on('error', reject); child.on('close', code => resolve({ code, stdout, stderr }));
    child.stdin.end(JSON.stringify(payload));
  });
}

test('authenticated hook transport is silent, excludes unrelated sessions, closes listener and fails open after shutdown', { timeout: 15000 }, async () => {
  const dir = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'claude-http-')));
  const child = spawn(process.execPath, [new URL('../scripts/claude-bridge.mjs', import.meta.url).pathname]);
  const lines = createInterface({ input: child.stdout });
  const messages = [];
  lines.on('line', line => messages.push(JSON.parse(line)));
  try {
    const ready = new Promise((resolve, reject) => {
      lines.on('line', line => { const e = JSON.parse(line); if (e.type === 'ready') resolve(e); if (e.type === 'error') reject(new Error(e.message)); });
      child.on('exit', () => reject(new Error('bridge exited before ready')));
    });
    child.stdin.write(JSON.stringify({ type: 'start', command: ['claude'], cwd: dir, timeout: 5000, hook_timeout: 2000, review: opts }) + '\n');
    const { env, command } = await ready;
    const settings = JSON.parse(command[command.indexOf('--settings') + 1]);
    assert.ok(settings.hooks.PostToolUse && settings.hooks.PreToolUse);
    assert.ok(!JSON.stringify(command).includes(env.AGENT_NVIM_CLAUDE_TOKEN));
    const response = await fetch(env.AGENT_NVIM_CLAUDE_ENDPOINT, { method: 'POST', body: '{}', headers: { Authorization: 'Bearer invalid' } });
    assert.equal(response.status, 403);
    const payload = { hook_event_name: 'SessionStart', session_id: 'our-session', tool_input: { content: 'do not forward this content' } };
    assert.deepEqual(await hook(env, payload), { code: 0, stdout: '', stderr: '' });
    assert.ok(messages.some(e => e.threadId === 'our-session'));
    assert.deepEqual(await hook(env, { ...payload, session_id: 'other-session' }), { code: 0, stdout: '', stderr: '' });
    assert.ok(!messages.some(e => e.threadId === 'other-session'));
    const exit = once(child, 'exit');
    child.stdin.end('{"type":"stop"}\n');
    await exit;
    assert.deepEqual(await hook(env, payload), { code: 0, stdout: '', stderr: '' });
  } finally {
    lines.close(); child.kill(); await fs.rm(dir, { recursive: true, force: true });
  }
});
