# AI_OS — Intelligent Operating System

An experimental Linux-based operating system combining AI/ML inference capabilities with a lightweight live-boot environment.

## Overview

**AI_OS** is a specialized Linux distribution built with:
- **Live-Boot System**: GRUB2 bootloader with casper/live-boot for in-memory execution
- **Rust Core Daemon** (`aios-core-daemon`): System service for AI workload orchestration
- **Mojo AI Engine**: LLM inference engine with model management
- **Minimal Ubuntu Noble Base**: Debootstrap-derived rootfs with essential tooling

## Project Structure

```
AI_OS/
├── ai-engine/           # Mojo LLM inference engine
│   └── engine.mojo
├── core-daemon/         # Rust system daemon
│   ├── Cargo.toml
│   ├── src/
│   │   ├── main.rs
│   │   ├── policy.rs
│   │   └── rpc.rs
│   └── target/          # Build artifacts
├── config/              # System configuration
│   ├── aios-core.service   # systemd unit
│   └── grub.cfg        # Boot configuration
├── scripts/            # Build and utility scripts
│   └── download_model.sh   # LLM model provisioning
├── build.sh            # Main build script
├── Dockerfile          # Container build support
└── build/              # Build outputs
    ├── aios.iso        # Live-boot ISO image
    ├── rootfs/         # Chroot filesystem
    └── iso/            # ISO staging directory
```

## Building

### Quick Start

```bash
cd /workspaces/AI_OS
sudo bash build.sh
```

The build process:
1. **Debootstrap** — Creates minimal Ubuntu Noble rootfs
2. **Kernel & Dependencies** — Installs Linux kernel, casper, initramfs-tools
3. **Rust Daemon** — Compiles `aios-core-daemon` (if available)
4. **AI Engine** — Deploys Mojo engine and model scripts
5. **SquashFS** — Compresses rootfs for live-boot
6. **ISO Creation** — Generates hybrid BIOS/UEFI bootable image

### Prerequisites

- Root/sudo access
- Linux host (tested on Ubuntu 22.04+)
- ~5-10GB free disk space
- Tools: `debootstrap`, `squashfs-tools`, `xorriso`, `grub-pc-bin`, `grub-efi-amd64-bin`

Most dependencies are auto-installed by `build.sh`.

### Output

- **`build/aios.iso`** — Live-boot ISO image (hybrid BIOS/UEFI)
  - Boot with: `qemu-system-x86_64 -cdrom build/aios.iso` or burn to USB

## Features

- **Live-Boot**: Runs entirely from RAM after boot, no installation needed
- **Casper Integration**: Ubuntu-standard live-boot stack for compatibility
- **AI/ML Ready**: Pre-configured daemon and model pipeline
- **Lightweight**: Minimal base system optimized for inference workloads
- **Hybrid UEFI/BIOS**: Boots on modern and legacy hardware

## Testing

### Virtual Machine

```bash
# QEMU
qemu-system-x86_64 -cdrom build/aios.iso -m 2G

# KVM (faster)
qemu-system-x86_64 -enable-kvm -cdrom build/aios.iso -m 2G
```

### USB Boot

```bash
sudo dd if=build/aios.iso of=/dev/sdX bs=4M conv=fsync
# Replace /dev/sdX with your USB device (e.g., /dev/sdb)
```

## Development

### Modifying the Rootfs

Edit `build.sh` to:
- Change base distribution: modify `debootstrap ... noble` variant
- Add packages: add to `chroot ... apt-get install` section
- Deploy custom files: copy to `$ROOTFS` paths

### Rebuilding Core Daemon

```bash
cd core-daemon
cargo build --release
# Binary at: target/release/aios-core-daemon
```

### Model Management

Scripts in `scripts/download_model.sh` manage LLM model provisioning.
Models deployed to `/opt/aios/models/` in the ISO.

## Troubleshooting

### Kernel Panic on Boot

- **Issue**: Unknown block device, mount_root failure
- **Fix**: Ensure `initramfs-tools` and `casper` are installed in rootfs
  - `build.sh` auto-generates initramfs; verify with: `cpio -it < build/iso/boot/initrd`
- **Verify**: Check GRUB boot parameters match `boot=casper` in `config/grub.cfg`

### Build Fails (noexec filesystem)

- **Issue**: `debootstrap` fails in workspace with noexec mount
- **Fix**: `build.sh` auto-detects and uses `/tmp` for build
  - Manually: `export ROOTFS=/tmp/aios-rootfs && bash build.sh`

### ISO Won't Boot

1. Verify ISO is written correctly: `md5sum build/aios.iso`
2. Ensure VM/machine has ≥512MB RAM
3. Test boot in QEMU first
4. Check GRUB menu for boot options

## Architecture

```
BIOS/UEFI → GRUB Bootloader
           ↓
         Kernel (6.8.0-31-generic)
           ↓
         Initramfs (casper hooks)
           ↓
         Casper Detection (boot=casper)
           ↓
         Mount Squashfs (filesystem.squashfs)
           ↓
         Live Root Environment
           ↓
         aios-core-daemon (systemd)
```

## Contributing

This is an experimental project. Contributions welcome via:
- Bug reports and fixes
- Performance improvements
- Model/engine enhancements
- Documentation

## License

[Specify your license here, e.g., MIT, Apache 2.0, GPL 3.0]

## References

- [Ubuntu Live Build Documentation](https://live-team.pages.debian.net/live-manual/html/live-manual/)
- [Casper Live-Boot Stack](https://manpages.ubuntu.com/manpages/noble/man7/casper.7.html)
- [GRUB Bootloader Docs](https://www.gnu.org/software/grub/manual/)
- [Mojo Programming Language](https://docs.modular.com/mojo/)
