#!/bin/bash
# Fix library symlinks for Calamares at boot time
if [ ! -L /usr/lib/libyaml-cpp.so.0.8 ] && [ -f /usr/lib/libyaml-cpp.so.0.9 ]; then
    ln -sf libyaml-cpp.so.0.9 /usr/lib/libyaml-cpp.so.0.8
    ldconfig
fi
