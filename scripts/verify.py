#!/usr/bin/env python3
"""Fail the build unless the resulting kernel has what Droidspaces needs
and none of the options that made earlier kernels bootloop."""
import gzip
import re
import sys

path = sys.argv[1]
raw = open(path, "rb").read()
try:
    data = gzip.decompress(raw)
except OSError:
    data = raw

i = data.find(b"IKCFG_ST")
if i < 0:
    sys.exit("FAIL: no embedded IKCFG config in kernel")

import zlib
cfg = zlib.decompress(data[i + 8:], 16 + zlib.MAX_WBITS).decode("utf-8", "ignore")
open("kernel-config.txt", "w").write(cfg)

required = [
    "CONFIG_NAMESPACES=y",
    "CONFIG_PID_NS=y",
    "CONFIG_IPC_NS=y",
    "CONFIG_USER_NS=y",
    "CONFIG_UTS_NS=y",
    "CONFIG_NET_NS=y",
    "CONFIG_SYSVIPC=y",
    "CONFIG_POSIX_MQUEUE=y",
    "CONFIG_CGROUP_PIDS=y",
    "CONFIG_DEVTMPFS=y",
    "CONFIG_OVERLAY_FS=y",
    "CONFIG_SECCOMP=y",
    "CONFIG_KSU=y",
    'CONFIG_LOCALVERSION="-reforge"',
]
forbidden = [
    "CONFIG_MODULE_SIG_FORCE=y",
    "CONFIG_SHADOW_CALL_STACK=y",
]

missing = [x for x in required if x not in cfg]
bad = [x for x in forbidden if x in cfg]
if missing or bad:
    print("MISSING:", missing)
    print("FORBIDDEN:", bad)
    sys.exit(1)

ver = re.search(rb"Linux version \d[^\x00\n]{0,180}", data)
print("OK:", ver.group(0).decode("latin1") if ver else "version unknown")

expected_manager = b"c371061b19d8c7d7d6133c6a9bafe198fa944e50c1b31c9d8daa8d7f1fc2d2d6"
if expected_manager not in data:
    sys.exit("FAIL: embedded KernelSU manager signature hash not found")

if b"32680" not in data:
    sys.exit("FAIL: KSU_VERSION=32680 not embedded (newer managers refuse older kernels)")

print("OK: all required options present, forbidden options absent")
print("OK: embedded manager signature matches KernelSU v0.9.5 manager")
