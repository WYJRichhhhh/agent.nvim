"""Exercise the real stdio MCP transport from a simulated native CLI."""
import json, os, subprocess
from pathlib import Path

def show_code():
    node = os.environ.get('AGENT_TEST_NODE', 'node')
    script = Path(__file__).resolve().parents[2] / 'scripts' / 'editor-mcp.mjs'
    child = subprocess.Popen([node, str(script)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    sequence = 0
    def request(method, params=None):
        nonlocal sequence
        sequence += 1
        child.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': sequence, 'method': method, 'params': params or {}}) + '\n')
        child.stdin.flush()
        return json.loads(child.stdout.readline())
    try:
        assert 'result' in request('initialize', {'protocolVersion': '2024-11-05'})
        assert len(request('tools/list')['result']['tools']) == 2
        result = request('tools/call', {'name': 'show_code', 'arguments': {'locations': [{'file': 'sample.txt', 'ranges': [{'start': 1, 'label': 'Core implementation'}]}]}})
        assert not result.get('error'), result
        return json.loads(result['result']['content'][0]['text'])
    finally:
        child.terminate(); child.wait(timeout=5)
