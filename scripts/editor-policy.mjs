import { spawn } from 'node:child_process';
import readline from 'node:readline';
// Session and MCP guidance share one workflow. No global instruction files are changed.
export const presentationPolicy = [
  'You are working inside Neovim with a live code editor beside the conversation.',
  'For repository-specific questions asking to learn or tour a project from its entry point, where code lives, what implements a feature, how code works, or why a behavior occurs, use show_code BEFORE the explanatory answer once you have read and verified the relevant source.',
  'This is the default code-explanation workflow, including follow-up questions; the user does not need to request a tool, say show_code, or explicitly ask to open a file.',
  'Read/search the source first, then display a small set of accurate key ranges with short explanatory labels, then explain those displayed lines. Put the most relevant file first, leave focus=false, and prefer expected_text.',
  'Example: "帮我来了解 manor-server的项目代码 从入口开始" means locate the entry point, read it, call show_code to open and highlight it, then explain the startup flow. Example: "订单校验在哪里实现的？" means locate and read the implementation, call show_code on its key lines, then answer. "这段逻辑为什么会重试？" also calls for showing the verified retry logic before explaining it.',
  'Respect requests not to switch the editor. Do not call merely for generic programming questions, progress updates, every search/read, or routine edit/test completion; edit-following already handles modifications.',
  'Never guess paths or line numbers or edit files just to highlight them. If the tool fails, explain the limitation without claiming the editor changed or retrying in a loop.',
].join(' ');

export function codexConfigArgs(command) {
  const args = [];
  for (let i = 1; i < command.length; i++) {
    const arg = command[i];
    if (arg === '--') break;
    if (['-c', '--config'].includes(arg)) {
      if (i + 1 >= command.length) throw new Error(`Missing value for ${arg}`);
      args.push(arg, command[++i]);
    } else if (arg.startsWith('--config=') || (arg.startsWith('-c') && arg.length > 2)) args.push(arg);
  }
  return args;
}

export function withCodexPresentation(command, existing) {
  if (existing != null && typeof existing !== 'string') throw new Error('Invalid Codex developer instructions');
  const merged = [existing, '<agent_nvim_code_presentation>\n' + presentationPolicy + '\n</agent_nvim_code_presentation>'].filter(Boolean).join('\n\n');
  const result = [...command], separator = result.indexOf('--');
  result.splice(separator < 0 ? result.length : separator, 0, '-c', 'developer_instructions=' + JSON.stringify(merged));
  return result;
}

// Read resolved configuration without a model turn or persistent config writes.
export function readCodexDeveloperInstructions(executable, command, cwd, timeout = 15000, signal) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) { reject(new Error('Codex configuration read cancelled')); return; }
    const child = spawn(executable, ['app-server', ...codexConfigArgs(command)], {
      cwd, detached: process.platform !== 'win32', stdio: ['pipe', 'pipe', 'ignore'],
    });
    const lines = readline.createInterface({ input: child.stdout });
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true; clearTimeout(timer); signal?.removeEventListener('abort', abort); lines.close();
      child.stdin.on('error', () => {}); child.stdin.end();
      // Stop only this owned, configuration-only server and its launcher children.
      const kill = signal => { if (!child.pid) return; try { process.kill(process.platform === 'win32' ? child.pid : -child.pid, signal); } catch {} };
      kill('SIGTERM');
      const cleanup = setTimeout(() => kill('SIGKILL'), 1000); cleanup.unref();
      error ? reject(error) : resolve(value);
    };
    const abort = () => finish(new Error('Codex configuration read cancelled'));
    const timer = setTimeout(() => finish(new Error('Codex configuration read timed out')), timeout);
    signal?.addEventListener('abort', abort, { once: true });
    child.on('error', () => finish(new Error('Cannot read Codex configuration')));
    child.on('exit', () => { if (!settled) finish(new Error('Codex configuration reader exited early')); });
    child.stdin.on('error', () => { if (!settled) finish(new Error('Codex configuration reader disconnected')); });
    const send = value => child.stdin.write(JSON.stringify(value) + '\n');
    lines.on('line', line => {
      let value; try { value = JSON.parse(line); } catch { return; }
      if (value.error && [1, 2].includes(value.id)) { finish(new Error('Codex configuration read failed')); return; }
      if (value.id === 1 && value.result) {
        send({ method: 'initialized' });
        send({ id: 2, method: 'config/read', params: { cwd, includeLayers: false } });
      }
      if (value.id === 2 && value.result) finish(null, value.result.config?.developer_instructions);
    });
    send({ id: 1, method: 'initialize', params: { clientInfo: { name: 'agent_nvim_config', version: '0.4.0' } } });
  });
}
