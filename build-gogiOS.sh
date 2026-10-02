#!/bin/bash
# gogiOS - Ubuntu 24.04 based distro with an iOS/macOS-like desktop.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run as root: sudo $0"; exit 1; }

NAME=gogiOS
W=/opt/build-$NAME
R=$W/rootfs
ISO=$W/iso
rm -rf "$W"
mkdir -p "$W" "$ISO"/casper "$ISO"/boot/grub

apt-get update
apt-get install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools git

# 1. Base system
debootstrap --arch=amd64 noble "$R" http://archive.ubuntu.com/ubuntu

cleanup() { for d in dev/pts dev proc sys; do umount -l "$R/$d" 2>/dev/null || true; done; }
trap cleanup EXIT
for d in dev proc sys; do mount --bind /$d "$R/$d"; done
cp /etc/resolv.conf "$R/etc/resolv.conf"

# 2. Chroot setup script
cat > "$R/setup.sh" <<'EOS'
set -ex
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
echo "gogiOS" > /etc/hostname
# stop services from starting inside the chroot
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

cat > /etc/apt/sources.list <<L
deb http://archive.ubuntu.com/ubuntu noble main universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main universe multiverse
L
rm -f /etc/apt/sources.list.d/ubuntu.sources
apt-get update

# core system (casper first so initramfs gets live-boot support)
apt-get install -y casper initramfs-tools
apt-get install -y linux-generic
apt-get install -y grub-common grub-pc-bin grub-efi-amd64-bin sudo \
  network-manager

# desktop
apt-get install -y xfce4 lightdm lightdm-gtk-greeter plank \
  network-manager-gnome epiphany-browser fonts-inter xdg-user-dirs \
  git sassc gtk2-engines-murrine libglib2.0-dev-bin libgtk-3-bin \
  xfce4-terminal thunar

# installer (best effort)
apt-get install -y calamares || true
apt-get install -y calamares-settings-debian || true

# iOS/macOS-style theme
cd /tmp
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-icon-theme.git
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-cursors.git
(cd WhiteSur-gtk-theme && ./install.sh -c Light) || true
(cd WhiteSur-icon-theme && ./install.sh) || true
(cd WhiteSur-cursors && ./install.sh) || true

mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml /etc/skel/.config/autostart
cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml <<X
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="WhiteSur-Light"/>
    <property name="IconThemeName" type="string" value="WhiteSur"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="CursorThemeName" type="string" value="WhiteSur-cursors"/>
    <property name="FontName" type="string" value="Inter 10"/>
  </property>
</channel>
X
cat > /etc/skel/.config/autostart/plank.desktop <<P
[Desktop Entry]
Type=Application
Name=Dock
Exec=plank
P

# live user
useradd -m -s /bin/bash -G sudo,adm live
echo "live:live" | chpasswd
mkdir -p /etc/lightdm/lightdm.conf.d
printf '[Seat:*]\nautologin-user=live\nuser-session=xfce\n' > /etc/lightdm/lightdm.conf.d/50-live.conf

update-initramfs -u
apt-get clean
rm -rf /tmp/* /var/lib/apt/lists/* /usr/sbin/policy-rc.d
EOS
chroot "$R" bash /setup.sh
rm "$R/setup.sh"

# 3. Kernel + squashfs
cp "$R"/boot/vmlinuz-* "$ISO/casper/vmlinuz"
cp "$R"/boot/initrd.img-* "$ISO/casper/initrd"
cleanup
mksquashfs "$R" "$ISO/casper/filesystem.squashfs" -comp xz -noappend

# 4. Boot config + ISO
cat > "$ISO/boot/grub/grub.cfg" <<G
set timeout=5
menuentry "$NAME (live / install)" {
  linux /casper/vmlinuz boot=casper quiet splash ---
  initrd /casper/initrd
}
G
grub-mkrescue -o "$W/$NAME.iso" "$ISO" -- -volid "$NAME"
ls -lh "$W/$NAME.iso"
echo "Ready: $W/$NAME.iso"
