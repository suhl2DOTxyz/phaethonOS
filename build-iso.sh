#!/usr/bin/env bash
#
# Phaethon OS ISO Build Automation Tool
#
# Automates the setup of custom repositories and compiles
# the bootable ISO using the custom archiso profile.
#
# Epitaph: "Though greatly he failed, more greatly he dared."
# Codename: Belle (v1.x)
#
# Host-agnostic: works on any Arch Linux system with archiso installed.
#

# --- COLOR DEFINITIONS (Zenless Zone Zero theme) ---
COLOR_BG="\e[38;2;10;10;10m"
COLOR_ACCENT="\e[38;2;200;255;0m" # Neon Lime-yellow
COLOR_GOLD="\e[38;2;212;175;55m"  # Emblem Gold
COLOR_ERROR="\e[38;2;255;68;68m"  # Danger Red
COLOR_WHITE="\e[38;2;255;255;255m"
COLOR_MUTED="\e[38;2;136;136;136m"
COLOR_RESET="\e[0m"

# Resolve paths relative to the script's location (portable across machines)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

WORKSPACE_DIR="${SCRIPT_DIR}"
PROFILE_DIR="${WORKSPACE_DIR}/phaethon-iso"
REPO_DIR="${WORKSPACE_DIR}/phaethon-repo"
WORK_DIR="${WORKSPACE_DIR}/build_work"
OUT_DIR="${WORKSPACE_DIR}/build_out"

# Header logo
show_banner() {
    if [ -n "${TERM}" ]; then
        clear 2>/dev/null || true
    fi
    echo -e "${COLOR_GOLD}"
    echo "         P H A E T H O N   O S   -   B U I L D E R"
    echo "       \"Though greatly he failed, more greatly he dared.\""
    echo "                 Codename: Belle (v1.0.0)"
    echo -e "${COLOR_RESET}"
}

show_banner

# --- SAFETY CHECKS ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${COLOR_ERROR}[ERROR] This build tool must be executed with root permissions (sudo).${COLOR_RESET}"
   echo "        Root privileges are required by archiso to mount, chroot, and set system permissions."
   exit 1
fi

# --- REPOSITORY LAYOUT VERIFICATION ---
echo -e "${COLOR_ACCENT}[+] Step 1: Initializing custom workspace directories...${COLOR_RESET}"
mkdir -p "${REPO_DIR}/x86_64"
mkdir -p "${WORK_DIR}"
mkdir -p "${OUT_DIR}"
mkdir -p "${PROFILE_DIR}/airootfs/usr/share/phaethon"

# Initialize local package repo DB if missing
if [ ! -f "${REPO_DIR}/x86_64/phaethon.db.tar.gz" ]; then
    PKGS=$(find "${REPO_DIR}/x86_64" -name "*.pkg.tar.*" 2>/dev/null | head -1)
    if [ -n "${PKGS}" ]; then
        echo -e "${COLOR_MUTED}[i] Initializing repository database with discovered packages...${COLOR_RESET}"
        repo-add "${REPO_DIR}/x86_64/phaethon.db.tar.gz" "${PKGS}"
    else
        echo -e "${COLOR_WHITE}[i] No packages yet. Creating placeholder repository database...${COLOR_RESET}"
        mkdir -p "${REPO_DIR}/x86_64"
        touch "${REPO_DIR}/x86_64/phaethon.db.tar.gz"
    fi
fi

# --- CORE INTEGRITY CHECKS ---
echo -e "${COLOR_ACCENT}[+] Step 2: Verifying workspace files...${COLOR_RESET}"
if [ ! -f "${PROFILE_DIR}/pacman.conf" ]; then
    echo -e "${COLOR_ERROR}[ERROR] Custom pacman.conf not found at ${PROFILE_DIR}/pacman.conf!${COLOR_RESET}"
    exit 1
fi

# Ensure high-res logo copy exists
if [ -f "${WORKSPACE_DIR}/phaethon-logo.png" ]; then
    cp "${WORKSPACE_DIR}/phaethon-logo.png" "${PROFILE_DIR}/airootfs/usr/share/phaethon/phaethon-logo.png"
    cp "${WORKSPACE_DIR}/phaethon-logo.png" "${PROFILE_DIR}/airootfs/usr/share/calamares/branding/phaethon/phaethon-logo.png"
    echo -e "${COLOR_WHITE}[✔] Distro branding logo matched and copied.${COLOR_RESET}"
else
    echo -e "${COLOR_ERROR}[ERROR] Branding logo missing at ${WORKSPACE_DIR}/phaethon-logo.png!${COLOR_RESET}"
    exit 1
fi

# Sync latest welcome-app source files to filesystem overlay
echo -e "${COLOR_MUTED}[i] Syncing Welcome App assets to filesystem overlay...${COLOR_RESET}"
mkdir -p "${PROFILE_DIR}/airootfs/usr/share/phaethon-welcome-app"
cp -r "${WORKSPACE_DIR}/welcome-app/"* "${PROFILE_DIR}/airootfs/usr/share/phaethon-welcome-app/"
echo -e "${COLOR_WHITE}[✔] Welcome App source synchronized.${COLOR_RESET}"

# --- COMPILING THE LIVE ISO ---
echo -e "${COLOR_ACCENT}[+] Step 3: Compiling bootable squashfs image with archiso...${COLOR_RESET}"
echo -e "${COLOR_MUTED}This process may take some time depending on your system and network throughput...${COLOR_RESET}"

# Execute archiso build
# -w work dir, -o output dir, -v verbose
mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${PROFILE_DIR}"

BUILD_STATUS=$?
if [ ${BUILD_STATUS} -eq 0 ]; then
    echo -e "${COLOR_GOLD}"
    echo "=========================================================================="
    echo "  P H A E T H O N   O S   C O M P I L A T I O N   C O M P L E T E D !"
    echo "=========================================================================="
    echo -e "Bootable ISO compiled successfully! File is saved at:"
    echo -e "${COLOR_ACCENT}${OUT_DIR}/phaethon-os-v1.0.0-Belle-x86_64.iso${COLOR_RESET}"
else
    echo -e "${COLOR_ERROR}[ERROR] Compilation failed during mkarchiso execution (Exit Code: ${BUILD_STATUS}).${COLOR_RESET}"
    exit ${BUILD_STATUS}
fi
