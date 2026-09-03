#=============================================================================
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# All rights reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#=============================================================================

enable_thp()
{
	# Deliberately does NOT touch /sys/kernel/mm/transparent_hugepage/enabled.
	#
	# This script (service memory-boot) and init.kernel.post_boot.sh (service
	# kernel-post-boot) are both class core oneshot services started off the
	# same trigger, and this one used to write "always" while the other writes
	# "never". Whichever ran last won, so a memory setting that changes fault
	# and reclaim behaviour device-wide was decided by service start order.
	#
	# "never" is the right answer here and is what the device actually runs:
	# init.kernel.post_boot.sh explains it ("We do not use THP, so having many
	# huge pages is not as necessary") and then tunes khugepaged to be inert --
	# defrag off, one page per scan, maximum sleep -- which only makes sense
	# with THP disabled. Leaving the write out here makes that deterministic
	# instead of ordering-dependent. The PASR setup below is what this script
	# is actually for.

	#Enable the PASR support
	ddr_type=`od -An -tx /proc/device-tree/memory/ddr_device_type`
	ddr_type5="08"

	if [ -d /sys/kernel/mem-offline ]; then
		#only LPDDR5 supports PAAR
		if [ ${ddr_type:4:2} != $ddr_type5 ]; then
			setprop vendor.pasr.activemode.enabled false
		fi
		setprop vendor.pasr.enabled true
	else
		setprop vendor.pasr.enabled false
	fi
}

enable_thp
