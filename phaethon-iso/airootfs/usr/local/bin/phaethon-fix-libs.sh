#!/usr/bin/env bash
# ==============================================================================
# PHAETHON OS - RESOLVE CALAMARES SHARED LIBRARY SKEW
# ==============================================================================
# cachyos-calamares is built against particular boost/yaml-cpp releases, and the
# repos move faster than the package gets rebuilt. On the v1.0.0-Belle ISO:
#
#   cachyos-calamares 3.4.2-4   wants   libboost_python314.so.1.91.0
#   boost-libs        1.92.0-1  ships   libboost_python314.so.1.92.0
#   python            3.14.7-1
#
# Same Python ABI, newer boost. Calamares then dies at exec with
# "error while loading shared libraries: ... cannot open shared object file".
#
# WHAT IS SAFE TO BRIDGE
# A boost-python soname encodes two things: libboost_python<PYABI>.so.<BOOSTVER>
# Only the BOOSTVER half may differ. Boost keeps its C++ ABI stable across minor
# releases, and both libraries link the same libpython, so the symlink holds.
# Bridging the PYABI half (python313 -> python314) is NOT safe: such a library
# links a libpython this system does not have, and would fail or crash inside
# Calamares' Python job modules -- which is most of them (bootloader, grubcfg,
# initcpiocfg all run through boost::python). This script therefore only ever
# links libraries whose soname base matches exactly.
#
# WHY THIS RUNS AS ROOT, AT BOOT
# This logic previously lived inline in phaethon-calamares, which runs as the
# unprivileged live user until it elevates at the very end. Its `ln -sf` into
# /usr/lib got EACCES, `2>/dev/null` swallowed the error and `&&` skipped the
# success log -- so the repair silently did nothing, every time, and the only
# visible symptom was Calamares still failing to start. It belongs here, in the
# root oneshot, with phaethon-calamares calling it via sudo as a fallback.
#
set -o pipefail

LOG_TAG="phaethon-fix-libs"
log()  { echo "[$LOG_TAG] $*" >&2; }
warn() { echo "[$LOG_TAG] WARNING: $*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
    echo "[$LOG_TAG] must run as root" >&2
    exit 1
fi

CALAMARES_BIN="$(command -v calamares 2>/dev/null || echo /usr/bin/calamares)"

# Link a compatible sibling into place for one missing soname.
# Returns 0 only if the library is present afterwards.
bridge_soname() {
    local want="$1" base found

    [ -e "/usr/lib/$want" ] && return 0

    # Everything before ".so." -- for libboost_python314.so.1.91.0 that is
    # "libboost_python314", which pins the Python ABI. Only siblings sharing
    # this exact base are candidates.
    base="${want%%.so.*}"
    case "$want" in
        *.so.*) ;;
        *) return 1 ;;   # not a versioned soname, nothing to bridge to
    esac

    found=$(find /usr/lib -maxdepth 1 -name "${base}.so.*" -printf '%f\n' 2>/dev/null |
            grep -v '\.a$' | sort -V | tail -1)

    if [ -z "$found" ] || [ "$found" = "$want" ]; then
        warn "no compatible build of ${base} present; cannot resolve $want"
        return 1
    fi

    if ln -sf "$found" "/usr/lib/$want"; then
        log "bridged $want -> $found"
        return 0
    fi
    warn "failed to link $want -> $found"
    return 1
}

# Collect every unresolved soname across the binary and its modules in one pass.
collect_missing() {
    {
        ldd "$CALAMARES_BIN" 2>/dev/null
        for mod in /usr/lib/calamares/modules/*/libcalamares*.so; do
            [ -e "$mod" ] && ldd "$mod" 2>/dev/null
        done
    } | awk '/not found/ {print $1}' | sort -u
}

if [ ! -x "$CALAMARES_BIN" ]; then
    log "Calamares not installed, nothing to do"
    exit 0
fi

changed=0
missing=$(collect_missing)

if [ -z "$missing" ]; then
    log "all Calamares libraries resolve"
    exit 0
fi

log "unresolved libraries: $(echo "$missing" | tr '\n' ' ')"
for lib in $missing; do
    bridge_soname "$lib" && changed=1
done

[ "$changed" -eq 1 ] && ldconfig 2>/dev/null

# Report the outcome honestly rather than exiting 0 regardless.
still=$(collect_missing)
if [ -n "$still" ]; then
    warn "still unresolved after repair: $(echo "$still" | tr '\n' ' ')"
    exit 1
fi

log "all Calamares libraries resolve"
