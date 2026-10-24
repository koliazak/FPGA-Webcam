# Boot script for U-Boot - AMD Embedded Development Framework
# meta-camera override: xilinx-default-sd.wks puts the rootfs /boot content
# on the FAT partition (p1) and EXCLUDES /boot from the ext4 rootfs (p2),
# so the stock EDF script (ext4load of /boot/uImage from p2) can never work.
# This variant loads kernel + DTB from the FAT boot partition.

setenv kernel_name @@KERNEL_IMAGE@@
setenv bootpartnum 1
setenv rootpartnum @@ROOT_PARTNUM@@
setenv kernel_bootcmd @@KERNEL_BOOTCMD@@

echo "=== Loading Kernel from partition ${bootpartnum} ==="
if test -e ${devtype} ${devnum}:${bootpartnum} /${kernel_name}; then
	fatload ${devtype} ${devnum}:${bootpartnum} ${kernel_addr_r} /${kernel_name}
else
	echo "ERROR: Kernel image not found on ${devtype} ${devnum}:${bootpartnum}"
	exit
fi

if test -e ${devtype} ${devnum}:${bootpartnum} /system.dtb; then
	fatload ${devtype} ${devnum}:${bootpartnum} ${fdt_addr_r} /system.dtb
else
	echo "ERROR: system.dtb not found on ${devtype} ${devnum}:${bootpartnum}"
	exit
fi

part uuid ${devtype} ${devnum}:${rootpartnum} distro_rootpart_uuid

setenv bootargs "earlycon console=ttyPS0,115200 clk_ignore_unused root=PARTUUID=${distro_rootpart_uuid} rw rootwait cma=8M uio_pdrv_genirq.of_id=generic-uio"

${kernel_bootcmd} ${kernel_addr_r} - ${fdt_addr_r}
