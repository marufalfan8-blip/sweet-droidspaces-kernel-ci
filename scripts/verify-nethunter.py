#!/usr/bin/env python3
"""Fail the build unless Droidspaces + NetHunter options are all present."""
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
    # --- NetHunter / monitor mode ---
    "CONFIG_WIRELESS=y",
    "CONFIG_CFG80211=y",
    "CONFIG_NL80211_TESTMODE=y",
    "CONFIG_MAC80211=y",
    "CONFIG_ATH9K_HTC=m",
    "CONFIG_CARL9170=m",
    "CONFIG_RT2800USB=m",
    "CONFIG_RTL8187=m",
    "CONFIG_RTL8192CU=m",
    "CONFIG_USB_CONFIGFS_F_HID=y",
]
forbidden = [
    "CONFIG_MODULE_SIG_FORCE=y",
    "CONFIG_SHADOW_CALL_STACK=y",
    # ATH9K_HTC=y clashes with the vendor HTC symbol htc_stop.
    "CONFIG_ATH9K_HTC=y",
]

missing = [x for x in required if x not in cfg]
bad = [x for x in forbidden if x in cfg]
if missing or bad:
    print("MISSING:", missing)
    print("FORBIDDEN:", bad)
    sys.exit(1)

ver = re.search(rb"Linux version \d[^\x00\n]{0,180}", data)
print("OK:", ver.group(0).decode("latin1") if ver else "version unknown")

expected_manager = b"79e590113c4c4c0c222978e413a5faa801666957b1212a328e46c00c69821bf7"
if expected_manager not in data:
    sys.exit("FAIL: embedded KernelSU-Next manager signature hash not found")
if b"com.rifsxd.ksunext" not in data:
    sys.exit("FAIL: manager package com.rifsxd.ksunext not embedded")

print("OK: all Droidspaces + NetHunter options present, forbidden options absent")
