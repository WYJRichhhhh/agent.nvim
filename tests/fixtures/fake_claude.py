#!/usr/bin/env python3
"""Interactive fixture executing the actual injected command hooks; no model/auth calls."""
import json, os, sys, subprocess
from pathlib import Path
settings = json.loads(sys.argv[sys.argv.index('--settings') + 1])
assert settings.get('env', {}).get('AGENT_KEEP_SETTING') == 'kept'
assert os.environ.get('AGENT_TEST_INHERITED') == 'unchanged'
sequence = 0

def hook(event, tool=None, target=None):
    global sequence
    sequence += 1
    payload = {'session_id': 'fixture-claude', 'hook_event_name': event, 'cwd': os.getcwd(),
               'tool_name': tool, 'tool_use_id': str(sequence), 'tool_input': {'file_path': str(target) if target else None}}
    for group in settings.get('hooks', {}).get(event, []):
        for entry in group['hooks']:
            result = subprocess.run(entry['command'], shell=True, input=json.dumps(payload), text=True, capture_output=True, timeout=20)
            assert result.returncode == 0, result.stderr
            assert result.stdout == '', result.stdout

def edit(value):
    file = Path.cwd() / 'sample.txt'
    hook('PreToolUse', 'Write', file)
    file.write_text(value + '\n')
    hook('PostToolUse', 'Write', file)

hook('SessionStart')
print('READY_CLAUDE_TUI', flush=True)
for line in sys.stdin:
    cmd = line.strip()
    if cmd == 'begin': hook('UserPromptSubmit')
    elif cmd == 'edit': edit('after')
    elif cmd == 'edit-again': edit('after twice')
    elif cmd == 'revert': edit('before')
    elif cmd == 'script':
        hook('PreToolUse', 'Bash')
        Path('shell.txt').write_text('script result\n')
        hook('PostToolUse', 'Bash')
    elif cmd == 'failed':
        hook('PreToolUse', 'Write', Path.cwd() / 'not-written.txt')
        hook('PostToolUseFailure', 'Write', Path.cwd() / 'not-written.txt')
    elif cmd == 'quit':
        hook('Stop'); hook('SessionEnd'); break
    print('DONE:' + cmd, flush=True)
