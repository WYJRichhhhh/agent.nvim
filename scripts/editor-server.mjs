import http from 'node:http';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs/promises';
import path from 'node:path';

export class EditorServer {
  constructor(emit, timeout = 10000) {
    this.emit = emit;
    this.timeout = timeout;
    this.pending = new Map();
    this.closed = false;
  }
  async start() {
    const token = crypto.randomBytes(32).toString('hex');
    const auth = Buffer.from(`Bearer ${token}`);
    this.server = http.createServer((req, res) => {
      const handle = async () => {
        const given = Buffer.from(req.headers.authorization ?? '');
        if (req.method !== 'POST' || req.url !== '/editor' || given.length !== auth.length || !crypto.timingSafeEqual(auth, given)) {
          res.writeHead(403).end(); req.resume(); return;
        }
        let body = '';
        for await (const chunk of req) {
          body += chunk;
          if (Buffer.byteLength(body) > 512 * 1024) { res.writeHead(413).end(); return; }
        }
        const value = JSON.parse(body);
        if (!['show_code', 'clear_code'].includes(value.name)) { res.writeHead(400).end(); return; }
        if (this.pending.size >= 16) { res.writeHead(429).end(); return; }
        const id = crypto.randomUUID();
        const result = await new Promise(resolve => {
          const timer = setTimeout(() => {
            this.pending.delete(id);
            resolve({ ok: false, error: 'Neovim did not respond before the editor timeout' });
          }, this.timeout);
          this.pending.set(id, { resolve, timer });
          this.emit({ type: 'editor', id, deadline: Date.now() + this.timeout, name: value.name, arguments: value.arguments });
        });
        if (!res.destroyed) res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(result));
      };
      handle().catch(() => { if (!res.headersSent && !res.destroyed) res.writeHead(400).end(); });
    });
    this.server.maxConnections = 20;
    this.server.requestTimeout = this.timeout + 5000;
    this.server.on('error', () => this.close());
    await new Promise((resolve, reject) => {
      this.server.once('error', reject);
      this.server.listen(0, '127.0.0.1', resolve);
    });
    this.env = {
      AGENT_NVIM_EDITOR_ENDPOINT: `http://127.0.0.1:${this.server.address().port}/editor`,
      AGENT_NVIM_EDITOR_TOKEN: token,
    };
    this.mcp = { type: 'stdio', command: process.execPath, args: [fileURLToPath(new URL('./editor-mcp.mjs', import.meta.url))] };
    return this;
  }
  reply(value) {
    const request = this.pending.get(value.id);
    if (!request) return;
    this.pending.delete(value.id);
    clearTimeout(request.timer);
    request.resolve(value.result);
  }
  codexArgs() {
    const name = 'mcp_servers.agent_nvim_editor.';
    return Object.entries({ command: this.mcp.command, args: this.mcp.args, env_vars: Object.keys(this.env) })
      .flatMap(([key, value]) => ['-c', name + key + '=' + JSON.stringify(value)]);
  }
  close() {
    this.closed = true;
    for (const [id] of this.pending) this.reply({ id, result: { ok: false, error: 'Agent editor session has stopped' } });
    this.server?.closeAllConnections();
    this.server?.close();
  }
}

export async function claudeEditorCommand(command, mcp, cwd) {
  const result = [], configs = [];
  for (let i = 0; i < command.length; i++) {
    const arg = command[i];
    if (arg === '--') { result.push(...command.slice(i)); break; }
    if (arg === '--mcp-config') {
      while (i + 1 < command.length && !command[i + 1].startsWith('-')) configs.push(command[++i]);
    } else if (arg.startsWith('--mcp-config=')) configs.push(arg.slice(13));
    else result.push(arg);
  }
  const servers = {};
  for (const source of configs) {
    let json = source;
    if (!source.trim().startsWith('{')) {
      const file = path.resolve(cwd, source), stat = await fs.stat(file);
      if (!stat.isFile() || stat.size > 2 * 1024 * 1024) throw new Error('MCP config must be a JSON file under 2 MiB');
      json = await fs.readFile(file, 'utf8');
    }
    const value = JSON.parse(json);
    if (!value?.mcpServers || typeof value.mcpServers !== 'object' || Array.isArray(value.mcpServers)) throw new Error('MCP config requires mcpServers');
    Object.assign(servers, value.mcpServers);
  }
  if (servers.agent_nvim_editor) throw new Error('agent_nvim_editor is reserved; rename your existing MCP server or set code.enabled=false');
  servers.agent_nvim_editor = mcp;
  const separator = result.indexOf('--');
  result.splice(separator === -1 ? result.length : separator, 0, '--mcp-config', JSON.stringify({ mcpServers: servers }));
  return result;
}
