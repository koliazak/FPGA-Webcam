FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " file://system-user.dtsi"

# device-tree.bb only compiles dtsi files listed in EXTRA_DT_INCLUDE_FILES
EXTRA_DT_INCLUDE_FILES:append = " system-user.dtsi"
