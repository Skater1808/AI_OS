#!/bin/bash
set -e

export ROOTFS=/build/rootfs
mkdir -p "$ROOTFS"

echo "Executing Debootstrap for Minimal Base Target System..."
debootstrap --variant=minbase noble "$ROOTFS" http://archive.ubuntu.com/ubuntu/

echo "Mounting Virtual Filesystems into Target Environment..."
# Diese Mounts sind absolut überlebenswichtig, damit apt-get Pakete wie Python und den Kernel konfigurieren kann!
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sys "$ROOTFS/sys"
mount --bind /dev "$ROOTFS/dev"
mount -t devpts devpts "$ROOTFS/dev/pts"

# Ein kleiner Trick, um dpkg-Fehler bezüglich fehlender Terminals/Schnittstellen abzufangen
export DEBIAN_FRONTEND=noninteractive

echo "Configuring Core Dependencies inside Target Environment..."
chroot "$ROOTFS" apt-get update
chroot "$ROOTFS" apt-get install -y --no-install-recommends systemd-sysv bubblewrap libgomp1 linux-image-virtual grub-pc-bin

echo "Compiling Rust System Daemon Engine..."
cd /build/core-daemon
cargo build --release

mkdir -p "$ROOTFS/usr/bin"
mkdir -p "$ROOTFS/etc/systemd/system"
mkdir -p "$ROOTFS/run/aios"

cp /build/core-daemon/target/release/aios-core-daemon "$ROOTFS/usr/bin/"

echo "Deploying Native Mojo AI Scripts..."
mkdir -p "$ROOTFS/opt/aios/ai-engine"
cp /build/ai-engine/engine.mojo "$ROOTFS/opt/aios/ai-engine/"

echo "Injecting Hardened Systemd Architecture Configurations..."
cp /build/config/aios-core.service "$ROOTFS/etc/systemd/system/"
chroot "$ROOTFS" systemctl enable aios-core.service

echo "Triggering Offline LLM Model Provisioning Pipeline..."
if [ -f /build/scripts/download_model.sh ]; then
    /bin/bash /build/scripts/download_model.sh "$ROOTFS/opt/aios/models/" || echo "Model pipeline skipped or warning handled."
fi

echo "Unmounting Virtual Filesystems before Squashing..."
# Extrem wichtig, da mksquashfs sonst die Live-Inhalte deines Host-Systems mit in die ISO packt!
umount -lf "$ROOTFS/proc" || true
umount -lf "$ROOTFS/sys" || true
umount -lf "$ROOTFS/dev/pts" || true
umount -lf "$ROOTFS/dev" || true

echo "Assembling ISO Distribution Framework..."
mkdir -p /build/iso/boot/grub
mkdir -p /build/iso/casper

cp /build/config/grub.cfg /build/iso/boot/grub/

mksquashfs "$ROOTFS" /build/iso/casper/filesystem.squashfs -comp xz -e boot

# Da wir linux-image-virtual nutzen, müssen wir den genauen Namen dynamisch auslesen
KERNEL_IMG=$(ls -1 $ROOTFS/boot/vmlinuz-* | head -n 1)
INITRD_IMG=$(ls -1 $ROOTFS/boot/initrd.img-* | head -n 1)

if [ -z "$KERNEL_IMG" ] || [ -z "$INITRD_IMG" ]; then
    echo "CRITICAL ERROR: Kernel image or initrd not found in rootfs/boot!"
    exit 1
fi

cp "$KERNEL_IMG" /build/iso/boot/vmlinuz
cp "$INITRD_IMG" /build/iso/boot/initrd

grub-mkrescue -o /build/aios.iso /build/iso

echo "AiOS Distribution Assembly Complete: /build/aios.iso"