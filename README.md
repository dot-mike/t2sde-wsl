# t2sde-wsl

Build a [T2/Linux](https://t2sde.org/) image for **WSL2** from an
official T2 ISO. Output is a `.wsl` file you install with `wsl --install`

## Build

Download the base build for T2 Linux from https://dl.t2sde.org/binary/2026/incoming/t2-26.6-x86-64-base-wayland-bootstrap-gcc-nocona.iso

From a WSL distro with `squashfs-tools` installed run the following:

```bash
cd t2sde-wsl
sudo ./scripts/build-wsl.sh --iso /path/to/t2-26.6-x86-64-base-wayland-bootstrap-gcc-nocona.iso
```

Or from PowerShell directly

```powershell
cd t2sde-wsl
wsl -d Ubuntu -e bash -lc "sudo ./scripts/build-wsl.sh --iso /path/to/t2-26.6-x86-64-base-wayland-bootstrap-gcc-nocona.iso"
```

Output will be in `out/t2sde.wsl`

## Usage

Install

```powershell
wsl --install --from-file .\out\t2sde.wsl
```

Follow OOBE setup guide. It will prompt username, password and root password (no sudo added).

Removal

```powershell
wsl --unregister t2sde
```

## WSL compatibility fixes

T2's rootfs is not designed for WSL, so the build applies a few compatibility changes:

- **devpts/ptmx** (`wsl.conf`) - remounts `/dev/pts` so `ptmx` can be opened correctly. Without this, `forkpty()` returns `ENODEV`.
- **Cleanup** - removes `boot`, `lib/modules`, and `lib/firmware` since WSL uses the host kernel.
- **Format conversion** - converts the ISO's rootfs.sqf (SquashFS) to the gzip-tar for WSL installation.
- **First-run setup** (`oobe.sh`) - creates a user account, configures passwords, enables `wheel`-based sudo where available, and sets the environment required for WSLg/Wayland applications.