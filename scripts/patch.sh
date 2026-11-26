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

# KernelSU vanilla v0.9.5. Its default embedded manager hash is
# c371061b19d8c7d7d6133c6a9bafe198fa944e50c1b31c9d8daa8d7f1fc2d2d6,
# which is exactly the certificate of KernelSU_v0.9.5_11872-release.apk.
curl -fsSL --max-time 60 \
  https://raw.githubusercontent.com/tiann/KernelSU/v1.0.0/kernel/setup.sh \
  -o /tmp/ksu-setup.sh
bash /tmp/ksu-setup.sh v1.0.0

echo "[+] patched"
