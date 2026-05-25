#!/usr/bin/env bash
#
# Phaethon OS ISO Build Cleanup Tool
#
# Safely unmounts hanging interfaces and removes compiled files, caches,
# and working build directories. Requires root permissions.
#

export COLOR_ACCENT="\e[38;2;200;255;0m" # Neon Lime-yellow
export COLOR_ERROR="\e[38;2;255;68;68m"   # Danger Red
export COLOR_WHITE="\e[38;2;255;255;255m"
export COLOR_RESET="\e[0m"

# Header
echo -e "${COLOR_ACCENT}         P H A E T H O N   O S   -   C L E A N E R${COLOR_RESET}"
echo "=========================================================================="

if [[ $EUID -ne 0 ]]; then
   echo -e "${COLOR_ERROR}[ERROR] This clean tool must be executed with root permissions (sudo).${COLOR_RESET}"
   exit 1
fi

WORKSPACE_DIR="/home/suhl2/Documents/PhaethonOS"
WORK_DIR="${WORKSPACE_DIR}/build_work"
OUT_DIR="${WORKSPACE_DIR}/build_out"

echo -e "${COLOR_ACCENT}[+] Step 1: Checking for mounted images and active systems...${COLOR_RESET}"

# Find any active loopback mounts or squashfs mounts left by aborted archiso runs
if mount | grep -q "${WORK_DIR}"; then
    echo -e "${COLOR_ERROR}[!] Detected active mounts under working directory. Attempting lazy unmount...${COLOR_RESET}"
    umount -l "${WORK_DIR}"/* 2>/dev/null
    umount -l "${WORK_DIR}" 2>/dev/null
fi

echo -e "${COLOR_ACCENT}[+] Step 2: Removing build output cache and work pools...${COLOR_RESET}"

if [ -d "${WORK_DIR}" ]; then
    rm -rf "${WORK_DIR}"
    echo -e "${COLOR_WHITE}[✔] Successfully cleaned temporary compile directory: ${WORK_DIR}${COLOR_RESET}"
else
    echo -e "${COLOR_WHITE}[✔] Compile directory already clean.${COLOR_RESET}"
fi

if [ -d "${OUT_DIR}" ]; then
    rm -rf "${OUT_DIR}"
    echo -e "${COLOR_WHITE}[✔] Successfully cleaned build output directory: ${OUT_DIR}${COLOR_RESET}"
else
    echo -e "${COLOR_WHITE}[✔] Build output directory already clean.${COLOR_RESET}"
fi

echo "=========================================================================="
echo -e "${COLOR_ACCENT}[✔] WORKSPACE RESETS COMPLETE.${COLOR_RESET}"
