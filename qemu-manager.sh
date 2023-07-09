#!/bin/bash

memory=4096

if [[ $1 == "create" ]]; then
	read -p "Name of virtual disk: " disk
	read -p "Size of virtual disk (GB): " size
	qemu-img create -f qcow2 ${disk}.qcow2 ${size}G
elif [[ $1 == "boot" ]]; then
	if [[ $2 == *.qcow2 ]]; then
		boot="-hda $2" #Eg: disk.qcow2
	elif [[ $2 == \/dev\/* ]]; then
		boot="-drive format=raw,file=$2" #Eg: /dev/sdb
	else
		boot=""
	fi
	if [[ $3 == *.iso ]]; then
		cdrom="-boot d -cdrom $3" #Eg: image.iso
	#elif [[ $3 == * ]]; then
	#	cdrom="-drive format=raw,media=cdrom,readonly,file=debian-8.2.0-amd64-DVD-1.iso"
	else
		cdrom=""
	fi
	qemu-system-x86_64 -enable-kvm $boot $cdrom -m $memory -cpu host -fsdev local,security_model=mapped,id=fsdev0,path=Public -device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare 
 #-netdev user,id=net0,hostfwd=tcp::8080-:80 \
 #-device virtio-net-pci,netdev=net0
	#qemu-system-x86_64 -enable-kvm -nographic $boot $cdrom -m 1024 -cpu host -fsdev local,security_model=mapped,id=fsdev0,path=Public -device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare 
	#-network bridge,source=virbr0,model=virtio
	#-netdev user,id=net0,hostfwd=tcp::22-:22 -device virtio-net-pci,netdev=net0,mac=<MAC_ADDRESS>
	#-netdev user,id=net0,net=<NETWORK_ADDRESS>/<NETMASK>,dhcpstart=<DHCP_START_ADDRESS>,dhcpend=<DHCP_END_ADDRESS> -device virtio-net-pci,netdev=net0,mac=<MAC_ADDRESS>
	#-netdev user,id=net0,net=192.168.122.0/24,dhcpstart=192.168.122.2,dhcpend=192.168.122.254 -device virtio-net-pci,netdev=net0,mac=52:54:00:ab:cd:ef

elif [[ $1 == "--help" || $1 == "" ]]; then
	printf "Examples:\n"
	printf "$0 boot disk.qcow2 image.iso\n"
	printf "$0 boot /dev/sdb\n"
	printf "$0 boot create\n"
fi

# Reference
# https://gist.github.com/bingzhangdai/7cf8880c91d3e93f21e89f96ff67b24b
# https://www.linux-kvm.org/page/9p_virtio
# https://wiki.qemu.org/Documentation/9psetup
# https://qemu-project.gitlab.io/qemu/system/devices/usb.html

