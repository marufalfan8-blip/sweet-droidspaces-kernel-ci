#!/usr/bin/env bash
# Apply local patches to the kernel source. Runs on the CI runner, never on the phone.
set -euo pipefail

KERNEL_DIR="$(cd "${1:-kernel}" && pwd)"
CI_DIR="$(cd "${2:-ci}" && pwd)"
cd "$KERNEL_DIR"

# Match the ROM kernel version string.
sed -i 's/^EXTRAVERSION = -openela$/EXTRAVERSION = -reforge/' Makefile
grep -q '^EXTRAVERSION = -reforge$' Makefile

# Kconfig recursive-dependency fix (-choice <-> CPU_FREQ_GOV_SCHEDUTIL).
sed -i 's/^\tdepends on SMP && CPU_FREQ_GOV_SCHEDUTIL$/\tdepends on SMP/' drivers/cpufreq/Kconfig

# Droidspaces requirements + LTO off (KPROBES needed by KSU-Next).
cat "$CI_DIR/patches/defconfig.add" >> arch/arm64/configs/vendor/sweet_defconfig

# KernelSU-Next v3.3.0 (same family as the user's FinaSU 33224 manager).
# Manager signature/size/package are overridden in the workflow make command.
curl -fsSL --max-time 60 \
  https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/v3.3.0/kernel/setup.sh \
  -o /tmp/ksu-setup.sh
bash /tmp/ksu-setup.sh v3.3.0

python3 - "$KERNEL_DIR" <<'PY'
import os, sys
root = sys.argv[1] + "/drivers/kernelsu"

def patch(rel, fn):
    p = os.path.join(root, rel)
    s = open(p).read()
    n = fn(s)
    if n != s:
        open(p, "w").write(n)
        print("[+] patched", rel)

# 4.14 has no syscall_fn_t typedef on arm64.
def syscall_fn(s):
    old = "#if defined(__x86_64__)\ntypedef sys_call_ptr_t syscall_fn_t;\n#endif\n"
    new = "#if defined(__x86_64__)\ntypedef sys_call_ptr_t syscall_fn_t;\n#elif defined(__aarch64__)\ntypedef long (*syscall_fn_t)(const struct pt_regs *regs);\n#endif\n"
    return s.replace(old, new, 1) if old in s and "typedef long (*syscall_fn_t)" not in s else s
patch("hook/syscall_hook.h", syscall_fn)

# __init/__exit need linux/init.h on this tree.
def sulog(s):
    if "#include <linux/init.h>" not in s:
        return s.replace("#include <linux/types.h>\n", "#include <linux/types.h>\n#include <linux/init.h>\n", 1)
    return s
patch("feature/sulog.h", sulog)

# 4.14 has no linux/pgtable.h.
patch("feature/sucompat.c", lambda s: s.replace("#include <linux/pgtable.h>", "#include <asm/pgtable.h>", 1))

# 4.14 exports sys_close(), not ksys_close().
def sucompat(s):
    s = s.replace("ksys_close(", "sys_close(")
    if "#include <linux/syscalls.h>" not in s:
        s = s.replace("#include <linux/types.h>\n", "#include <linux/types.h>\n#include <linux/syscalls.h>\n", 1)
    return s
patch("feature/sucompat.c", sucompat)

def util(s):
    return s.replace("#define ksu_close_fd ksys_close", "#define ksu_close_fd sys_close", 1)
patch("include/util.h", util)

# arm64 text-patch helpers from newer kernels -> 4.14 equivalents.
def patchmem(s):
    s = s.replace("__pte_to_phys(*pte)", "(pte_pfn(*pte) << PAGE_SHIFT)")
    s = s.replace("ret = (int)copy_to_kernel_nofault(map, src, len);", "memcpy(map, src, len); ret = 0;")
    s = s.replace("__flush_icache_range", "flush_icache_range")
    return s
patch("hook/arm64/patch_memory.c", patchmem)
PY

echo "[+] patched"
