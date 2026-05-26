#!/usr/bin/env bash
# shellcheck disable=SC2034

# ==============================================================================
# PHAETHONOS - PROFILE DEFINITION
# ==============================================================================
# Shipped at: /home/suhl2/Documents/PhaethonOS/phaethon-iso/profiledef.sh
# Core configuration defining ISO metadata, boot loaders, squashfs compression,
# and fine-grained root filesystem execution permissions.
#

iso_name="phaethon-os"
iso_label="PHAETHON_BELLE"
iso_publisher="PhaethonOS Project <https://phaethon.suhl2.xyz>"
iso_application="PhaethonOS Live/Installation System"
iso_version="v1.0.0-Belle" # Codename: Belle (v1.x)
arch="x86_64"
pacman_conf="pacman.conf"
buildmodes=('iso')

# Boot loader capabilities
bootmodes=('bios.syslinux'
           'uefi.grub')

# Root filesystem type and high-efficiency XZ compression parameters
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')

# Fine-grained file permissions setup for special files, credentials, and custom executables
file_permissions=(
    ["/etc/shadow"]="0:0:400"
    ["/etc/gshadow"]="0:0:400"
    ["/root"]="0:0:750"
    ["/root/.gnupg"]="0:0:700"
    ["/usr/local/bin/choose-mirror"]="0:0:755"
    ["/usr/local/bin/Installation_guide"]="0:0:755"
    ["/usr/local/bin/livecd-sound"]="0:0:755"
    ["/etc/sysctl.d/99-phaethon.conf"]="0:0:644"
    ["/usr/local/bin/phaethon-init.sh"]="0:0:755"
    ["/usr/local/bin/phaethon-calamares"]="0:0:755"
    ["/usr/local/bin/phaethon-welcome"]="0:0:755"
    ["/etc/polkit-1/rules.d/10-calamares-nopasswd.rules"]="0:0:644"
    ["/etc/sudoers.d/g_wheel"]="0:0:440"
    ["/usr/local/bin/phaethon-fix-libs.sh"]="0:0:755"
)

