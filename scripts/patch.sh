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

# KernelSU-Next (matches the ROM root manager family). The manager signature
# is overridden at build time by KSU_NEXT_MANAGER_HASH / KSU_NEXT_MANAGER_SIZE
# in the workflow so the kernel recognises the user's FinaSU manager.
curl -fsSL --max-time 60 \
  https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/v3.3.0/kernel/setup.sh \
  -o /tmp/ksu-setup.sh
bash /tmp/ksu-setup.sh v3.3.0

echo "[+] patched"
