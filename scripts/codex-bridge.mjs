// Own one private App Server and observe its native TUI. stdin/stdout are JSONL.
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import crypto from 'node:crypto';
import readline from 'node:readline';
import { connect } from './websocket.mjs';

let child, ws, stopping = false, activeThread, binding = 0, seq = 0;
const requests = new Map();
const emit = value => { if (!stopping) process.stdout.write(JSON.stringify(value) + '\n'); };
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function shutdown() {
  if (stopping) return;
  stopping = true;
  try { ws?.close(); } catch {}
  if (child?.pid) {
    const kill = signal => {
      try {
        if (process.platform !== 'win32') process.kill(-child.pid, signal);
        else child.kill(signal);
      } catch {}
    };
    // npm's codex launcher can spawn a native binary. Kill the owned process group,
    // even when the launcher has already exited, so the server cannot be orphaned.
    kill('SIGTERM');
    const deadline = Date.now() + 1200;
    while (Date.now() < deadline) {
      try { process.kill(process.platform !== 'win32' ? -child.pid : child.pid, 0); } catch { break; }
      await sleep(50);
    }
    kill('SIGKILL');
  }
  process.exit(0);
}
function fatal(message) { emit({ type: 'error', message }); void shutdown(); }
function rpc(method, params) {
  const id = ++seq;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { requests.delete(id); reject(new Error(`${method} timed out`)); }, 5000);
    requests.set(id, { resolve, reject, timer });
    ws.send(JSON.stringify({ id, method, params }));
  });
}
async function bind(threadId) {
  const generation = ++binding;
  activeThread = threadId;
  emit({ type: 'thread', threadId, state: 'connecting' });
  for (let attempt = 0; !stopping && generation === binding; attempt++) {
    try {
      await rpc('thread/resume', { threadId, excludeTurns: true });
      if (generation !== binding) return;
      emit({ type: 'thread', threadId, state: 'connected' });
      // Recover edits completed before this observer subscribed. Never start a turn.
      try {
        const turns = await rpc('thread/turns/list', { threadId, limit: 1, sortDirection: 'desc', itemsView: 'notLoaded' });
        const turnId = turns.data?.[0]?.id;
        if (turnId) {
          let cursor;
          do {
            const result = await rpc('thread/items/list', { threadId, turnId, limit: 100, ...(cursor ? {cursor} : {}) });
            if (generation !== binding) return;
            for (const entry of result.data ?? []) {
              if (entry.item?.type === 'fileChange') emit({ type: 'event', method: 'item/completed', params: {threadId, turnId, item: entry.item} });
            }
            cursor = result.nextCursor;
          } while (cursor && !stopping);
        }
      } catch { /* Older servers may not support pagination; live events still work. */ }
      return;
    } catch (error) {
      // Empty native-TUI threads are not persisted until their first turn.
      // Keep waiting without warnings while the user is at the initial prompt.
      if (attempt === 8) emit({type:'thread',threadId,state:'waiting'});
      await sleep(attempt < 20 ? 250 : 1500);
    }
  }
}
async function start(options) {
  if (process.platform === 'win32') throw new Error('Codex review currently supports macOS/Linux; use codex.enabled=false for terminal-only mode on Windows');
  if (Number(process.versions.node.split('.')[0]) < 22) throw new Error('Codex bridge requires Node.js 22+');
  // Only bind localhost. A fresh capability token protects this server from other clients.
  const probe = createServer();
  await new Promise((resolve, reject) => { probe.once('error', reject); probe.listen(0, '127.0.0.1', resolve); });
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const token = crypto.randomBytes(32).toString('hex');
  const hash = crypto.createHash('sha256').update(token).digest('hex');
  const endpoint = `ws://127.0.0.1:${port}`;
  child = spawn(options.executable, ['app-server', '--listen', endpoint, '--ws-auth', 'capability-token', '--ws-token-sha256', hash], {
    cwd: options.cwd, env: process.env, detached: process.platform !== 'win32', stdio: ['ignore', 'ignore', 'pipe'],
  });
  child.stderr.resume(); // Do not mix server diagnostics/authentication data into protocol output.
  child.on('error', () => fatal('Cannot launch Codex App Server'));
  child.on('exit', () => { if (!stopping) fatal('Codex App Server exited unexpectedly; check CLI version/configuration'); });
  const deadline = Date.now() + options.timeout;
  while (!stopping) {
    try { ws = await connect(endpoint, token); break; }
    catch { if (Date.now() > deadline) throw new Error('App Server startup timed out; Codex with --remote and capability-token support is required'); await sleep(100); }
  }
  if (stopping) return;
  ws.on('error', () => fatal('Codex observer connection failed'));
  ws.on('close', () => { if (!stopping) fatal('Codex observer disconnected'); });
  ws.on('message', text => {
    let message;
    try { message = JSON.parse(text); } catch { fatal('Invalid App Server JSON'); return; }
    if (message.id !== undefined && requests.has(message.id) && !message.method) {
      const request = requests.get(message.id); requests.delete(message.id); clearTimeout(request.timer);
      message.error ? request.reject(new Error(message.error.message)) : request.resolve(message.result);
      return;
    }
    const { method, params } = message;
    // Approval and user-input requests belong to the native TUI. Never answer them here.
    if (message.id !== undefined || !params) return;
    if (method === 'thread/started') {
      const thread = params.thread;
      if (thread && thread.id !== activeThread && !thread.ephemeral && !thread.parentThreadId
          && (!thread.threadSource || thread.threadSource === 'user')
          && !(typeof thread.source === 'object' && thread.source?.subAgent)) void bind(thread.id);
    }
    if (params.threadId !== activeThread) return;
    if (['turn/started', 'turn/completed', 'turn/diff/updated'].includes(method)
        || (['item/started', 'item/completed'].includes(method) && params.item?.type === 'fileChange')) {
      emit({ type: 'event', method, params: {...params, turnId: params.turnId ?? params.turn?.id} });
    }
  });
  await rpc('initialize', {clientInfo:{name:'agent_nvim',title:'agent.nvim',version:'0.2.0'}});
  ws.send(JSON.stringify({method:'initialized'}));
  emit({ type:'ready', endpoint, token });
}
let started = false;
const input = readline.createInterface({input:process.stdin});
input.on('line', line => {
  try {
    const message = JSON.parse(line);
    if (message.type === 'stop') void shutdown();
    else if (message.type === 'start' && !started) { started = true; start(message).catch(error => fatal(error.message)); }
  } catch { fatal('Invalid bridge command'); }
});
input.on('close', shutdown);
process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown);
process.on('uncaughtException', () => fatal('Unexpected bridge failure'));
