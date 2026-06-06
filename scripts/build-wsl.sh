#!/usr/bin/env bash
# Build a T2/Linux .wsl image from a T2 ISO.
# Run on Linux as root (or with sudo). Needs squashfs-tools, tar, gzip.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISTRO_DIR="$REPO_DIR/distro"

NAME="t2sde"
ISO="" ; OUTPUT="" ; WORKOPT=""
ROOT_ONLY=0 ; KEEP_WORK=0

die()  { echo "error: $*" >&2; exit 1; }
info() { echo ">> $*"; }
usage() {
cat <<'USAGE'
build-wsl.sh --iso FILE [options]   build a T2/Linux .wsl image

  --iso FILE      T2 ISO (required)
  --output FILE   output path        (default out/<name>.wsl)
  --name NAME     distro name        (default t2sde)
  --work DIR      scratch dir        (default /tmp on /mnt/*)
  --root-only     default user root, no OOBE
  --keep-work     keep the scratch dir
USAGE
exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --iso)        ISO="${2:?}"; shift 2 ;;
        --output)     OUTPUT="${2:?}"; shift 2 ;;
        --name)       NAME="${2:?}"; shift 2 ;;
        --work)       WORKOPT="${2:?}"; shift 2 ;;
        --root-only)  ROOT_ONLY=1; shift ;;
        --keep-work)  KEEP_WORK=1; shift ;;
        -h|--help)    usage 0 ;;
        *) die "unknown argument: $1 (--help)" ;;
    esac
done

[ -n "$ISO" ] || die "need --iso FILE"
[ -f "$ISO" ] || die "no such ISO: $ISO"

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else
    command -v sudo >/dev/null 2>&1 || die "not root and no sudo"
    SUDO="sudo"
fi
as_root() { $SUDO "$@"; }

for c in unsquashfs tar gzip; do command -v "$c" >/dev/null 2>&1 || die "$c not found"; done

# drvfs/9p (/mnt/c) can't hold Linux ownership -> corrupt tar; use a real fs.
if [ -n "$WORKOPT" ]; then WORK="$WORKOPT"
else case "$REPO_DIR" in
        /mnt/*) WORK="${TMPDIR:-/tmp}/t2sde-wsl.work" ;;
        *)      WORK="$REPO_DIR/work" ;;
     esac
fi
ROOTFS="$WORK/rootfs"
case "$WORK" in ""|/|/mnt|/usr|/etc|/var|/home|"$HOME") die "refusing unsafe --work: $WORK" ;; esac
info "work dir: $WORK"

as_root rm -rf "$WORK"
as_root mkdir -p "$WORK"
as_root chown "$(id -u):$(id -g)" "$WORK"

SQF="$WORK/rootfs.sqf"
info "extracting rootfs.sqf from ISO"
command -v bsdtar >/dev/null 2>&1 && bsdtar -xOf "$ISO" rootfs.sqf > "$SQF" || true
if [ ! -s "$SQF" ]; then
    mp="$(mktemp -d)"
    as_root mount -o loop,ro "$ISO" "$mp"
    as_root cp "$mp/rootfs.sqf" "$SQF"
    as_root umount "$mp"; rmdir "$mp"
fi
[ -s "$SQF" ] || die "could not extract rootfs.sqf from $ISO"

info "extracting squashfs"
as_root unsquashfs -q -d "$ROOTFS" "$SQF" >/dev/null
[ -d "$ROOTFS/etc" ] || die "rootfs has no /etc"

info "sanitising rootfs"
as_root rm -f  "$ROOTFS/etc/resolv.conf" "$ROOTFS/etc/hostname" "$ROOTFS/etc/machine-id"
as_root rm -rf "$ROOTFS/boot" "$ROOTFS/lib/modules" "$ROOTFS/lib/firmware"
grep -q "^root:.*:0:0:" "$ROOTFS/etc/passwd" || die "no uid 0 root in /etc/passwd"

for s in "$ROOTFS"/etc/postinstall.d/*; do
    [ -e "$s" ] || continue
    info "postinstall: ${s##*/}"
    as_root chroot "$ROOTFS" /bin/sh "/etc/postinstall.d/${s##*/}" || true
done

info "installing WSL configuration"
as_root install -d -m 0755 "$ROOTFS/usr/lib/wsl"
as_root install -m 0644 "$DISTRO_DIR/wsl.conf"              "$ROOTFS/etc/wsl.conf"
as_root install -m 0644 "$DISTRO_DIR/terminal-profile.json" "$ROOTFS/usr/lib/wsl/terminal-profile.json"

ICON_LINE=""
if [ -f "$REPO_DIR/assets/t2.ico" ]; then
    as_root install -m 0644 "$REPO_DIR/assets/t2.ico" "$ROOTFS/usr/lib/wsl/$NAME.ico"
    ICON_LINE="icon = /usr/lib/wsl/$NAME.ico"
fi

if [ "$ROOT_ONLY" -eq 1 ]; then
    as_root tee "$ROOTFS/etc/wsl-distribution.conf" >/dev/null <<EOF
[oobe]
defaultName = $NAME

[shortcut]
enabled = true
$ICON_LINE

[windowsterminal]
enabled = true
profileTemplate = /usr/lib/wsl/terminal-profile.json
EOF
else
    as_root install -m 0755 "$DISTRO_DIR/oobe.sh" "$ROOTFS/usr/lib/wsl/oobe.sh"
    as_root tee "$ROOTFS/etc/wsl-distribution.conf" >/dev/null <<EOF
[oobe]
command = /usr/lib/wsl/oobe.sh
defaultUid = 1000
defaultName = $NAME

[shortcut]
enabled = true
$ICON_LINE

[windowsterminal]
enabled = true
profileTemplate = /usr/lib/wsl/terminal-profile.json
EOF
fi
as_root chmod 0644 "$ROOTFS/etc/wsl-distribution.conf"

# T2 hardcode PATH
info "patching /etc/profile"
as_root sed -i \
    -e '1i __wslpath="$PATH"' \
    -e 's#^export PATH$#[ -n "$WSL_DISTRO_NAME" ] \&\& PATH="$PATH:$__wslpath"\nexport PATH#' \
    "$ROOTFS/etc/profile"

OUT="${OUTPUT:-$REPO_DIR/out/$NAME.wsl}"
mkdir -p "$(dirname "$OUT")"
info "packing $OUT"
as_root tar --numeric-owner --exclude-from="$DISTRO_DIR/tar-exclude.txt" -C "$ROOTFS" -c . | gzip --best > "$OUT"
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" ) > "$OUT.sha256"

[ "$KEEP_WORK" -eq 1 ] || as_root rm -rf "$WORK"

info "built $OUT ($(du -h "$OUT" | cut -f1))"
WINOUT="$(wslpath -w "$OUT" 2>/dev/null || echo "$OUT")"
echo "install via Powershell: wsl --install --from-file \"$WINOUT\""
