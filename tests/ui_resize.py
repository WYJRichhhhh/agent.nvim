"""Run resize checks against an actual embedded Neovim UI (requires msgpack)."""
import msgpack, subprocess, sys
process=subprocess.Popen(['nvim','--embed','-u','NONE','-i','NONE'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
unpacker=msgpack.Unpacker(raw=False)
request_id=0
def rpc(method,args):
 global request_id
 request_id+=1;target=request_id
 process.stdin.write(msgpack.packb([0,target,method,args],use_bin_type=True));process.stdin.flush()
 while True:
  for message in unpacker:
   if message[0]==1 and message[1]==target:
    if message[2]:raise RuntimeError(message[2])
    return message[3]
  chunk=process.stdout.read1(65536)
  if not chunk:raise RuntimeError('Neovim exited: '+process.stderr.read().decode())
  unpacker.feed(chunk)
try:
 rpc('nvim_ui_attach',[160,45,{'rgb':True}])
 rpc('nvim_exec_lua',["dofile('tests/resize.lua')",[]])
except RuntimeError:
 code=process.wait()
 if code:print(process.stderr.read().decode());sys.exit(code)
 print("AGENT_UI_RESIZE_OK float / right / bottom / PTY / focus / input / cancellation")
finally:
 if process.poll() is None:process.terminate();process.wait()
