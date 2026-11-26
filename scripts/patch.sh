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

# Droidspaces requirements + LTO off.
cat "$CI_DIR/patches/defconfig.add" >> arch/arm64/configs/vendor/sweet_defconfig

# KernelSU vanilla v0.9.5 — already proven to compile and boot on this 4.14 tree.
# Manager hash/size/package/version are overridden in the workflow make command
# so the kernel accepts the user's FinaSU manager (me.yuki.fina, 33224).
curl -fsSL --max-time 60 \
  https://raw.githubusercontent.com/tiann/KernelSU/v0.9.5/kernel/setup.sh \
  -o /tmp/ksu-setup.sh
bash /tmp/ksu-setup.sh v0.9.5

echo "[+] patched"
