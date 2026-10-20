import test from 'node:test';
import { codexConfigArgs, withCodexPresentation } from '../scripts/editor-policy.mjs';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import { EditorServer, claudeEditorCommand } from '../scripts/editor-server.mjs';
function client(env) {
  const child = spawn(process.execPath, [new URL('../scripts/editor-mcp.mjs', import.meta.url).pathname], { env: { ...process.env, ...env } });
  const lines = createInterface({ input: child.stdout });
  let id = 0; const pending = new Map();
  lines.on('line', line => { const value = JSON.parse(line); pending.get(value.id)?.(value); pending.delete(value.id); });
  return { child, lines, rpc(method, params) { return new Promise(resolve => {
    const requestId = ++id; pending.set(requestId, resolve); child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: requestId, method, params }) + '\n');
  }); } };
}
test('MCP discovery, authenticated acknowledged UI call, error result, shutdown and config preservation', { timeout: 15000 }, async () => {
  const calls = [];
  const server = await new EditorServer(e => {
    calls.push(e);
    setTimeout(() => server.reply({ id: e.id, result: e.arguments?.bad ? { ok: false, error: 'invalid range' } : { ok: true, file: 'source.lua' } }), 15);
  }).start();
  const c = client(server.env);
  try {
    const initialized = await c.rpc('initialize', { protocolVersion: '2025-03-26' });
    assert.equal(initialized.result.protocolVersion, '2025-03-26');
    const listed = await c.rpc('tools/list');
    assert.deepEqual(listed.result.tools.map(t => t.name), ['show_code', 'clear_code']);
    const shown = await c.rpc('tools/call', { name: 'show_code', arguments: { locations: [] } });
    assert.equal(shown.result.isError, false);
    assert.ok(calls[0].deadline > Date.now() - 1000);
    const bad = await c.rpc('tools/call', { name: 'show_code', arguments: { bad: true } });
    assert.equal(bad.result.isError, true);
    const denied = await fetch(server.env.AGENT_NVIM_EDITOR_ENDPOINT, { method: 'POST', body: '{}', headers: { Authorization: 'Bearer wrong' } });
    assert.equal(denied.status, 403);
    const merged = await claudeEditorCommand(['claude', '--mcp-config', '{"mcpServers":{"existing":{"command":"other"}}}', '--', 'prompt'], server.mcp, '/tmp');
    const entry = JSON.parse(merged[merged.indexOf('--mcp-config') + 1]);
    assert.equal(entry.mcpServers.existing.command, 'other');
    assert.equal(entry.mcpServers.agent_nvim_editor.command, process.execPath);
    assert.ok(!JSON.stringify(merged).includes(server.env.AGENT_NVIM_EDITOR_TOKEN));
    assert.ok(server.codexArgs().some(a => a.includes('env_vars=')));
    server.close();
    const stopped = await c.rpc('tools/call', { name: 'clear_code', arguments: {} });
    assert.equal(stopped.result.isError, true);
  } finally { server.close(); c.lines.close(); c.child.kill(); }
});
test('Editor timeout and closing reject pending requests instead of claiming UI success', { timeout: 5000 }, async () => {
  const server = await new EditorServer(() => {}, 30).start();
  const c = client(server.env);
  try {
    const value = await c.rpc('tools/call', { name: 'show_code', arguments: {} });
    assert.equal(value.result.isError, true);
    assert.ok(value.result.content[0].text.includes('timeout'));
  } finally { server.close(); c.lines.close(); c.child.kill(); }
});

test('Codex session rules append existing instructions and preserve CLI prompt boundaries', () => {
  const command = ['codex', '-p', 'work', '--config', 'developer_instructions="keep me"', '--config=model="chosen"', '--', '帮我来了解 manor-server的项目代码 从入口开始'];
  assert.deepEqual(codexConfigArgs(command), ['--config', 'developer_instructions="keep me"', '--config=model="chosen"']);
  const merged = withCodexPresentation(command, 'existing project rules');
  const index = merged.indexOf('-c');
  const value = JSON.parse(merged[index + 1].slice('developer_instructions='.length));
  assert.ok(value.startsWith('existing project rules\n\n'));
  assert.ok(value.includes('manor-server'));
  assert.ok(value.includes('show_code BEFORE'));
  assert.deepEqual(merged.slice(-2), command.slice(-2));
  assert.deepEqual(command.slice(-2), ['--', '帮我来了解 manor-server的项目代码 从入口开始']);
  assert.ok(index < merged.indexOf('--'));
  assert.deepEqual(codexConfigArgs(['codex', '--', '-c', 'not a config']), []);
  assert.throws(() => withCodexPresentation(command, {}), /Invalid/);
});
