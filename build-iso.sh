#!/usr/bin/env bash
#
# Phaethon OS ISO Build Automation Tool
#
# Automates the setup of custom repositories, keyservers, permissions, and compiles 
# the bootable ISO using the custom archiso profile.
#
# Epitaph: "Though greatly he failed, more greatly he dared."
# Codename: Belle (v1.x)
#

# --- COLOR DEFINITIONS (Zenless Zone Zero theme) ---
export COLOR_BG="\e[38;2;10;10;10m"
export COLOR_ACCENT="\e[38;2;200;255;0m" # Neon Lime-yellow
export COLOR_GOLD="\e[38;2;212;175;55m"  # Emblem Gold
export COLOR_ERROR="\e[38;2;255;68;68m"   # Danger Red
export COLOR_WHITE="\e[38;2;255;255;255m"
export COLOR_MUTED="\e[38;2;136;136;136m"
export COLOR_RESET="\e[0m"

# Header logo
function show_banner() {
    clear
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

# Paths
export WORKSPACE_DIR="/home/suhl2/Documents/PhaethonOS"
export PROFILE_DIR="${WORKSPACE_DIR}/phaethon-iso"
export REPO_DIR="${WORKSPACE_DIR}/phaethon-repo"
export WORK_DIR="${WORKSPACE_DIR}/build_work"
export OUT_DIR="${WORKSPACE_DIR}/build_out"

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

# --- KEYRING SETUP & GPG INTEGRATIONS ---
echo -e "${COLOR_ACCENT}[+] Step 2: Configuring CachyOS and pacman signature keyrings...${COLOR_RESET}"
# Check if key is already imported into pacman
if ! pacman-key -list-keys F3B607488DB35C47 &>/dev/null; then
    echo -e "${COLOR_MUTED}[i] Importing CachyOS GPG master keys into system keyring...${COLOR_RESET}"
    pacman-key --recv-keys F3B607488DB35C47 --keyserver keyserver.ubuntu.com || true
    pacman-key --lsign-key F3B607488DB35C47 || true
    
    # We also download the cachyos-keyring and cachyos-mirrorlist directly for host validation
    echo -e "${COLOR_MUTED}[i] Ensuring CachyOS keyring packages are installed...${COLOR_RESET}"
    pacman -Sy --noconfirm --needed cachyos-keyring cachyos-mirrorlist
else
    echo -e "${COLOR_WHITE}[✔] CachyOS keyring already initialized.${COLOR_RESET}"
fi

# --- CORE INTEGRITY CHECKS ---
echo -e "${COLOR_ACCENT}[+] Step 3: Verifying workspace files...${COLOR_RESET}"
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
echo -e "${COLOR_ACCENT}[+] Step 4: Compiling bootable squashfs image with archiso...${COLOR_RESET}"
echo -e "${COLOR_MUTED}This process may take some time depending on your system and network throughput...${COLOR_RESET}"

# Execute archiso build
# -p specifies the profile path, -w work dir, -o output dir, -v verbose
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
