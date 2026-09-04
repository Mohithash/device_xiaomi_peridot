# How this device tree and the Theettam kernel fit together

Written 2026-09-03 from the running device (POCO F6 peridot, `bestrom_peridot-user`,
Android 17 `CP2A.260605.016`) with the Theettam SukiSU-Ultra + SUSFS build of
`theettam-2.7-lts176` flashed over it. Every claim below was checked against
this tree, the kernel tree, or the phone. Read it before changing anything in
the `# Kernel` block of `BoardConfig.mk`.

## There are two kernels in play, and that is deliberate

This device tree **builds its own kernel from source**:

    BoardConfig.mk   TARGET_KERNEL_SOURCE  := kernel/xiaomi/sm8635
                     TARGET_KERNEL_CONFIG  := gki_defconfig
                                              vendor/pineapple_GKI.config
                                              vendor/peridot_GKI.config
                     TARGET_KERNEL_CLANG_VERSION := r563880c

That build is what produces `boot.img` **and every module** in `vendor_dlkm`,
`vendor_boot` and `system_dlkm`. On the current ROM those modules carry:

    vermagic=6.1.175-android14-11-ga3b9c44908dd-ab13320413 SMP preempt mod_unload modversions aarch64

The Theettam kernel is then flashed **over the Image only**, by AnyKernel3 with
`do.modules=0`, and the phone ends up running `6.1.176-...` against modules
built for `6.1.175-...`.

That is not an accident and it is not fragile-by-luck. `CONFIG_MODVERSIONS=y`
is set, so every module carries symbol CRCs, and `kernel/module/version.c`
says:

    /* First part is kernel version, which we ignore if module has crcs. */
    int same_magic(const char *amagic, const char *bmagic, bool has_crcs)
    {
            if (has_crcs) {
                    amagic += strcspn(amagic, " ");
                    bmagic += strcspn(bmagic, " ");
            }
            return strcmp(amagic, bmagic) == 0;
    }

The version prefix is skipped and the rest (`SMP preempt mod_unload
modversions aarch64`) matches, so the load succeeds **if and only if** the
exported-symbol CRCs still match. On this device all 444 modules load and
`dmesg` has zero `disagrees about version` lines.

**So the contract is: the CRCs, not the version string.** The kernel side
enforces it with a gate that fails the build on any CRC drift
(`scripts/ci/symvers-diff.sh` against `scripts/ci/kmi-baseline/<flavor>.symvers`;
see `docs/BOOT-NOTES.md` Rules 1, 2 and 7 in the kernel tree). The device-tree
side upholds it by continuing to build its modules from a same-KMI base.

## Things not to do

**Do not point `TARGET_KERNEL_SOURCE` at the Theettam tree.** It looks like
the tidy thing to do and it breaks four ways at once:

1. it would merge `pineapple_GKI.config` and `peridot_GKI.config` on top of
   `gki_defconfig`, so the Image would no longer be the configuration the KMI
   baselines were recorded from;
2. it would build with `r563880c` instead of the pinned Neutron toolchain the
   releases are built and boot-tested with;
3. it would skip the KernelSU/SUSFS integration steps entirely, so the result
   would have no root engine;
4. it would rebuild the vendor modules from that tree, which is exactly what
   the Image-only contract exists to avoid.

**Do not "fix" the version mismatch.** 6.1.176 modules against a 6.1.176 Image
would be tidier and would also mean rebuilding every vendor module, which is
the one thing the arrangement is designed not to require.

**Do not bump the kernel branch and the ROM independently.** `534bcf0` records
what that costs: a lineage-23.2 kernel at 6.1.170 against current
kernel-modules left the bootloader refusing the slot outright.

## Where the kernel command line actually comes from

Only three parameters are this tree's (`BoardConfig.mk` `BOARD_KERNEL_CMDLINE`):
`sysctl.kernel.firmware_config.force_sysfs_fallback`, `swinfo.fingerprint` and
`mtdoops.fingerprint`. Everything else in `/proc/cmdline` comes from the
kernel's own `CONFIG_CMDLINE` (extended, not overridden) and from the Xiaomi
DTB `chosen` node — including `block2mtd.block2mtd=/dev/block/by-name/oops`,
`kasan=off`, `rcu_nocbs=0-7` and `cpufreq.default_governor=performance`.

Two consequences worth knowing:

- `cpufreq.default_governor=performance` is overridden at init: all three
  policies run the vendor `walt` governor on the live device.
