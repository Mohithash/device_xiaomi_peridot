#! /vendor/bin/sh

# Copyright (c) 2012-2013, 2016-2021, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

target=`getprop ro.board.platform`

case "$target" in
        "pineapple" | "cliffs")
                if [ -f /sys/devices/soc0/chip_family ]; then
                        chip_family_id=`cat /sys/devices/soc0/chip_family`
                else
                        chip_family_id=-1
                fi

                echo "adsprpc : chip_family_id : $chip_faily_id" > /dev/kmsg

                case "$chip_family_id" in
                    "0x8a" | "0x94")
                    if [ -f /sys/devices/platform/soc/soc:qcom,msm_fastrpc/fastrpc_nsp_status ]; then
                        fastrpc_nsp_status=`cat /sys/devices/platform/soc/soc:qcom,msm_fastrpc/fastrpc_nsp_status`
                    else
                        fastrpc_nsp_status=-1
                    fi

                    echo "adsprpc : fastrpc_nsp_status : $fastrpc_nsp_status" > /dev/kmsg

                    if [ $fastrpc_nsp_status -eq 0 ]; then
                            setprop vendor.fastrpc.disable.cdsprpcd.daemon 1
                            echo "adsprpc : Disabled cdsp daemon" > /dev/kmsg
                    fi
                esac
                 ;;
esac

emmc_boot=`getprop vendor.boot.emmc`
case "$emmc_boot"
    in "true")
        chown -h system /sys/devices/platform/rs300000a7.65536/force_sync
        chown -h system /sys/devices/platform/rs300000a7.65536/sync_sts
        chown -h system /sys/devices/platform/rs300100a7.65536/force_sync
        chown -h system /sys/devices/platform/rs300100a7.65536/sync_sts
    ;;
esac

# Let kernel know our image version/variant/crm_version
if [ -f /sys/devices/soc0/select_image ]; then
    image_version="10:"
    image_version+=`getprop ro.build.id`
    image_version+=":"
    image_version+=`getprop ro.build.version.incremental`
    image_variant=`getprop ro.product.name`
    image_variant+="-"
    image_variant+=`getprop ro.build.type`
    oem_version=`getprop ro.build.version.codename`
    echo 10 > /sys/devices/soc0/select_image
    echo $image_version > /sys/devices/soc0/image_version
    echo $image_variant > /sys/devices/soc0/image_variant
    echo $oem_version > /sys/devices/soc0/image_crm_version
fi

# Change console log level as per console config property
console_config=`getprop persist.vendor.console.silent.config`
case "$console_config" in
    "1")
        echo "Enable console config to $console_config"
        echo 0 > /proc/sys/kernel/printk
        ;;
    *)
        echo "Enable console config to $console_config"
        ;;
esac

# Parse misc partition path and set property
misc_link=$(ls -l /dev/block/bootdevice/by-name/misc)
real_path=${misc_link##*>}
setprop persist.vendor.mmi.misc_dev_path $real_path

# Pin the display and GPU interrupts off CPU0.
#
# This used to live in init.peridot.rc as two hard-coded writes to IRQ 70 and
# 222, labelled msm_drm0 and kgsl_3d0_irq. Linux hands out IRQ numbers in
# probe order, so they are not stable: on 6.1.176 IRQ 70 is
# arm-smmu-context-fault and IRQ 222 is wdog, and both writes landed on those
# instead, while msm_drm (330) and kgsl_3d0_irq (324) stayed on CPU0 with
# every other interrupt. Resolve them by name so the fix survives a kernel
# bump, and skip quietly if the name is absent.
pin_irq_by_name() {
    irq=`awk -v n="$1" '$NF == n { sub(":", "", $1); print $1; exit }' /proc/interrupts`
    if [ -n "$irq" ] && [ -w /proc/irq/$irq/smp_affinity_list ]; then
        echo "$2" > /proc/irq/$irq/smp_affinity_list
    fi
}

# Silver cores are 0-2; leave CPU0 for the general interrupt load.
pin_irq_by_name msm_drm 2
pin_irq_by_name kgsl_3d0_irq 1
