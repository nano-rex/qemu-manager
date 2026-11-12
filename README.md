# qemu-manager

Quickly create and run QEMU/KVM virtual machines from the terminal, without writing long
`qemu-system-x86_64` command lines.

## Functionality

- `create` — asks for a name and size and creates a `<name>.qcow2` disk image.
- `boot -qcow2 <disk.qcow2> [-iso <os.iso>]` — boots a `.qcow2` image, or a whole physical
  disk with `-disk /dev/sdb`, optionally with an installer ISO attached as a CD-ROM.
- Every VM runs with KVM acceleration and the host CPU model. Memory defaults to 2 GB
  (`-memory 4G` to change it), CPUs to 1 (`-smp 4`).
- `-secureboot` boots with Secure Boot UEFI firmware (Microsoft keys) on a q35 machine.
- `-tpm` attaches an emulated TPM 2.0 chip (swtpm).
- `-secureboot` and `-tpm` keep the VM's UEFI settings and TPM state in `<disk>.vmstate/`
  next to the disk, so keep that folder with the image.
- `-share 9p` shares `~/Public` with the guest over virtio-9p (mount tag `hostshare`).
- `-usb ID` attaches a host USB device (by `VENDOR:PRODUCT` or port), and `-pci ADDR`
  attaches a host PCI device such as a Wi-Fi card or USB controller. `qemu-devices.sh`
  lists the devices you can attach and the flag to use for each.

## Install

Requires QEMU with KVM (Debian/Ubuntu: `sudo apt install qemu-system-x86 qemu-utils`;
Arch: `sudo pacman -S qemu-full`). `-secureboot` needs `ovmf` and `-tpm` needs `swtpm`. Your user
needs to be in the `kvm` group (`sudo usermod -aG kvm $USER`, then log in again). There's
nothing to build:

```bash
git clone https://github.com/nano-rex/qemu-manager.git
cd qemu-manager
sudo install -m 755 qemu-manager.sh /usr/local/bin/qemu-manager
sudo install -m 755 qemu-devices.sh /usr/local/bin/qemu-devices
```

`qemu-manager.ps1` is an unfinished Windows draft: it calls `New-QemuDisk` /
`Start-QemuSystem`, which aren't shipped with QEMU, so use the Linux script.

## Examples

Create a new virtual machine disk (prompts for name and size, writes `VM.qcow2`):

```bash
qemu-manager create
```

Install an OS onto it:

```bash
qemu-manager boot -qcow2 VM.qcow2 -iso debian-13-amd64-netinst.iso
```

Run it afterwards:

```bash
qemu-manager boot -qcow2 VM.qcow2
```

Install Windows 11. Setup checks for Secure Boot, TPM 2.0, 4 GB RAM, 2 CPUs and a 64 GB
disk, so create a disk of at least 64 GB and boot with `-secureboot -tpm -memory 4G -smp 2`.
The script presses Enter for you through "Press any key to boot from CD or DVD" during
the first 10 seconds after an ISO is attached (`iso_keypress_seconds` at the top of the
script; needs `python3`). Click into the VM window before using Setup, so it has keyboard
focus. Keep the same flags on every later boot, because Windows ties its data to that TPM
and UEFI state:

```bash
qemu-manager boot -qcow2 win11.qcow2 -iso Win11_English_x64.iso -secureboot -tpm -memory 4G -smp 2
qemu-manager boot -qcow2 win11.qcow2 -secureboot -tpm -memory 4G -smp 2
```

Boot an external disk as a VM, for example to troubleshoot an OS that won't start on
another machine. Pass the whole disk, not a partition (`sdb`, not `sdb1`):

```bash
sudo qemu-manager boot -disk /dev/sdb
```

Attach host devices. List them first; the `ATTACH` column gives the flag to use, or why a
device can't be attached (the host's display, system disk, bridges and internal platform
devices are refused):

```bash
qemu-devices                # PCI and USB devices
sudo qemu-manager boot -qcow2 VM.qcow2 -usb 0951:1666 -pci 00:14.3
```

- `-usb` takes `VENDOR:PRODUCT`, or the port (e.g. `3-1`) when two devices share an ID.
  It needs `sudo` unless your user can write to the device under `/dev/bus/usb`.
- `-pci` needs `sudo` and the IOMMU (`intel_iommu=on` / `amd_iommu=on` if it's off). The
  device, and any other device in its IOMMU group, is detached from the host while the VM
  runs and given back to its driver when the VM exits. Attaching a USB controller takes
  every USB device on it away from the host; `qemu-devices` lists them.

Inside a Linux guest booted with `-share 9p`, mount the shared `~/Public` folder:

```bash
sudo mount -t 9p -o trans=virtio hostshare /mnt
```

## License

GPL-3.0, see `LICENSE`.
