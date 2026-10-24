# Build Yocto for my zynq7010 camera project

## 1. Generate sdt from .xsa

Run `sdtgen` inside Vitis environment:
```
source <path-to-Vitis>/settings64.sh
sdtgen -xsa <path-to-xsa>.xsa -dir sdt_outdir
```


## 2. Start Ubuntu in Docker Container

Navigate to sw/bsp/ directory where Docker configuration resides:
```
cd sw/bsp
docker compose up -d --build
docker compose exec -u yocto yocto-builder bash
```

## 3. Init sources

*inside docker container

```
cd /workspace
repo init -u https://github.com/Xilinx/yocto-manifests.git \
            -b refs/tags/amd-edf-rel-v26.06.1 \
            -m default-edf.xml
repo sync
```


## 4. Generate machine-conf


`-c` - DIRECTORY where conf locates, not the local.conf!

```
gen-machine-conf parse-sdt \
  --hw-description /workspace/sdt_outdir \
  -c conf \
  --machine-name zynq7010-camera
```


## 5. Integrate custom layer


```
bitbake-layers add-layer /workspace/sw/bsp/meta-camera
```


### 5.1 system-user.dtsi

`device-tree.bb` (meta-xilinx-core) compiles DTB for BOOT.BIN and U-Boot control FDT. 
Recipe automatically includes only the .dtsi explicitly specified in 
`EXTRA_DT_INCLUDE_FILES`

File: `sw/bsp/meta-camera/recipes-bsp/device-treedevice-tree/device-tree.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " file://system-user.dtsi"
EXTRA_DT_INCLUDE_FILES:append = " system-user.dtsi"
```

*Warning:* Do not add `/include/ "system-conf.dtsi"` inside `system-user.dtsi` - it's a Petalinux-specific file,
which will break dtc compilation.

Verify after build:
```
strings build/tmp/deploy/images/zynq7010-camera/devicetree/cortexa9-linux.dtb | grep bootargs
```

### 5.2 bootargs

boot.scr (u-boot-edf-scr) reads bootargs from control FDT and appends to the end:
`root=PARTUUID=<uuid> ro rootwait`. Kernel takes the last `root=` parameter; `ro` 
overrides `rw` making root FS mount read-only.

## 6. Config Kernel

File: `sw/bsp/meta-camera/recipes-kernel/linux/files/user.cfg`:
```
CONFIG_UIO=y
CONFIG_UIO_PDRV_GENIRQ=y
CONFIG_CMA=y
CONFIG_CMA_SIZE_MBYTES=8
```

File: `sources/meta-camera/recipes-kernel/linux/linux-xlnx_%.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://user.cfg"
```


## 7. Image Recipe (`camera-image.bb`):

File: `sw/bsp/meta-camera/recipes-core/images/camera-image.bb`:

```
SUMMARY = "Custom Zynq-7010 Camera System Image"
LICENSE = "MIT"

inherit core-image

IMAGE_FEATURES += "ssh-server-openssh hwcodecs package-management"


IMAGE_INSTALL:append = " \
    sudo \
    e2fsprogs-mke2fs \
    fpga-manager-script \
    mtd-utils \
    nfs-utils \
    pciutils \
    vim \
    run-postinsts \
    libjpeg-turbo \
    libturbojpeg \
    opencv \
    udev-extraconf \
    linux-xlnx-udev-rules \
    bridge-utils \
    dosfstools \
    u-boot-tools \
    libdrm \
    libdrm-dev \
    tcf-agent \
    python3 \
    python3-modules \
    python3-pip \
    packagegroup-core-boot \
    bash \
    htop \
    media-ctl \
    devmem2 \
    ethtool \
    openssh \
    packagegroup-core-boot \
    packagegroup-core-buildessential \
"

INHERIT += "extrausers"

EXTRA_USERS_PARAMS = " \
    useradd -p '' petalinux; \
    groupadd aie; \
    usermod -a -G audio,video,input,sudo,aie petalinux; \
    usermod -p '\$6\$saltsalt\$Gv.mcbuxm6cZ2mSj5z7J0iC1aA3V1cM2vUvDxP3x1z/' root; \
"
    
custom_sudoers_config() {
    mkdir -p ${IMAGE_ROOTFS}${sysconfdir}/sudoers.d
    
    echo "petalinux ALL=(ALL) NOPASSWD: ALL" > ${IMAGE_ROOTFS}${sysconfdir}/sudoers.d/petalinux
    chmod 0440 ${IMAGE_ROOTFS}${sysconfdir}/sudoers.d/petalinux
}

ROOTFS_POSTPROCESS_COMMAND += "custom_sudoers_config; "    
```


## 8. Build Environment Configuration (`local.conf`)

Add the followinglines to `build/conf/local.conf`:
```
MACHINE = "zynq7010-camera"

IMAGE_FSTYPES += "wic wic.bmap tar.gz"

#p1 = FAT (boot), p2 = ext4 (rootfs)
EDF_ROOT_PARTNUM = "2"
IMAGE_BOOT_FILES = "boot.bin boot.scr uImage system.dtb"
```

### 8.1 Custom `boot.scr` Recipe

WIC layout (`xilinx-default-sd.wks`) places `/boot` 
contents onto FAT p1 and excludes `/boot` from ext4 p2. 
Stock `u-boot-edf-scr` looks for `/boot/uImage` on ext4 p2 and fails.

`meta-camera` overrides it with a customized boot command:
```
sw/bsp/meta-camera/recipes-bsp/u-boot/
├── u-boot-edf-scr_1.0.bb          # recipe copy from meta-amd-edf
└── files/
    └── edf-linux-boot.cmd         # our template (fatload uImage+system.dtb from p1)
```

## 8. Build Target Image

```
bitbake device-tree
bitbake linux-xlnx -c configure
bitbake camera-image
```

if `boot.scr`, device tree, or partition layouts are updated, force rebuild dependent targets:
```
bitbake u-boot-edf-scr device-tree camera-image
```

## 9. Build SDK (Optional)

```
bitbake camera-image -c do_populate_sdk
```

## 10. Flash to SD

```
sudo dd if=build/tmp/deploy/images/zynq7010-camera/camera-image-zynq7010-camera.rootfs.wic \
        of=/dev/sdX bs=4M conv=fsync status=progress
sync
```
Check boot.scr before start:
```
strings build/tmp/deploy/images/zynq7010-camera/boot.scr | grep rootpartnum
# Expected: setenv rootpartnum 2
```
