#!/usr/bin/env bash
set -e

# Apply Phaethon color scheme
plasma-apply-colorscheme PhaethonDark 2>/dev/null || true

# Apply wallpaper
plasma-apply-wallpaperimage /usr/share/wallpapers/phaethon/wallpaper-phaethon.jpeg 2>/dev/null || true


# Disable blur and shadows via kwriteconfig6, set animation speed to 1 (snappy open/close)
kwriteconfig6 --file kwinrc --group Compositing --key AnimationSpeed 1 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Compositing --key Backend OpenGL 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Compositing --key Enabled true 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Decorations --key BorderRadius 0 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Decorations --key Shadows false 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Windows --key BorderRadius 0 2>/dev/null || true
