// A command hook must stay silent and fail open: never approve, reject or steer a task.
import http from 'node:http';
let input = '';
try {
  for await (const chunk of process.stdin) {
    input += chunk;
    if (Buffer.byteLength(input) > 32 * 1024 * 1024) process.exit(0);
  }
  const value = JSON.parse(input);
  const body = JSON.stringify({
    hook_event_name: value.hook_event_name, session_id: value.session_id,
    source: value.source,
    agent_id: value.agent_id, tool_name: value.tool_name, tool_use_id: value.tool_use_id,
    tool_input: { file_path: value.tool_input?.file_path, notebook_path: value.tool_input?.notebook_path },
  });
  const url = new URL(process.env.AGENT_NVIM_CLAUDE_ENDPOINT);
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || url.pathname !== '/hook') process.exit(0);
  await new Promise(resolve => {
    const timer = setTimeout(() => { request.destroy(); resolve(); }, Number(process.env.AGENT_NVIM_CLAUDE_TIMEOUT) || 10000);
    const done = () => { clearTimeout(timer); resolve(); };
    const request = http.request(url, { method: 'POST', headers: {
      Authorization: `Bearer ${process.env.AGENT_NVIM_CLAUDE_TOKEN}`,
      'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body),
    } }, response => { response.resume(); response.on('end', done); });
    request.on('error', done);
    request.end(body);
  });
} catch { /* Tracking failures must not block Claude. */ }
