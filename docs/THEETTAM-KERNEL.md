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
the full 1100, and the reason is worth spelling out, because it is not what
it looks like.

### The second limiter is mi_thermald, and it is not temperature-driven

Above 950 MHz the ceiling comes from `cooling_device37`, whose type string is
`gpu`. Three things about it:

1. **No thermal zone binds it.** Walking every
   `/sys/class/thermal/thermal_zone*/cdev*` link, all eleven GPU bindings
   resolve to `cooling_device36` (`devfreq-3d00000.qcom,kgsl-3d0`) — the
   kernel's own devfreq cooling device, bound to the `gpuss-0..3` zones with
   real trip points. That one reads `cur_state=0`: the actual
   temperature-driven protection is not throttling at all.
2. **`cooling_device37` is driven from userspace by `mi_thermald`**, via
   `/vendor/etc/thermald-devices.conf` (`name:gpu`, `cooling_name:gpu`).
3. **Its policy is a permanently-tripped trip point.** The decrypted Xiaomi
   map for this region (`ro.boot.hwc=IN`) at `/data/vendor/thermal/decrypt.txt`:

        [INDIA-MONITOR-GPU]
        algo_type  monitor
        sensor     VIRTUAL-SENSOR0
        device     gpu
        polling    2000
        trig       15000
        clr        13000
        target     3

   `trig 15000` is 15 °C, and `VIRTUAL-SENSOR0` is a weighted composite of
   cpu/battery/charger/wifi/pa/quiet sensors that reads ~35–36 °C in ordinary
   use. The trip is therefore *always* tripped, at any temperature the phone
   will ever see, and `mi_thermald` requests GPU cooling state 3 forever.
   `/data/vendor/thermal/thermal.dump` shows it doing exactly that:
   `[INDIA-MONITOR-GPU][VIRTUAL-SENSOR0 36196] {[gpu 3]...}`.

So the 950 MHz ceiling is a permanent policy cap wearing thermal clothing,
not heat management.

### Why it lands on 950 and not 900

Because this kernel already softens it. `drivers/thermal/qcom/qti_devfreq_cdev.c`
carries commit 80accb269363, "thermal: cpu_cooling, gpu_cooling: tune cdev
limits to prevent thermal throttling under sustained load", which remaps
mid-range cooling states while leaving the bottom and the critical tail
alone (`DEVFREQ_SOFT_THROTTLE_START_STATE 1`, `_DIVIDER 2`,
`_CRITICAL_TAIL_STATES 2`):

        mi_thermald asks  0 -> stored  0 -> 1100 MHz
        mi_thermald asks  1 -> stored  1 -> 1000 MHz
        mi_thermald asks  2 -> stored  2 ->  950 MHz
        mi_thermald asks  3 -> stored  2 ->  950 MHz   <-- this device, always
        mi_thermald asks  4 -> stored  3 ->  900 MHz
        ...
        mi_thermald asks  9 -> stored  9 ->  353 MHz   <-- tail untouched
        mi_thermald asks 10 -> stored 10 ->  255 MHz

Xiaomi asks for state 3 (900 MHz); the kernel stores 2 (950 MHz). The
emergency states at the top of the range are deliberately left unmapped, so
genuine critical throttling still works at full strength.

Measured directly, by driving `cooling_device37/cur_state` with the power-HAL
ceiling already lifted to 1100000000 (device idle at 35 °C, screen on, each
state read back immediately, `mi_thermald` re-asserting within its 2000 ms
poll):

        written   stored    max_freq       thermal_pwrlevel
        0         0         1100000000     0
        1         1         1000000000     1
        2         2          950000000     2
        4         3          900000000     3
        3         2          950000000     2

Two things this proves. Writing 4 stores 3 and writing 3 stores 2, which is
`devfreq_cdev_map_state()` doing exactly the arithmetic above — the remap is
real and active on this device, not merely present in the source. And at
state 0 the GPU reaches the full 1100 MHz, so the OPP table and the hardware
support the top level; nothing but the cooling request holds it down.

GPU temperature fell slightly across the run (35.5 -> 34.7 °C), which is the
expected result: raising a *ceiling* while idle changes nothing, because the
governor only selects a higher frequency under load.

The state then becomes a `DEV_PM_QOS_MAX_FREQUENCY` request on the kgsl
devfreq device, and PM QoS aggregates that class as the *minimum* of all
requests — which is why writing 1100000000 to `max_freq` reads back
950000000 while this request stands, and why the screen-off
`DISPLAY_INACTIVE` value of 255 MHz wins over both.

### What this tree can and cannot do about it

`mi_thermald`, `thermald-devices.conf`, `thermal-map.conf` and
`thermal-map-india.conf` are all extracted vendor blobs (`proprietary-files.txt`),
not files this tree authors, and the map is encrypted. So there is no clean
device-tree edit here. The levers, in increasing order of nerve:

- leave it (the kernel remap already recovered one OPP);
- ship an edited `thermald-devices.conf` that does not map the `gpu` device,
  so `mi_thermald` cannot drive the cdev at all — the kernel `gpuss` zones
  keep protecting the GPU;
- retune the remap constants in `qti_devfreq_cdev.c`.

Anything beyond the first is a real thermal decision and wants sustained-load
measurement, not reasoning. Note also that Xiaomi's own userspace has never
used the top two OPPs on this device, which is a reason for caution rather
than evidence of a problem.

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
