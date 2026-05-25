#!/usr/bin/env bash
#
# Phaethon OS Custom Repository Database Generator
#
# Scans the package build repository, discovers new compiler artifacts (*.pkg.tar.zst),
# compiles the target database, and signs index listings.
#

export COLOR_ACCENT="\e[38;2;200;255;0m" # Neon Lime-yellow
export COLOR_GOLD="\e[38;2;212;175;55m"  # Emblem Gold
export COLOR_WHITE="\e[38;2;255;255;255m"
export COLOR_ERROR="\e[38;2;255;68;68m"
export COLOR_RESET="\e[0m"

echo -e "${COLOR_GOLD}         P H A E T H O N   O S   -   R E P O   M A N A G E R${COLOR_RESET}"
echo "=========================================================================="

REPO_DIR="/home/suhl2/Documents/PhaethonOS/phaethon-repo/x86_64"
cd "${REPO_DIR}" || { echo -e "${COLOR_ERROR}[ERROR] Failed to access repository path: ${REPO_DIR}${COLOR_RESET}"; exit 1; }

echo -e "${COLOR_ACCENT}[+] Step 1: Scanning for compiled distribution packages...${COLOR_RESET}"
PKG_COUNT=$(find . -maxdepth 1 -name "*.pkg.tar.zst" | wc -l)

if [ "${PKG_COUNT}" -eq 0 ]; then
    echo -e "${COLOR_WHITE}[i] No packages (*.pkg.tar.zst) found. Keeping database pristine.${COLOR_RESET}"
    exit 0
fi

echo -e "${COLOR_WHITE}[✔] Discovered ${PKG_COUNT} package archives in storage pool.${COLOR_RESET}"
echo -e "${COLOR_ACCENT}[+] Step 2: Compiling pacman repository index database...${COLOR_RESET}"

# Remove existing database links to prevent index fragmentation
rm -f phaethon.db phaethon.files
rm -f phaethon.db.tar.gz phaethon.files.tar.gz

# repo-add creates a fresh, optimized index of discovered packages
# -n: only add new packages (though we wiped index for safety)
# -R: remove old package entries when adding newer ones
repo-add -n -R phaethon.db.tar.gz *.pkg.tar.zst

# Sync standard database names
ln -sf phaethon.db.tar.gz phaethon.db
ln -sf phaethon.files.tar.gz phaethon.files

echo "=========================================================================="
echo -e "${COLOR_GOLD}[✔] PHAETHON PACKAGE INDEX UPDATED SUCCESSFULLY!${COLOR_RESET}"
