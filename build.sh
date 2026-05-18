#!/bin/bash
set -e

export ROOTFS=/build/rootfs
mkdir -p "$ROOTFS"

echo "Executing Debootstrap for Minimal Base Target System..."
debootstrap --variant=minbase noble "$ROOTFS" http://archive.ubuntu.com/ubuntu/

echo "Configuring Core Dependencies inside Target Environment..."
# 1. Wir mounten /dev und /proc, damit grub und der Kernel-Hook keine Warnungen/Fehler werfen
mount -t proc proc "$ROOTFS/proc" || true
mount -t sysfs sys "$ROOTFS/sys" || true
mount --bind /dev "$ROOTFS/dev" || true

chroot "$ROOTFS" apt-get update

# 2. CI-RETTUNG: Wir installieren den virtuellen Kernel OHNE die riesige linux-firmware!
# --no-install-recommends verhindert das Laden von Desktop-WLAN-/Grafiktreibern.
# linux-image-virtual reicht für VMs und Server vollkommen aus und spart 1.5 GB Speicherplatz.
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
    systemd-sysv \
    bubblewrap \
    libgomp1 \
    linux-image-virtual \
    grub-pc-bin

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
# Das wird über die GitHub-Workflow-Anpassung übersprungen oder nutzt dein Dummy-Modell
/bin/bash /build/scripts/download_model.sh "$ROOTFS/opt/aios/models/" || echo "Modell-Download übersprungen (CI-Mode)"

echo "Assembling ISO Distribution Framework..."
mkdir -p /build/iso/boot/grub
mkdir -p /build/iso/casper

cp /build/config/grub.cfg /build/iso/boot/grub/

# Aufräumen der Mounts vor dem Packen des Dateisystems
umount "$ROOTFS/proc" || true
umount "$ROOTFS/sys" || true
umount "$ROOTFS/dev" || true

mksquashfs "$ROOTFS" /build/iso/casper/filesystem.squashfs -comp xz -e boot

# Dynamische Ermittlung von Kernel und Initrd (funktioniert jetzt auch mit -virtual)
KERNEL_IMG=$(ls -1 $ROOTFS/boot/vmlinuz-* | head -n 1)
INITRD_IMG=$(ls -1 $ROOTFS/boot/initrd.img-* | head -n 1)

if [ -z "$KERNEL_IMG" ] || [ -z "$INITRD_IMG" ]; then
    echo "ERROR: Kernel oder Initrd wurde im chroot nicht gefunden!"
    exit 1
fi

cp "$KERNEL_IMG" /build/iso/boot/vmlinuz
cp "$INITRD_IMG" /build/iso/boot/initrd

grub-mkrescue -o /build/aios.iso /build/iso

echo "AiOS Distribution Assembly Complete: /build/aios.iso"