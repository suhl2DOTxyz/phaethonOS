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

# Keep the live filesystem's copy of the GRUB theme in sync with the ISO's.
# phaethon-iso/grub/themes/phaethon is the single source of truth: mkarchiso
# copies it to /boot/grub/themes on the ISO for the live boot menu, and this
# copy lands in the live root at /usr/share/grub/themes so Calamares
# (shellprocess@before-online) can install it onto the target system.
echo -e "${COLOR_MUTED}[i] Syncing GRUB theme to filesystem overlay...${COLOR_RESET}"
mkdir -p "${PROFILE_DIR}/airootfs/usr/share/grub/themes"
rm -rf "${PROFILE_DIR}/airootfs/usr/share/grub/themes/phaethon"
cp -aT "${PROFILE_DIR}/grub/themes/phaethon" "${PROFILE_DIR}/airootfs/usr/share/grub/themes/phaethon"
echo -e "${COLOR_WHITE}[✔] GRUB theme synchronized.${COLOR_RESET}"

# ==============================================================================
# VENDOR THE BOOST RELEASE cachyos-calamares WAS BUILT AGAINST
# ==============================================================================
# cachyos-calamares 3.4.2-4 links libboost_python314.so.1.91.0. Arch has since
# moved to boost 1.92, and CachyOS has not rebuilt the package, so the installer
# dies at startup:
#
#   /usr/bin/calamares: symbol lookup error: /usr/lib/libcalamares.so.3.4:
#   undefined symbol: boost::python::detail::init_module(PyModuleDef&, void(*)())
#
# Symlinking 1.91 -> 1.92 does not work: boost 1.92 dropped that overload.
# The sonames differ, so instead we ship the 1.91 runtime library alongside
# 1.92. Nothing is downgraded and no other package is affected -- only
# Calamares looks for the 1.91 soname.
#
# Remove this block once cachyos-calamares is rebuilt against current boost.
BOOST_SO="libboost_python${PY_ABI:-314}.so.1.91.0"
BOOST_DEST="${PROFILE_DIR}/airootfs/usr/lib/${BOOST_SO}"
ARCHIVE="https://archive.archlinux.org/packages/b/boost-libs"

if [ -f "${BOOST_DEST}" ]; then
    echo -e "${COLOR_WHITE}[✔] Vendored ${BOOST_SO} already present.${COLOR_RESET}"
else
    echo -e "${COLOR_MUTED}[i] Fetching ${BOOST_SO} from the Arch archive...${COLOR_RESET}"
    mkdir -p "${PROFILE_DIR}/airootfs/usr/lib"
    BOOST_TMP="$(mktemp -d)"

    # Several pkgrels of 1.91.0 exist and only the later ones were rebuilt
    # against Python 3.14. Walk them newest-first and keep the first package
    # that actually contains the soname we need.
    PKG_LIST="$(curl -fsSL "${ARCHIVE}/" 2>/dev/null |
                grep -oE 'boost-libs-1\.91\.0-[0-9]+-x86_64\.pkg\.tar\.zst' |
                sort -Vu | tac)"

    if [ -z "${PKG_LIST}" ]; then
        echo -e "${COLOR_ERROR}[ERROR] Could not reach ${ARCHIVE}/ to fetch boost 1.91.${COLOR_RESET}"
        echo    "        Calamares will not start without ${BOOST_SO}."
        rm -rf "${BOOST_TMP}"; exit 1
    fi

    for PKG in ${PKG_LIST}; do
        echo -e "${COLOR_MUTED}    trying ${PKG}${COLOR_RESET}"
        if curl -fsSL "${ARCHIVE}/${PKG}" -o "${BOOST_TMP}/pkg.tar.zst" &&
           bsdtar -xf "${BOOST_TMP}/pkg.tar.zst" -C "${BOOST_TMP}" "usr/lib/${BOOST_SO}" 2>/dev/null; then
            cp "${BOOST_TMP}/usr/lib/${BOOST_SO}" "${BOOST_DEST}"
            break
        fi
    done

    rm -rf "${BOOST_TMP}"

    if [ ! -f "${BOOST_DEST}" ]; then
        echo -e "${COLOR_ERROR}[ERROR] No boost-libs 1.91.0 package contained ${BOOST_SO}.${COLOR_RESET}"
        echo    "        The Python ABI suffix is probably wrong; check what"
        echo    "        cachyos-calamares actually links with:"
        echo    "          ldd /usr/bin/calamares | grep boost_python"
        exit 1
    fi

    # Fail here rather than in the VM: the whole point of this file is one
    # symbol, so prove it is exported before shipping an ISO around it.
    # nm is preferred (it distinguishes defined from referenced symbols) but
    # binutils is not guaranteed in a bare build container, so fall back to
    # grepping .dynstr, where the mangled name appears literally.
    if command -v nm >/dev/null 2>&1; then
        BOOST_HAS_SYM=$(nm -D --defined-only "${BOOST_DEST}" 2>/dev/null |
                        grep -c '_ZN5boost6python6detail11init_moduleER11PyModuleDefPFvvE')
    else
        BOOST_HAS_SYM=$(grep -ac '_ZN5boost6python6detail11init_moduleER11PyModuleDefPFvvE' "${BOOST_DEST}")
    fi
    if [ "${BOOST_HAS_SYM:-0}" -eq 0 ]; then
        echo -e "${COLOR_ERROR}[ERROR] ${BOOST_SO} does not export boost::python::detail::init_module.${COLOR_RESET}"
        echo    "        Shipping it would reproduce the symbol lookup error."
        rm -f "${BOOST_DEST}"; exit 1
    fi
    echo -e "${COLOR_WHITE}[✔] Vendored ${BOOST_SO} (init_module verified present).${COLOR_RESET}"
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
