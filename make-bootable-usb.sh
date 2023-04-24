#!/bin/bash

# TODO: Some error handling

set -e

# making sure the script runs from it's path
cd $(dirname $0)

# global
alpineMiniRootFsUrl="https://dl-cdn.alpinelinux.org/alpine/v3.17/releases/x86_64/alpine-minirootfs-3.17.3-x86_64.tar.gz"
mountPath=/media/alpineUsb

printGreen() {
	printf '\033[1;32m> %s\033[0m\n' "$@" >&2  # bold Green
}


printGreen "Pick a usb device:"
lsblk -dno name,size,type,mountpoint | awk '{print NR, ") ", $0}';

echo ""
read -p 'Device number: ' deviceNumber;

# TODO: validate device number, or check for sed error stream

chosenDevice=$(lsblk -dno name,size,type,mountpoint | sed -n ${deviceNumber}p | awk '{print "/dev/" $1}')

echo ""
printGreen "Are you sure you want to format the device ${chosenDevice}? (y/N)"
read -p "[n] : " isContinue
if [[ ! $isContinue = "y" ]];then
  exit 0
fi
if mount | grep -q "${chosenDevice}1"; then
  sudo umount "${chosenDevice}1"
fi
if mount | grep -q "${chosenDevice}2"; then
  sudo umount "${chosenDevice}2"
fi

# Preliminary commands
echo ""
printGreen "Partitioning the USB device"
sudo sgdisk --zap-all "$chosenDevice"
sudo parted "$chosenDevice" mklabel gpt
sudo parted "$chosenDevice" mkpart ESP fat32 0% 512MB
sudo parted "$chosenDevice" mkpart primary ext4 512MB 100%

# Set up main partition
sudo mkfs.ext4 "${chosenDevice}2"
echo ""
printGreen "Mounting the primary partition"
sudo mount "${chosenDevice}2" $mountPath
echo ""
printGreen "Installing alpine root file system on the primary partition"
# sudo curl -s --show-error $alpineMiniRootFsUrl | sudo tar -xvf -C $mountPath
sudo wget -q -O ./alpine-minirootfs.tar.gz $alpineMiniRootFsUrl 
sudo tar -xf ./alpine-minirootfs.tar.gz -C $mountPath > /dev/null

# Set up EFI partition
sudo mkfs.fat -F32 "${chosenDevice}1"
sudo mkdir $mountPath/efi
echo ""
printGreen "Mounting the the EFI partition"
sudo mount "${chosenDevice}1" $mountPath/efi
echo ""
printGreen "Installing GRUB bootloader for EFI"
sudo mkdir $mountPath/boot
sudo grub-install --target=x86_64-efi --efi-directory=$mountPath/efi --boot-directory=$mountPath/boot --removable
sudo grub-mkconfig -o $mountPath/boot/grub/grub.cfg

echo ""
printGreen "Fixing net in the installed alpine"
sudo touch $mountPath/etc/resolv.conf
sudo chmod 666 $mountPath/etc/resolv.conf
sudo echo "nameserver 8.8.8.8" > $mountPath/etc/resolv.conf
sudo chmod 644 $mountPath/etc/resolv.conf

echo ""
printGreen "Installing dependencies for the debian installation script"
sudo chroot $mountPath /bin/sh -c "apk add bash debootstrap lsblk parted sgdisk dosfstools"

echo ""
printGreen "Making the installation script run on boot"
sudo cp ./setup-debian.sh $mountPath/etc/init.d/setup-debian.sh
sudo chmod +x $mountPath/etc/init.d/setup-debian.sh

echo ""
printGreen "Cleanup"
if mount | grep -q "${chosenDevice}1"; then
  sudo umount "${chosenDevice}1"
fi
if mount | grep -q "${chosenDevice}2"; then
  sudo umount "${chosenDevice}2"
fi
sudo rm -rf $mountPath

# testing bootable usb
# sudo qemu-system-x86_64 -machine accel=kvm:tcg -m 512 -hda $chosenDevice
