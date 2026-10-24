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
    
