#!/bin/bash
# qemu-devices: list the host's PCI and USB devices and how to attach them to a VM
# with qemu-manager (-pci ADDR / -usb ID).

sys="/sys"  # sysfs root

usage() {
  printf "Usage: %s [pci|usb]\n\n" "$0"
  printf "Lists host devices that can be attached to a VM, with the qemu-manager flag to use.\n"
  printf "  pci    PCI devices only (attach with: sudo qemu-manager boot ... -pci ADDR)\n"
  printf "  usb    USB devices only (attach with: sudo qemu-manager boot ... -usb ID)\n"
  printf "With no argument, both are listed.\n"
}

# Short PCI address (0000:00:14.3 -> 00:14.3)
short_addr() {
  echo "${1#0000:}"
}

# Human-readable PCI device name, from lspci when available
pci_name() {
  local addr="$1" dev="$sys/bus/pci/devices/$1"
  if command -v lspci > /dev/null; then
    lspci -s "$addr" | cut -d' ' -f2-
  else
    printf "class %s [%s:%s]" "$(cat "$dev/class")" "$(cat "$dev/vendor")" "$(cat "$dev/device")"
  fi
}

# PCI addresses of the disks holding the root filesystem (e.g. the NVMe controller)
root_disk_paths() {
  local src disk
  src=$(findmnt -no SOURCE / 2>/dev/null) || return
  lsblk -nrso NAME,TYPE "$src" 2>/dev/null | while read -r disk type; do
    [[ $type == disk ]] && readlink -f "$sys/block/$disk"
  done
}

# Why a PCI device must never be detached from the host (empty if it may be)
pci_blocker() {
  local addr="$1" dev="$sys/bus/pci/devices/$1" class
  class=$(cat "$dev/class")
  if [[ $class == 0x06* ]]; then
    echo "bridge"
  elif [[ $(cat "$dev/boot_vga" 2>/dev/null) == 1 ]]; then
    echo "host display"
  elif grep -q "/$addr/" <<< "$root_disks"; then
    echo "host system disk"
  fi
}

# Why a PCI device can't be attached: a hard blocker, or a platform device a VM has no use
# for (SPI flash, I2C, SMBus, thermal...). Attachable: storage, network, display, audio,
# USB controllers, SD readers, wireless/Bluetooth, accelerators.
pci_unattachable() {
  local blocker
  blocker=$(pci_blocker "$1")
  if [[ -n $blocker ]]; then
    echo "$blocker"
    return
  fi
  case $(cat "$sys/bus/pci/devices/$1/class") in
    0x01*|0x02*|0x03*|0x04*|0x0c03*|0x0805*|0x0d*|0x12*) ;;
    *) echo "system device" ;;
  esac
}

# Human-readable USB device name; unnamed devices are described by class
usb_name() {
  local dev="$1" name
  name=$(echo "$(cat "$dev/manufacturer" 2>/dev/null) $(cat "$dev/product" 2>/dev/null)" | xargs)
  if [[ -z $name ]]; then
    case $(cat "$dev/bDeviceClass") in
      e0) name="Bluetooth or wireless adapter (no name)" ;;
      *)  name="unnamed device $(cat "$dev/idVendor"):$(cat "$dev/idProduct")" ;;
    esac
  fi
  echo "$name"
}

# Names of the USB devices plugged into a USB controller (by PCI address)
usb_devices_on() {
  local ctrl="$1" dev names=()
  for dev in "$sys"/bus/usb/devices/*; do
    [[ -f $dev/idVendor && ${dev##*/} != usb* ]] || continue
    [[ $(cat "$dev/bDeviceClass") == 09 ]] && continue
    [[ $(readlink -f "$dev") == */$ctrl/* ]] || continue
    names+=("$(usb_name "$dev")")
  done
  local IFS=';'
  echo "${names[*]}" | sed 's/;/; /g'
}

list_pci() {
  local groups dev addr group drv blocker mates mate m_block status name
  groups=$(ls "$sys/kernel/iommu_groups" 2>/dev/null | wc -l)
  printf "PCI DEVICES"
  if [[ $groups -gt 0 ]]; then
    printf " (IOMMU on, %s groups)\n" "$groups"
  else
    printf " (IOMMU OFF: PCI passthrough is not possible.\n"
    printf "  Add intel_iommu=on (Intel) or amd_iommu=on (AMD) to the kernel command line and reboot.)\n"
  fi
  printf "%-8s %-5s %-17s %-23s %s\n" "ADDR" "GROUP" "DRIVER" "ATTACH" "DEVICE"

  root_disks=$(root_disk_paths)
  for dev in "$sys"/bus/pci/devices/*; do
    addr="${dev##*/}"
    group=$(basename "$(readlink "$dev/iommu_group")" 2>/dev/null)
    drv=$(basename "$(readlink "$dev/driver")" 2>/dev/null)
    blocker=$(pci_unattachable "$addr")

    # Every other non-bridge device in the IOMMU group is detached from the host too
    mates=()
    if [[ -z $blocker && -n $group ]]; then
      for mate in "$sys/kernel/iommu_groups/$group/devices"/*; do
        mate="${mate##*/}"
        [[ $mate == "$addr" ]] && continue
        m_block=$(pci_blocker "$mate")
        [[ $m_block == bridge ]] && continue
        if [[ -n $m_block ]]; then
          blocker="group has $m_block"
          break
        fi
        mates+=("$(short_addr "$mate")")
      done
    fi

    if [[ $groups -eq 0 ]]; then
      status="no (IOMMU off)"
    elif [[ -n $blocker ]]; then
      status="no ($blocker)"
    elif [[ $drv == vfio-pci ]]; then
      status="-pci $(short_addr "$addr") (ready)"
    else
      status="-pci $(short_addr "$addr")"
    fi
    name=$(pci_name "$addr")
    [[ ${#mates[@]} -gt 0 && $status == -pci* ]] && name+="  [also detaches: ${mates[*]}]"
    if [[ $(cat "$dev/class") == 0x0c03* && $status == -pci* ]]; then
      usb_on=$(usb_devices_on "$addr")
      [[ -n $usb_on ]] && name+="  [host loses USB: $usb_on]"
    fi
    printf "%-8s %-5s %-17s %-23s %s\n" "$(short_addr "$addr")" "${group:--}" "${drv:--}" "$status" "$name"
  done
  printf "\n'also detaches': devices in the same IOMMU group, which leave the host along with it.\n"
  printf "An attached PCI device is unavailable to the host until the VM shuts down.\n"
}

list_usb() {
  local dev name id
  printf "USB DEVICES\n"
  printf "%-22s %-9s %s\n" "ATTACH" "PORT" "DEVICE"
  for dev in "$sys"/bus/usb/devices/*; do
    name="${dev##*/}"
    [[ -f $dev/idVendor ]] || continue
    [[ $name == usb* ]] && continue                  # root hubs
    [[ $(cat "$dev/bDeviceClass") == 09 ]] && continue  # hubs
    id="$(cat "$dev/idVendor"):$(cat "$dev/idProduct")"
    printf "%-22s %-9s %s\n" "-usb $id" "$name" "$(usb_name "$dev")"
  done
  printf "\nIf two devices share an ID, attach by port instead: -usb PORT (e.g. -usb 3-1).\n"
}

case $1 in
  ""|all)  list_pci; echo; list_usb ;;
  pci)     list_pci ;;
  usb)     list_usb ;;
  help|--help|-h) usage ;;
  *) usage; exit 1 ;;
esac
