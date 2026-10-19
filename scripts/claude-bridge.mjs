import http from 'node:http';
import crypto from 'node:crypto';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs/promises';
import { ClaudeReview, augmentCommand } from './claude-review.mjs';

let server, review, hookTimer, startupTimer, stopping = false, started = false, queue = Promise.resolve();
const emit = value => { if (!stopping) process.stdout.write(JSON.stringify(value) + '\n'); };
const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
function shutdown() {
  if (stopping) return;
  stopping = true;
  clearTimeout(hookTimer);
  clearTimeout(startupTimer);
  review?.close();
  server?.closeAllConnections();
  server?.close();
  process.exit(0);
}
async function start(options) {
  if (process.platform === 'win32') throw new Error('Claude review currently supports macOS/Linux; use claude.enabled=false on Windows');
  if (Number(process.versions.node.split('.')[0]) < 22) throw new Error('Claude review requires Node.js 22+');
  startupTimer = setTimeout(() => { emit({ type: 'error', message: 'Claude bridge startup timed out' }); shutdown(); }, options.timeout);
  await promisify(execFile)('git', ['--version'], { timeout: 3000 });
  const token = crypto.randomBytes(32).toString('hex');
  const auth = Buffer.from(`Bearer ${token}`);
  review = new ClaudeReview(await fs.realpath(options.cwd), options.review, emit);
  await review.git.discover();
  const handle = async (request, response) => {
    const given = Buffer.from(request.headers.authorization ?? '');
    if (request.method !== 'POST' || request.url !== '/hook' || given.length !== auth.length || !crypto.timingSafeEqual(auth, given)) {
      response.writeHead(403).end(); request.resume(); return;
    }
    let body = '';
    for await (const chunk of request) {
      body += chunk;
      if (Buffer.byteLength(body) > 128 * 1024) { response.writeHead(413).end(); return; }
    }
    let event;
    try { event = JSON.parse(body); } catch { response.writeHead(400).end(); return; }
    response.on('close', () => {
      if (!response.writableEnded) review.warn('timeout', 'Claude hook disconnected before tracking finished; some changes may be missing.');
    });
    queue = queue.then(() => review.handle(event)).catch(() => {
      review.warn('hook', 'Claude review hook failed; the CLI continues, but some changes may be missing.');
    });
    await queue;
    if (review.sessionId) clearTimeout(hookTimer);
    if (!response.destroyed) response.writeHead(200, { 'Content-Type': 'application/json' }).end('{}');
  };
  server = http.createServer((request, response) => {
    handle(request, response).catch(() => {
      if (!response.destroyed) response.writeHead(400).end();
    });
  });
  server.maxConnections = 16;
  server.requestTimeout = options.hook_timeout + 5000;
  server.on('error', () => { emit({ type: 'error', message: 'Claude review listener failed' }); shutdown(); });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  if (stopping) return;
  const hookCommand = `${quote(process.execPath)} ${quote(fileURLToPath(new URL('./claude-hook.mjs', import.meta.url)))}`;
  const hooks = {};
  for (const event of ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'Stop', 'SessionEnd']) {
    hooks[event] = [{ hooks: [{ type: 'command', command: hookCommand, timeout: Math.ceil(options.hook_timeout / 1000) + 1 }] }];
  }
  const command = await augmentCommand(options.command, hooks, options.cwd);
  clearTimeout(startupTimer);
  hookTimer = setTimeout(() => emit({ type: 'warning', message: 'Claude Hooks have not connected yet. Accept workspace trust and check /hooks, disableAllHooks and managed policy; the terminal continues without tracked edits until hooks run.' }), options.timeout);
  emit({ type: 'ready', state: 'waiting', command, env: {
    AGENT_NVIM_CLAUDE_ENDPOINT: `http://127.0.0.1:${server.address().port}/hook`,
    AGENT_NVIM_CLAUDE_TOKEN: token,
    AGENT_NVIM_CLAUDE_TIMEOUT: String(options.hook_timeout),
  } });
}
const input = readline.createInterface({ input: process.stdin });
input.on('line', line => {
  try {
    const value = JSON.parse(line);
    if (value.type === 'stop') shutdown();
    if (value.type === 'start' && !started) {
      started = true;
      start(value).catch(error => { emit({ type: 'error', message: `Claude review startup failed: ${error.message}` }); shutdown(); });
    }
  } catch { emit({ type: 'error', message: 'Invalid Claude bridge command' }); shutdown(); }
});
input.on('close', shutdown);
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
