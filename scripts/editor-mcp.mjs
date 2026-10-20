// Minimal stdio MCP server. Protocol messages only on stdout; no SDK or login.
import http from 'node:http';
const range = { type: 'object', additionalProperties: false, properties: {
  start: { type: 'integer', minimum: 1, description: 'First line, 1-based' },
  end: { type: 'integer', minimum: 1, description: 'Last line, inclusive; omit for one line' },
  label: { type: 'string', maxLength: 200, description: 'Short explanation displayed beside this range' },
  expected_text: { type: 'string', description: 'Optional exact text of this entire range; rejects stale line numbers' },
}, required: ['start'] };
const tools = [
  { name: 'show_code', description: 'Open existing source files in the left Neovim editor and highlight key lines while explaining code. Use when the user asks to locate, open, show or explain an implementation. Read files first, use accurate 1-based ranges and preferably expected_text. No file edits. Only the first location opens; the user can browse the others. Keeps Agent focus by default; refuses unsaved buffers. Automatic edit-following pauses to keep the explanation visible.', inputSchema: {
    type: 'object', additionalProperties: false, required: ['locations'], properties: {
      title: { type: 'string', maxLength: 200 },
      focus: { type: 'boolean', default: false },
      locations: { type: 'array', minItems: 1, maxItems: 20, items: { type: 'object', additionalProperties: false, required: ['file', 'ranges'], properties: {
        file: { type: 'string', description: 'Existing file, absolute or relative to the Agent working directory' },
        ranges: { type: 'array', minItems: 1, maxItems: 50, items: range },
      } } },
    },
  }, annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false } },
  { name: 'clear_code', description: 'Clear Neovim code-explanation highlights and location list. Does not edit files or resume automatic following.', inputSchema: { type: 'object', properties: {}, additionalProperties: false }, annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false } },
];
async function invoke(name, args) {
  const url = new URL(process.env.AGENT_NVIM_EDITOR_ENDPOINT);
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || url.pathname !== '/editor') throw new Error('No active local Neovim editor endpoint');
  const body = JSON.stringify({ name, arguments: args ?? {} });
  return new Promise((resolve, reject) => {
    const req = http.request(url, { method: 'POST', headers: { Authorization: `Bearer ${process.env.AGENT_NVIM_EDITOR_TOKEN}`, 'Content-Type': 'application/json' } }, res => {
      let result = '';
      res.on('data', chunk => { result += chunk; if (result.length > 1024 * 1024) req.destroy(new Error('Editor response too large')); });
      res.on('end', () => {
        if (res.statusCode !== 200) return reject(new Error(`Editor connection rejected (${res.statusCode})`));
        try { resolve(JSON.parse(result)); } catch { reject(new Error('Invalid editor response')); }
      });
    });
    req.setTimeout(15000, () => req.destroy(new Error('Editor request timed out')));
    req.on('error', reject);
    req.end(body);
  });
}
async function handle(message) {
  if (!message || typeof message !== "object") return;
  if (message.id === undefined) return;
  const reply = result => process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: message.id, result }) + '\n');
  const error = (code, text) => process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: message.id, error: { code, message: text } }) + '\n');
  if (message.method === 'initialize') return reply({
    protocolVersion: ['2024-11-05', '2025-03-26', '2025-06-18'].includes(message.params?.protocolVersion) ? message.params.protocolVersion : '2024-11-05',
    capabilities: { tools: {} }, serverInfo: { name: 'agent.nvim editor', version: '0.4.0' },
    instructions: 'When asked to show or explain source code, read the code and use show_code to display key lines in Neovim. Do not modify files merely to highlight them.',
  });
  if (message.method === 'ping') return reply({});
  if (message.method === 'tools/list') return reply({ tools });
  if (message.method !== 'tools/call') return error(-32601, 'Method not found');
  if (!tools.some(tool => tool.name === message.params?.name)) return error(-32602, 'Unknown tool');
  try {
    const result = await invoke(message.params.name, message.params.arguments);
    reply({ content: [{ type: 'text', text: JSON.stringify(result) }], isError: !result.ok });
  } catch (e) { reply({ content: [{ type: 'text', text: e.message }], isError: true }); }
}
let pending = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  pending += chunk;
  if (pending.length > 1024 * 1024) { process.exitCode = 1; process.stdin.destroy(); return; }
  let at;
  while ((at = pending.indexOf('\n')) !== -1) {
    const line = pending.slice(0, at); pending = pending.slice(at + 1);
    try { void handle(JSON.parse(line)); } catch { /* Ignore malformed protocol input. */ }
  }
});
