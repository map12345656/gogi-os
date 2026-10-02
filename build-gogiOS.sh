#!/bin/bash
# gogiOS - Ubuntu 24.04 based distro with an iOS/macOS-like desktop.
# Run on an Ubuntu/Debian machine as root, ~25 GB free disk, internet needed.
# UNTESTED: written without the ability to boot the result.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run as root: sudo $0"; exit 1; }

NAME=gogiOS
W=/opt/build-$NAME
R=$W/rootfs
ISO=$W/iso
mkdir -p "$W" "$ISO"/{casper,boot/grub,EFI/boot}

apt-get update
apt-get install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools git

# 1. Base system
[ -d "$R/etc" ] || debootstrap --arch=amd64 noble "$R" http://archive.ubuntu.com/ubuntu

for d in dev proc sys; do mount --bind /$d "$R/$d"; done
cp /etc/resolv.conf "$R/etc/resolv.conf"
trap 'for d in dev proc sys; do umount -l "$R/$d" 2>/dev/null || true; done' EXIT

# 2. Install desktop + installer, apply iOS/macOS look
cat > "$R/setup.sh" <<'EOS'
set -e
export DEBIAN_FRONTEND=noninteractive
echo "gogiOS" > /etc/hostname
sed -i 's/ main$/ main universe multiverse/' /etc/apt/sources.list 2>/dev/null || true
cat > /etc/apt/sources.list <<L
deb http://archive.ubuntu.com/ubuntu noble main universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main universe multiverse
L
apt-get update
apt-get install -y linux-generic casper initramfs-tools grub-efi-amd64 \
  xfce4 xfce4-goodies lightdm lightdm-gtk-greeter plank network-manager-gnome \
  firefox calamares calamares-settings-ubuntu git sassc gtk2-engines-murrine \
  fonts-inter xdg-user-dirs sudo
# iOS/macOS-style theme (WhiteSur) + icons + cursors
cd /tmp
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-icon-theme.git
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-cursors.git
(cd WhiteSur-gtk-theme && ./install.sh -c Light -t default)
(cd WhiteSur-icon-theme && ./install.sh)
(cd WhiteSur-cursors && ./install.sh)
# Defaults for every new user
mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml /etc/skel/.config/autostart
cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml <<X
<?xml version="1.0"?>
<channel name="xsettings" version="1.0">
 <property name="Net"><property name="ThemeName" type="string" value="WhiteSur-Light"/>
  <property name="IconThemeName" type="string" value="WhiteSur"/></property>
 <property name="Gtk"><property name="CursorThemeName" type="string" value="WhiteSur-cursors"/>
  <property name="FontName" type="string" value="Inter 10"/></property>
</channel>
X
cat > /etc/skel/.config/autostart/plank.desktop <<P
[Desktop Entry]
Type=Application
Name=Dock
Exec=plank
P
# Live user
useradd -m -s /bin/bash -G sudo,adm live || true
echo "live:live" | chpasswd
echo "[Seat:*]
autologin-user=live" > /etc/lightdm/lightdm.conf.d/50-live.conf 2>/dev/null || {
 mkdir -p /etc/lightdm/lightdm.conf.d; echo "[Seat:*]
autologin-user=live" > /etc/lightdm/lightdm.conf.d/50-live.conf; }
apt-get clean
EOS
chroot "$R" bash /setup.sh
rm "$R/setup.sh"

# 3. Kernel, squashfs
cp "$R"/boot/vmlinuz-* "$ISO/casper/vmlinuz"
cp "$R"/boot/initrd.img-* "$ISO/casper/initrd"
for d in dev proc sys; do umount -l "$R/$d"; done
mksquashfs "$R" "$ISO/casper/filesystem.squashfs" -comp xz -e boot

# 4. Boot config + ISO
cat > "$ISO/boot/grub/grub.cfg" <<G
set timeout=5
menuentry "$NAME (live / install)" {
  linux /casper/vmlinuz boot=casper quiet splash ---
  initrd /casper/initrd
}
G
grub-mkrescue -o "$W/$NAME.iso" "$ISO" -V "$NAME"
echo "Ready: $W/$NAME.iso"
