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
# WHAT IS SAFE TO BRIDGE -- AND WHY A NAME MATCH IS NOT ENOUGH
# A boost-python soname encodes two things: libboost_python<PYABI>.so.<BOOSTVER>
# Bridging the PYABI half (python313 -> python314) is never safe: such a library
# links a libpython this system does not have.
#
# Matching the PYABI half is necessary but NOT sufficient. Bridging 1.91.0 to
# 1.92.0 satisfies the loader's search -- `ldd` reports every library found --
# and then fails at first use:
#
#   /usr/bin/calamares: symbol lookup error: /usr/lib/libcalamares.so.3.4:
#   undefined symbol: _ZN5boost6python6detail11init_moduleER11PyModuleDefPFvvE
#     -> boost::python::detail::init_module(PyModuleDef&, void (*)())
#
# Boost 1.92 dropped that overload, so the bridged library loads but does not
# export what libcalamares was linked against. Boost does not promise C++ ABI
# stability across releases and this is what that looks like in practice.
#
# So every bridge is verified with `ldd -r`, which performs the same relocations
# the loader will and reports undefined symbols rather than just missing files.
# A bridge that does not survive that check is undone, not shipped -- a clear
# "cannot start" beats a symbol lookup error after the window fails to appear.
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
        log "bridged $want -> $found (provisional, pending symbol check)"
        record_bridge "/usr/lib/$want"
        return 0
    fi
    warn "failed to link $want -> $found"
    return 1
}

# Relocation-level check. `ldd` alone only proves each soname resolves to a
# file; `ldd -r` additionally binds every symbol, which is what actually catches
# a same-name-different-ABI bridge.
unresolved_symbols() {
    ldd -r "$CALAMARES_BIN" 2>&1 | grep -E 'undefined symbol|not found'
}

# Bridges are recorded in /run so a later invocation can undo one made earlier
# in the same boot: the boot service bridges first, then phaethon-calamares
# re-runs this script and must be able to revert what the service did.
#
# Only links listed here are ever removed. Guessing from the filesystem is not
# safe -- plenty of packages legitimately ship a versioned symlink pointing at
# another versioned name (libcurl.so.4 -> libcurl.so.4.8.0), and those are
# indistinguishable from ours by shape alone.
STATE=/run/phaethon-fix-libs.bridges

record_bridge() { echo "$1" >>"$STATE"; }

undo_bridges() {
    local link
    [ -f "$STATE" ] || return 0
    while read -r link; do
        [ -L "$link" ] && rm -f "$link" && log "reverted unsound bridge ${link##*/}"
    done <"$STATE"
    rm -f "$STATE"
    ldconfig 2>/dev/null
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

# NOTE: no early exit when nothing is missing. A bridge made earlier this boot
# makes "every file resolves" trivially true while the symbols behind it are
# still wrong -- which is exactly how a bad bridge reached a user as
# "all Calamares libraries resolve" immediately followed by a symbol lookup
# error. The symbol check below runs unconditionally.
if [ -n "$missing" ]; then
    log "unresolved libraries: $(echo "$missing" | tr '\n' ' ')"
    for lib in $missing; do
        bridge_soname "$lib" && changed=1
    done
    [ "$changed" -eq 1 ] && ldconfig 2>/dev/null

    still=$(collect_missing)
    if [ -n "$still" ]; then
        warn "still unresolved after repair: $(echo "$still" | tr '\n' ' ')"
        exit 1
    fi
fi

# Every file resolves -- now prove the symbols do too.
syms=$(unresolved_symbols)
if [ -n "$syms" ]; then
    warn "libraries resolve by name but not by symbol:"
    printf '%s\n' "$syms" | while read -r line; do
        warn "  $line"
        sym=${line##*symbol: }; sym=${sym%%[[:space:]]*}
        if [ -n "$sym" ] && command -v c++filt >/dev/null 2>&1; then
            warn "    -> $(echo "$sym" | c++filt)"
        fi
    done
    warn "the installed build does not export what Calamares was linked against;"
    warn "this needs a matching package, not a symlink."
    undo_bridges
    exit 1
fi

log "all Calamares libraries and symbols resolve"
