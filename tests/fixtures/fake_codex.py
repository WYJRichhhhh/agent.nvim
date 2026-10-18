#!/usr/bin/env python3
"""A local protocol fixture, never calls a model or reads login credentials."""
import json, os, sys, urllib.request, subprocess
from pathlib import Path
if len(sys.argv)>1 and sys.argv[1]=='app-server':
    sys.exit(subprocess.call([os.environ.get('AGENT_TEST_NODE','node'),str(Path(__file__).with_name('fake_app_server.mjs')),*sys.argv[2:]]))
endpoint=sys.argv[sys.argv.index('--remote')+1].replace('ws:','http:')
def request(action):
    req=urllib.request.Request(endpoint+'/'+action,headers={'Authorization':'Bearer '+os.environ['AGENT_NVIM_SERVER_TOKEN']})
    return urllib.request.urlopen(req).read().decode()
print('READY_NATIVE_TUI',flush=True)
for line in sys.stdin:
    cmd=line.strip()
    if cmd=='quit':break
    if cmd in ['edit','approve','stats']:print(request(cmd),flush=True)
