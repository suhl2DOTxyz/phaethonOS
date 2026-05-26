# Phaethon OS

*"Though greatly he failed, more greatly he dared."*

**Codename: Belle (v1.x)**

A custom Arch Linux live ISO distribution featuring the [CachyOS](https://cachyos.org/) kernel and repositories, with Calamares as the system installer.

## Features

- **CachyOS kernel** (`linux-cachyos`) with scheduler optimizations
- **Calamares installer** (`cachyos-calamares`) for guided system installation
- **Custom GRUB theme** — Zenless Zone Zero-inspired black-and-neon-lime graphical menu
- **Live session** with full desktop, network access (`sudo pacman -Sy` works out of the box), and pre-configured Arch + CachyOS mirrors
- **Welcome App** — first-boot information panel
- **UEFI (x64/IA32) and BIOS** boot support

## Build Requirements

- **Arch Linux** (or a derivative with `archiso`)
- `archiso` package installed
- Root access (`sudo`) for `mkarchiso`
- ~15 GB free disk space during build
- Active internet connection (packages are downloaded fresh each build)

## Building the ISO

```bash
# Clone the repository
git clone https://github.com/suhl2DOTxyz/phaethonOS.git
cd phaethonOS

# Install build dependency
sudo pacman -S --needed archiso

# Build the ISO (requires root)
sudo bash build-iso.sh
```

The finished ISO will be written to `build_out/phaethon-os-v1.0.0-Belle-x86_64.iso`.

## Quick Build (skip clean)

If you just want to rebuild without running the full clean script:

```bash
sudo mkarchiso -v -w build_work -o build_out phaethon-iso/
```

## Using GitHub Actions to build

If you'd like to build the ISO yet do not have an Arch Linux machine (or simply do not want to clone the repo and build), you can go to the Actions page of this repo and click "Build Phaethon OS ISO" and run the workflow. If this fails, try forking the repo.

## Clean Build Artifacts

```bash
sudo bash clean.sh
```

This removes `build_work/` and `build_out/`.

## Project Structure

```
phaethon-iso/              # archiso build profile
├── airootfs/              # Overlay files injected into the live system
│   ├── etc/
│   │   ├── calamares/     # Calamares settings
│   │   ├── pacman.conf    # Live-session pacman config (Arch + CachyOS)
│   │   └── pacman.d/      # Mirror list
│   └── usr/local/bin/     # Helper scripts (calamares runner, fix-libs)
├── grub/
│   ├── fonts/unicode.pf2  # GRUB Unicode font (required for graphical theme)
│   ├── grub.cfg           # Main GRUB boot menu config
│   ├── loopback.cfg       # Loopback boot entry
│   └── themes/phaethon/   # Custom GRUB theme assets
├── packages.x86_64        # Package list for the live ISO
├── pacman.conf            # Profile-level pacman config (host-side)
├── profiledef.sh          # ISO metadata (label, publisher, etc.)
└── syslinux/              # SYSLINUX BIOS boot config
```

## Key Design Decisions

- **CachyOS kernel + repos**: Provides performance-tuned kernel packages and a maintained Calamares fork (`cachyos-calamares`) with 62 module configs. The profile does NOT duplicate these module configs in the overlay.
- **Library symlink at runtime**: `libyaml-cpp.so.0.8` is provided via a systemd oneshot + wrapper-script fallback rather than a static pre-built symlink, keeping it resilient across minor yaml-cpp version bumps.
- **GRUB font required**: The custom theme depends on `unicode.pf2` being present at `/boot/grub/fonts/` in the ISO. Without it, `loadfont` fails and GRUB falls back to the plain text menu.

## Burning to USB

```bash
# Using dd (replace /dev/sdX with your device)
sudo dd if=build_out/phaethon-os-v1.0.0-Belle-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync

# Or use Ventoy (recommended)
# Just copy the ISO to your Ventoy drive.
```

## License

See [LICENSE](LICENSE).