- Adding kernel parameters here to enable kernel features is almost always
  wrong. ADIOS is already the default via `CONFIG_MQ_IOSCHED_DEFAULT_ADIOS`,
  BORE has no command-line knob, and the Boeffla wakelock blocker and DAMON
  are sysfs-gated.

## What the kernel gives this device tree to tune

Verified live on the rooted build:

| Thing | Value on device | Owner |
|---|---|---|
| I/O scheduler | `adios` 3.2.0 on every UFS LU | kernel default (`CONFIG_MQ_IOSCHED_DEFAULT_ADIOS`) |
| Tick rate | `CONFIG_HZ=300`, `NO_HZ_IDLE` | kernel |
| CPU idle governor | `qcom-cpu-lpm` | vendor module, beats the Image's `menu`/`teo` |
| CPU freq governor | `walt` on policy0/3/7 | vendor module |
| Scheduler | BORE, `sched_pelt_multiplier=4` | kernel |
| MGLRU | on (`lru_gen/enabled` `0x0003`) | kernel |
| THP | `never` | this tree, see `init.kernel.post_boot.sh` |
| zram | 6 GiB, `lz4` | ROM module default + AOSP `mmd` |
| DAMON reclaim / LRU sort | both `N` | off, nothing enables them |
| MTE / KASAN | compiled in, off at boot (`kasan=off`) | Xiaomi DTB cmdline |
| SELinux | genuinely `Enforcing` | see below |
| GPU ceiling | 900 MHz of an available 1100 | was this tree's powerhint, see below |

`/proc/config.gz` is present (system_server reads it) and is scrubbed of every
`CONFIG_KSU*`, `CONFIG_KPM*`, `KernelSU` and `SUSFS` line by the kernel's
`filechk_ikconfig`, so a root build is not identifiable from it.

## The GPU ceiling, measured

Worth recording because it took a device to see it and the config alone was
misleading in both directions.

`configs/power/powerhint.json` used to set the `GPUMaxFreq` node to
`DefaultIndex: 3` (900 MHz) with `ResetOnInit`, and nothing in the file ever
raised it again — the only action that writes `GPUMaxFreq` at all is
`DISPLAY_INACTIVE`, lowering it to 255 MHz for screen-off. Measured on the
device, screen on:

    devfreq/available_frequencies  1100 1000 950 900 835 736 684 633 500 353 255 (MHz)
    devfreq/max_freq               900000000
    max_gpuclk                     900000000
    thermal_pwrlevel               3

The cap is binding, not cosmetic. Forcing the governor's floor to the top OPP
while it was in place gave:

    min_freq written 1100000000 -> reads 900000000, cur_freq 900000000

i.e. the GPU physically could not leave 900 MHz. Lifting the ceiling the way
`DefaultIndex: 0` does gave, immediately:

    max_freq written 1100000000 -> reads 950000000, cur_freq 950000000

So removing the cap is worth a real 900 -> 950 MHz right now. It is not worth
the full 1100: above 950 the limiter is a *second, separate* mechanism — the
`gpu` thermal cooling device, sitting at `cur_state=2`. That one is not this
device tree's to set, it comes from the vendor thermal-engine configuration,
and at the time of measurement the GPU was at 33 °C, so it is a static
baseline rather than heat-driven throttling. Chasing the last two OPPs means
looking there, not at powerhint.json.

Both `max_freq` and `min_freq` are ordinary devfreq tunables and revert on
reboot; screen-off/screen-on cycles rewrite `max_freq` from the HAL
(255000000 / 900000000), which is a quick way to confirm the HAL, not the
kernel, owns this node.

## SELinux

The kernel does not fake `Enforcing` and neither should this tree. There is
nothing in the kernel that spoofs `getenforce`, and `androidboot.selinux=`
has been removed from `BOARD_BOOTCONFIG` — it was inert on a user build but
exposed `ro.boot.selinux=permissive` to every app while `getenforce` said
`Enforcing`, which is precisely the kind of contradiction root-detection
looks for.

## Checking a build before trusting it

The kernel tree ships an on-device gate. After flashing:

    adb push scripts/device/postflash-check.sh /data/local/tmp/
    adb shell sh /data/local/tmp/postflash-check.sh "<kernel.release>" <flavor>

It exits non-zero on a real problem and knows about this device's two
harmless stock-vendor `WARN_ON`s (`spmi-pmic-arb.c:309` from `qcom_spmi_pmic`
probing an absent PMIC address, and `irq/manage.c:914` from `goodix_ts`
resume). `scripts/device/device-probe.sh` in the same place dumps the tuning
state this document tabulates. Both are read-only.
