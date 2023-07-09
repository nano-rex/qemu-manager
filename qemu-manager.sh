#!/bin/bash

memory=4096

mkdir $HOME/Public

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
	qemu-system-x86_64 -enable-kvm $boot $cdrom -m $memory -cpu host -fsdev local,security_model=mapped,id=fsdev0,path=$HOME/Public -device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare 

elif [[ $1 == "--help" || $1 == "" ]]; then
	printf "Examples:\n"
	printf "$0 boot disk.qcow2 image.iso\n"
	printf "$0 boot /dev/sdb\n"
	printf "$0 boot create\n"
fi
