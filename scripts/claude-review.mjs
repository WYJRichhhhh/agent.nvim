import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { GitReview } from './git-review.mjs';

const equal = (a, b) => a === b || (Buffer.isBuffer(a) && Buffer.isBuffer(b) && a.equals(b));
const hash = value => value === null ? 'absent' : crypto.createHash('sha256').update(value).digest('hex');
const fileTools = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);

export class ClaudeReview {
  constructor(cwd, options, emit) {
    this.cwd = cwd;
    this.options = options;
    this.emit = emit;
    this.git = new GitReview(cwd, options, emit);
    this.files = new Map();
    this.bytes = 0;
    this.sequence = 0;
    this.closed = false;
    this.notices = new Set();
  }
  warn(key, message) {
    if (!this.notices.has(key)) {
      this.notices.add(key);
      this.emit({ type: 'warning', message });
    }
  }
  async begin() {
    this.turnId = `claude-${++this.sequence}`;
    this.files.clear();
    this.bytes = 0;
    if (this.options.git_fallback) await this.git.begin(this.turnId);
    else await this.git.discover();
    this.emit({ type: 'event', method: 'turn/started', params: { turnId: this.turnId } });
  }
  async fileFor(input) {
    const value = input?.file_path ?? input?.notebook_path;
    if (typeof value !== 'string' || !path.isAbsolute(value) || /[\0\r\n]/.test(value)) return;
    let resolved;
    let parent = path.dirname(value);
    const suffix = [path.basename(value)];
    while (true) {
      try { resolved = path.join(await fs.realpath(parent), ...suffix); break; }
      catch (error) {
        if (error.code !== 'ENOENT' || parent === path.dirname(parent)) return;
        suffix.unshift(path.basename(parent));
        parent = path.dirname(parent);
      }
    }
    const allowed = () => !this.options.restrict_to_cwd || [this.cwd, ...(this.options.worktrees ? this.git.roots.filter(root => !this.cwd.startsWith(root + path.sep)) : [])]
      .some(root => resolved.startsWith(root + path.sep));
    if (!allowed()) await this.git.discover();
    if (!allowed()) return;
    return resolved;
  }
  async read(file) {
    try {
      const stat = await fs.lstat(file);
      if (!stat.isFile() || stat.size > this.options.max_diff_bytes) return undefined;
      const value = await fs.readFile(file);
      return value.includes(0) ? undefined : value;
    } catch (error) { return error.code === 'ENOENT' ? null : undefined; }
  }
  async before(event) {
    if (!fileTools.has(event.tool_name)) return;
    const file = await this.fileFor(event.tool_input);
    if (!file || this.files.has(file)) return;
    const value = await this.read(file);
    if (value === undefined) return;
    const cost = value?.length ?? 0;
    if (this.bytes + this.git.bytes + cost > this.options.max_snapshot_bytes) {
      this.warn('budget', 'Claude review snapshot limit reached; some file edits are omitted.');
      return;
    }
    this.files.set(file, { before: value, last: hash(value), reported: false });
    this.bytes += cost;
  }
  async after(event) {
    if (!fileTools.has(event.tool_name)) return;
    const file = await this.fileFor(event.tool_input);
    const baseline = this.files.get(file);
    if (!baseline) return; // Never invent a before-image after a write has happened.
    const after = await this.read(file);
    if (after === undefined || baseline.last === hash(after)) return;
    baseline.last = hash(after);
    const reverted = equal(baseline.before, after);
    if (reverted && !baseline.reported) return;
    const diff = reverted ? '' : await this.git.patch(this.cwd, path.relative(this.cwd, file), baseline.before, after);
    if (diff === null || diff.length > this.options.max_diff_bytes) return;
    baseline.reported = !reverted;
    this.emit({ type: 'event', method: 'item/completed', params: {
      turnId: this.turnId,
      item: { id: `claude-${crypto.randomUUID()}`, type: 'fileChange', status: 'completed', source: 'claude',
        changes: [{ path: file, kind: { type: baseline.before === null ? 'add' : after === null ? 'delete' : 'update' }, diff, reverted }] },
    } });
  }
  async handle(event) {
    if (this.closed || !event || typeof event.session_id !== 'string' || !event.session_id) return;
    if (!this.sessionId) this.sessionId = event.session_id;
    if (event.session_id !== this.sessionId) {
      if (event.hook_event_name !== 'SessionStart' || event.agent_id || !['clear', 'resume'].includes(event.source)) return;
      if (this.turnId && this.options.git_fallback) await this.git.scan(this.turnId);
      this.sessionId = event.session_id;
      this.turnId = undefined;
      this.files.clear();
      this.bytes = 0;
    }
    const type = event.hook_event_name;
    this.emit({ type: 'thread', threadId: this.sessionId, state: type === 'SessionEnd' ? 'ended' : 'connected' });
    // Subagent tool writes count toward the parent task, but cannot reset its turn.
    if (type === 'SessionStart' || (event.agent_id && ['UserPromptSubmit', 'Stop', 'SessionEnd'].includes(type))) return;
    if (type === 'UserPromptSubmit') {
      if (this.turnId && this.options.git_fallback) await this.git.scan(this.turnId);
      await this.begin();
      return;
    }
    if (!this.turnId && type === 'PreToolUse') await this.begin();
    if (!this.turnId) return;
    if (type === 'PreToolUse') await this.before(event);
    if (type === 'PostToolUse' || type === 'PostToolUseFailure') {
      await this.after(event);
      if (this.options.git_fallback) await this.git.scan(this.turnId);
    }
    if (type === 'Stop' || type === 'SessionEnd') {
      if (this.options.git_fallback) await this.git.scan(this.turnId);
      this.emit({ type: 'event', method: 'turn/completed', params: { turnId: this.turnId } });
    }
  }
  close() {
    this.closed = true;
    this.git.close();
    this.files.clear();
  }
}

