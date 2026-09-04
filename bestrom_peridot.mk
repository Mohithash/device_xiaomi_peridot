#
# Copyright (C) 2024 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# VOLTAGE_BUILD is load-bearing and is NOT just a version string.
# build/make/core/config.mk:501 wraps the entire VoltageOS board-config chain in
# "ifneq ($(VOLTAGE_BUILD),)", and that chain is what pulls in
# BoardConfigKernel.mk (the kernel build), BoardConfigQcom.mk (every
# hardware/qcom-caf + vendor/qcom soong namespace) and BoardConfigSoong.mk.
# build/make/envsetup.sh:452 only sets it for products literally named
# "voltage_*", so a rebranded product silently gets an empty value and loses
# all three - the failure surfaces far away, as "libwifi_hal_vendor_impl_defaults
# depends on undefined module libwifi-hal-qcom". Set it here so the product name
# stays bestrom_peridot.
VOLTAGE_BUILD := peridot

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common VoltageOS stuff.
# NOTE: choosing common_mobile over common_full_phone does NOT make the build
# minimal, contrary to what this comment used to claim. common_mobile.mk:2
# inherits common.mk, which at :267 includes packages.mk unconditionally and at
# :253 inherits fonts.mk - so every VoltageOS app and font ships either way.
# The entire delta is PRODUCT_SIZE, the LatinIME dictionaries overlay and
# ro.support_one_handed_mode. Actual slimming is done in debloat/Android.bp.
$(call inherit-product, vendor/voltage/config/common_mobile.mk)
$(call inherit-product, vendor/voltage/config/telephony.mk)

# Inherit from peridot device
$(call inherit-product, device/xiaomi/peridot/device.mk)

# VoltageOS version.mk downloads the official device list and errors out when
# VOLTAGE_BUILD_TYPE=OFFICIAL and the device is absent. peridot is not official.
VOLTAGE_BUILD_TYPE := UNOFFICIAL

# 1440x2560 15fps animation - see the boot animation note in BoardConfig.mk
TARGET_BOOT_ANIMATION_RES := 2560

PRODUCT_NAME := bestrom_peridot
PRODUCT_DEVICE := peridot
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_BRAND := POCO
PRODUCT_MODEL := 24069PC21G

PRODUCT_SYSTEM_NAME := peridot_global
PRODUCT_SYSTEM_DEVICE := peridot

# BestROM: this block is currently DEAD CODE. PRODUCT_BUILD_PROP_OVERRIDES is
# not registered in build/make/core/product.mk and is never exported into any
# soong json by build/make/core/soong_config.mk or soong_extra_config.mk, so
# override_config() in build/soong/scripts/gen_build_prop.py:50-64 never sees
# it. Verified in the built ROM: out/target/product/peridot/system/build.prop:29
# still reads
# ro.build.fingerprint=POCO/lineage_peridot/peridot:17/CP2A.260605.016/eng.sal:userdebug/test-keys.
# Gate it to user builds so that if the plumbing is ever restored it cannot
# stamp a "user/release-keys" fingerprint (and an Android-16 BuildDesc) onto an
# Android-17 userdebug/test-keys ROM. ro.build.type/ro.build.tags contradicting
# ro.build.fingerprint is a stronger tell than an honest userdebug fingerprint.
ifeq ($(TARGET_BUILD_VARIANT),user)
PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="peridot_global-user 16 BP2A.250605.031.A3 OS3.0.302.0.WNPMIXM release-keys" \
    BuildFingerprint=POCO/peridot_global/peridot:16/BP2A.250605.031.A3/OS3.0.302.0.WNPMIXM:user/release-keys \
    DeviceName=$(PRODUCT_SYSTEM_DEVICE) \
    DeviceProduct=$(PRODUCT_SYSTEM_NAME)
endif

PRODUCT_GMS_CLIENTID_BASE := android-xiaomi

# BestROM: the old PRODUCT_PACKAGES filter-out line lived here and NEVER
# WORKED. inherit-product defers its nodes, so at this point PRODUCT_PACKAGES
# holds only inherit markers and filter-out matches none of the real package
# names. Proof from the shipped build: DeviceAsWebcam, PrintSpooler and
# ThemePicker were all named in it and all three APKs shipped anyway.
# Packages contributed by inherited makefiles are removed instead via the
# RemovePackagesPeridot "overrides:" list in
# device/xiaomi/peridot/debloat/Android.bp. Add new removals THERE.

# BestROM branding
PRODUCT_PRODUCT_PROPERTIES += \
    ro.bestrom.version=1.0-a17 \
    ro.bestrom.device=peridot
