#!/usr/bin/env bash
# Apply local patches to the kernel source. Runs on the CI runner, never on the phone.
set -euo pipefail

KERNEL_DIR="$(cd "${1:-kernel}" && pwd)"
CI_DIR="$(cd "${2:-ci}" && pwd)"
cd "$KERNEL_DIR"

# Droidspaces requirements + LTO off (KPROBES needed by KSU-Next/KSUN).
cat "$CI_DIR/patches/defconfig.add" >> arch/arm64/configs/vendor/sweet_defconfig

# KernelSU-Next/KSUN fork (SUSFS + BRANCH_LINK family, same as the ROM kernel).
# Manager constants/version are overridden in the workflow make command.
curl -fsSL --max-time 60 \
  https://raw.githubusercontent.com/MirahSyakilla/KSUN/main/kernel/setup.sh \
  -o /tmp/ksu-setup.sh
bash /tmp/ksu-setup.sh

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

def syscall_fn(s):
    old = "#if defined(__x86_64__)\ntypedef sys_call_ptr_t syscall_fn_t;\n#endif\n"
    new = "#if defined(__x86_64__)\ntypedef sys_call_ptr_t syscall_fn_t;\n#elif defined(__aarch64__)\ntypedef long (*syscall_fn_t)(const struct pt_regs *regs);\n#endif\n"
    return s.replace(old, new, 1) if old in s and "typedef long (*syscall_fn_t)" not in s else s
patch("hook/syscall_hook.h", syscall_fn)

def sulog(s):
    if "#include <linux/init.h>" not in s:
        return s.replace("#include <linux/types.h>\n", "#include <linux/types.h>\n#include <linux/init.h>\n", 1)
    return s
patch("feature/sulog.h", sulog)

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

# KSUN uses a newer pr_info_ratelimited macro; 4.14 expands it to __ratelimit.
patch("extras.c", lambda s: s.replace("pr_info_ratelimited(", "pr_info("))

# 4.14 has fsnotify_add_mark(), not fsnotify_add_inode_mark().
patch("manager/pkg_observer.c", lambda s: s.replace("fsnotify_add_inode_mark(m, inode, 0)", "fsnotify_add_mark(m, inode, NULL, 0)"))
PY

echo "[+] patched"
