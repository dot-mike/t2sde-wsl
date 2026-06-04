#!/bin/bash
# First-run user setup. Must exit 0 or WSL blocks the shell.
set -u

DEFAULT_UID=1000
getent passwd "$DEFAULT_UID" >/dev/null 2>&1 && exit 0

echo
echo "Welcome to T2/Linux on WSL."
echo "The base image has no sudo so a root password is required".
echo "This setup will guide you."
echo

ask() { read -rp "$1" "$2" </dev/tty; }

set_password() {
    local u="$1" n=0
    while [ "$n" -lt 3 ]; do
        passwd "$u" </dev/tty && return 0
        n=$((n + 1))
    done
    echo "(no password set for $u; run: passwd $u)"
}

username=""
attempts=0
while [ -z "$username" ]; do
    attempts=$((attempts + 1))
    if [ "$attempts" -gt 5 ]; then
        username="t2"
        echo "No input; creating default user '$username'."
    elif ! ask "Enter new UNIX username: " username; then
        username=""; continue
    fi
    [ -z "$username" ] && continue
    if ! printf '%s' "$username" | grep -Eq '^[a-z_][a-z0-9_-]*$'; then
        echo "lowercase start; letters, digits, '-' and '_' only."; username=""; continue
    fi
    if ! useradd --uid "$DEFAULT_UID" --user-group --create-home --shell /bin/bash "$username"; then
        echo "could not create '$username'."; username=""; continue
    fi
    set_password "$username"
done

if command -v sudo >/dev/null 2>&1; then
    getent group wheel >/dev/null 2>&1 || groupadd wheel
    usermod -aG wheel "$username" 2>/dev/null || true
    [ -e /etc/sudoers.d/wheel ] || { echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel; chmod 0440 /etc/sudoers.d/wheel; }
else
    echo "Set a root password:"
    set_password root
fi

if grep -q '^default=' /etc/wsl.conf 2>/dev/null; then
    sed -i "s/^default=.*/default=$username/" /etc/wsl.conf
else
    printf '\n[user]\ndefault=%s\n' "$username" >> /etc/wsl.conf
fi

BRC="/home/$username/.bashrc"
if [ -f "$BRC" ] && ! grep -q 'start in home' "$BRC"; then
    cat >> "$BRC" <<'EOF'

# start in home when launched from a Windows path
[ "${PWD#/mnt/}" != "$PWD" ] && cd "$HOME"
if [ -d /mnt/wslg/runtime-dir ]; then
    export XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir WAYLAND_DISPLAY=wayland-0 DISPLAY=:0
fi
EOF
fi

echo "User '$username' created. Root: 'su -'"
exit 0