// Only this CLI launch gets the extra hooks. User/project settings are not edited.
export async function augmentCommand(command, hooks, cwd) {
  const result = [], supplied = [];
  for (let i = 0; i < command.length; i++) {
    const arg = command[i];
    if (arg === "--") { result.push(...command.slice(i)); break; }
    if (['--bare', '--safe-mode'].includes(arg)) throw new Error(`${arg} disables hooks; use claude.enabled=false for terminal-only mode`);
    if (arg === '--settings') {
      if (!command[i + 1]) throw new Error('--settings is missing a value');
      supplied.push(command[++i]);
    } else if (arg.startsWith('--settings=')) supplied.push(arg.slice(11));
    else result.push(arg);
  }
  if (supplied.length > 1) throw new Error('Use a single --settings argument with Claude review');
  let settings = {};
  if (supplied.length) {
    const value = supplied[0];
    let json = value;
    if (!value.trim().startsWith('{')) {
      const file = path.resolve(cwd, value);
      const stat = await fs.stat(file);
      if (!stat.isFile() || stat.size > 2 * 1024 * 1024) throw new Error('--settings must be a regular JSON file no larger than 2 MiB');
      json = await fs.readFile(file, 'utf8');
    }
    settings = JSON.parse(json);
    if (!settings || typeof settings !== 'object' || Array.isArray(settings)) throw new Error('--settings must contain a JSON object');
  }
  if (settings.disableAllHooks) throw new Error('disableAllHooks prevents Claude review; use claude.enabled=false for terminal-only mode');
  settings.hooks ??= {};
  if (typeof settings.hooks !== "object" || Array.isArray(settings.hooks)) throw new Error("hooks must be an object in --settings");
  for (const [event, entries] of Object.entries(hooks)) {
    const existing = settings.hooks[event] ?? [];
    if (!Array.isArray(existing)) throw new Error(`Invalid hooks.${event} in --settings`);
    settings.hooks[event] = [...existing, ...entries];
  }
  const separator = result.indexOf('--');
  result.splice(separator === -1 ? result.length : separator, 0, '--settings', JSON.stringify(settings));
  return result;
}
