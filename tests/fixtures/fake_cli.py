"""用于终端生命周期测试，不访问模型、网络或认证文件。"""
import os
import sys

print(f"READY pid={os.getpid()} cwd={os.getcwd()} env={os.getenv('AGENT_TEST_VALUE', '')}", flush=True)
print("ARGS:" + " ".join(sys.argv[1:]), flush=True)
for line in sys.stdin:
    value = line.strip()
    if value == "SIZE":
        dimensions = os.get_terminal_size(sys.stdin.fileno())
        print(f"SIZE:{dimensions.columns}x{dimensions.lines}", flush=True)
        continue
    if value == "EXIT":
        sys.exit(7)
    print(f"REPLY:{value}", flush=True)
