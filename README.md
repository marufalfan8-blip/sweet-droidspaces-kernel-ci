# sweet Droidspaces kernel — CI build

Build the kernel **off the phone** with GitHub Actions. The handset only
downloads the resulting `Image.gz`; no compiler runs on the device, so no
heat, no lag, no memory pressure.

## Source

- `manipvlator/los_kernel_xiaomi_sm6150` @ `stable` (4.14.357)
- `EXTRAVERSION` set to `-reforge`
- Droidspaces kernel options applied (PID/IPC/USER namespaces, cgroups,
  overlayfs, veth, netfilter, …)
- KernelSU v0.9.5 integrated (the defconfig references `CONFIG_KSU`)
- `MODULE_SIG_FORCE` and `SHADOW_CALL_STACK` stay disabled
- one Kconfig recursive-dependency fix

## Trigger

GitHub → Actions → **Build sweet Droidspaces kernel (off-device)** →
Run workflow. Takes roughly 15–30 minutes on a 2-vCPU runner with a 4 GB
swapfile and `-j2`.

## Output

Artifact `sweet-droidspaces-kernel` contains:

- `Image.gz` — the kernel
- `kernel-config.txt` — verified config (guaranteed to contain the required
  options and none of the forbidden ones)

The workflow fails automatically if `PID_NS`, `IPC_NS`, `KSU` or the version
string are missing, or if `MODULE_SIG_FORCE` / `SHADOW_CALL_STACK` appear.

## Repacking (done on the phone, only a few seconds)

Use `magiskboot repack` with the **original boot image** as the base, putting
the CI `Image.gz` in the working directory together with the original
`ramdisk.cpio` and `dtb`. That keeps the original ramdisk, DTB, cmdline and
header. Flashing remains the user's decision and action.
