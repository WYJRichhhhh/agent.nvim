import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { ClaudeReview, augmentCommand } from '../scripts/claude-review.mjs';
const exec = promisify(execFile);
const options = { git_fallback: true, worktrees: true, restrict_to_cwd: true, max_diff_bytes: 1024 * 1024, max_snapshot_bytes: 8 * 1024 * 1024 };
const git = (cwd, ...args) => exec('git', ['-C', cwd, ...args]);
const event = (hook_event_name, extra = {}) => ({ session_id: 'parent', hook_event_name, ...extra });

test('CLI settings merge preserves user hooks/options; disabled hooks and ambiguous flags are rejected', async () => {
  const hooks = { Stop: [{ hooks: [{ command: 'our-hook' }] }] };
  const command = await augmentCommand(['claude', '--settings', JSON.stringify({ model: 'original', hooks: { Stop: [{ hooks: [{ command: 'user-hook' }] }] } }), '--', 'prompt'], hooks, '/tmp');
  const index = command.indexOf('--settings');
  const settings = JSON.parse(command[index + 1]);
  assert.equal(settings.model, 'original'); assert.equal(settings.hooks.Stop.length, 2);
  assert.ok(index < command.indexOf('--'));
  await assert.rejects(augmentCommand(['claude', '--bare'], hooks, '/tmp'));
  await assert.rejects(augmentCommand(['claude', '--settings={"disableAllHooks":true}'], hooks, '/tmp'));
});

test('Git shell writes exclude pre-existing dirt, discover worktrees, and do not reset for subagent prompts', async () => {
  const dir = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'claude-review-')));
  const work = dir + '-work';
  const events = [];
  const review = new ClaudeReview(dir, options, e => events.push(e));
  try {
    await git(dir, 'init', '-q'); await git(dir, 'config', 'user.email', 'test@example.invalid'); await git(dir, 'config', 'user.name', 'Test');
    await fs.writeFile(path.join(dir, 'file.txt'), 'original\n');
    await git(dir, 'add', '.'); await git(dir, 'commit', '-qm', 'base');
    await fs.writeFile(path.join(dir, 'file.txt'), 'dirty before\n');
    await review.handle(event('SessionStart')); await review.handle(event('UserPromptSubmit'));
    const turn = review.turnId;
    await review.handle(event('UserPromptSubmit', { agent_id: 'child' }));
    assert.equal(review.turnId, turn);
    await fs.writeFile(path.join(dir, 'file.txt'), 'script after\n');
    await review.handle(event('PostToolUse', { tool_name: 'Bash' }));
    const change = events.flatMap(e => e.params?.item?.changes ?? []).find(c => c.path.endsWith('/file.txt'));
    assert.ok(change.diff.includes('-dirty before') && change.diff.includes('+script after'));
    await git(dir, 'worktree', 'add', '-qb', 'child', work);
    await fs.writeFile(path.join(work, 'file.txt'), 'worktree edit\n');
    await review.handle(event('PostToolUse', { tool_name: 'Bash', agent_id: 'child' }));
    const count = events.filter(e => e.params?.item).length;
    assert.ok(events.some(e => e.params?.item?.changes.some(c => c.path === path.join(work, 'file.txt'))));
    await review.handle(event('PostToolUse', { tool_name: 'Read' }));
    assert.equal(events.filter(e => e.params?.item).length, count);
    await review.handle(event('UserPromptSubmit', { session_id: 'unrelated-session' }));
    assert.equal(review.turnId, turn);
    await review.handle(event('SessionStart', { session_id: 'cleared-session', source: 'clear' }));
    assert.equal(review.sessionId, 'cleared-session');
    assert.equal(review.turnId, undefined);
    await review.handle(event('UserPromptSubmit', { session_id: 'cleared-session' }));
    assert.notEqual(review.turnId, turn);
  } finally { review.close(); await fs.rm(dir, { recursive: true, force: true }); await fs.rm(work, { recursive: true, force: true }); }
});

test('Non-Git native snapshots reject external/symlink paths and enforce budget', async () => {
  const dir = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'claude-path-')));
  const outside = dir + '-outside.txt';
  const emitted = [];
  const review = new ClaudeReview(dir, { ...options, max_snapshot_bytes: 2 }, e => emitted.push(e));
  try {
    await fs.writeFile(outside, 'external');
    await fs.symlink(outside, path.join(dir, 'link.txt'));
    await fs.writeFile(path.join(dir, 'large.txt'), 'too big');
    await review.handle(event('UserPromptSubmit'));
    for (const file of [outside, path.join(dir, 'link.txt'), path.join(dir, 'large.txt')]) {
      const tool = { tool_name: 'Write', tool_input: { file_path: file } };
      await review.handle(event('PreToolUse', tool));
      await review.handle(event('PostToolUse', tool));
    }
    assert.equal(review.files.size, 0);
    assert.equal(emitted.filter(e => e.params?.item).length, 0);
    assert.ok(emitted.some(e => e.type === 'warning'));
  } finally { review.close(); await fs.rm(dir, { recursive: true, force: true }); await fs.rm(outside, { force: true }); }
});


test('Write into a previously absent nested directory is captured outside Git', async () => {
  const dir = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'claude-create-')));
  const events = [];
  const review = new ClaudeReview(dir, options, e => events.push(e));
  try {
    const file = path.join(dir, 'new', 'nested', 'file.txt');
    const tool = { tool_name: 'Write', tool_input: { file_path: file } };
    await review.handle(event('UserPromptSubmit'));
    await review.handle(event('PreToolUse', tool));
    await fs.mkdir(path.dirname(file), { recursive: true });
    await fs.writeFile(file, 'created\n');
    await review.handle(event('PostToolUse', tool));
    const change = events.find(e => e.params?.item)?.params.item.changes[0];
    assert.equal(change?.kind.type, 'add');
    assert.ok(change.diff.includes('+created'));
  } finally { review.close(); await fs.rm(dir, { recursive: true, force: true }); }
});
