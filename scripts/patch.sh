#!/usr/bin/env bash
# Apply local patches to the kernel source. Runs on the CI runner, never on the phone.
set -euo pipefail

KERNEL_DIR="$(cd "${1:-kernel}" && pwd)"
CI_DIR="$(cd "${2:-ci}" && pwd)"
cd "$KERNEL_DIR"

# Droidspaces requirements + FinaSU built-in requirements (KALLSYMS_ALL, kprobes).
cat "$CI_DIR/patches/defconfig.add" >> arch/arm64/configs/vendor/sweet_defconfig

# FinaSU v1.7.0 built-in driver (non-GKI 4.14). setup.sh clones the tagged source,
# symlinks kernel/ to drivers/kernelsu, and wires Kconfig/Makefile.
curl -fsSL --max-time 60 \
  https://raw.githubusercontent.com/LyraVoid/FinaSU/v1.7.0/kernel/setup.sh \
  -o /tmp/finasu-setup.sh
FINASU_REF=v1.7.0 bash /tmp/finasu-setup.sh

# 4.14 compatibility shims. Each patch is skipped when the file is absent.
python3 - "$KERNEL_DIR" <<'PY'
import os, sys
root = sys.argv[1] + "/drivers/kernelsu"

def patch(rel, fn):
    p = os.path.join(root, rel)
    if not os.path.exists(p):
        print("[-] skip", rel, "(not present)")
        return
    s = open(p).read()
    n = fn(s)
    if n != s:
        open(p, "w").write(n)
        print("[+] patched", rel)

# aarch64 syscall_fn_t typedef
def syscall_fn(s):
    old = "#if defined(__x86_64__)\ntypedef sys_call_ptr_t syscall_fn_t;\n#endif\n"
    new = "#if defined(__x86_64__)\ntypedef sys_call_ptr_t syscall_fn_t;\n#elif defined(__aarch64__)\ntypedef long (*syscall_fn_t)(const struct pt_regs *regs);\n#endif\n"
    return s.replace(old, new, 1) if old in s and "typedef long (*syscall_fn_t)" not in s else s
patch("hook/syscall_hook.h", syscall_fn)
patch("hook/arm64/syscall_hook.h", syscall_fn)

def sulog(s):
    if "#include <linux/init.h>" not in s:
        return s.replace("#include <linux/types.h>\n", "#include <linux/types.h>\n#include <linux/init.h>\n", 1)
    return s
patch("feature/sulog.h", sulog)
patch("sulog/event.c", sulog)

patch("feature/sucompat.c", lambda s: s.replace("#include <linux/pgtable.h>", "#include <asm/pgtable.h>", 1))

def sucompat(s):
    s = s.replace("ksys_close(", "sys_close(")
    if "#include <linux/syscalls.h>" not in s:
        s = s.replace("#include <linux/types.h>\n", "#include <linux/types.h>\n#include <linux/syscalls.h>\n", 1)
    return s
patch("feature/sucompat.c", sucompat)

patch("include/util.h", lambda s: s.replace("#define ksu_close_fd ksys_close", "#define ksu_close_fd sys_close", 1))

def patchmem(s):
    s = s.replace("__pte_to_phys(*pte)", "(pte_pfn(*pte) << PAGE_SHIFT)")
    s = s.replace("ret = (int)copy_to_kernel_nofault(map, src, len);", "memcpy(map, src, len); ret = 0;")
    s = s.replace("__flush_icache_range", "flush_icache_range")
    return s
patch("hook/arm64/patch_memory.c", patchmem)

# 4.14 has fsnotify_add_mark(), not fsnotify_add_inode_mark().
patch("manager/pkg_observer.c", lambda s: s.replace("fsnotify_add_inode_mark(m, inode, 0)", "fsnotify_add_mark(m, inode, NULL, 0)"))

# 4.14 ktime_get_boottime_ts64() takes an output pointer.
def boottime(s):
    s = s.replace("ktime_get_boottime_seconds()", "ksu_boottime_seconds()")
    helper = (
        "static inline uint64_t ksu_boottime_seconds(void)\n"
        "{\n"
        "    struct timespec64 ts;\n"
        "    ktime_get_boottime_ts64(&ts);\n"
        "    return (uint64_t)ts.tv_sec;\n"
        "}\n\n"
    )
    anchor = "void ksu_compat_sulog(uint8_t sym)"
    if helper not in s and anchor in s:
        s = s.replace(anchor, helper + anchor, 1)
    return s
patch("sulog/event.c", boottime)
PY

echo "[+] patched"
