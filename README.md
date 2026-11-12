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

## Install

Requires QEMU with KVM (Debian/Ubuntu: `sudo apt install qemu-system-x86 qemu-utils`;
Arch: `sudo pacman -S qemu-full`). `-secureboot` needs `ovmf` and `-tpm` needs `swtpm`. Your user
needs to be in the `kvm` group (`sudo usermod -aG kvm $USER`, then log in again). There's
nothing to build:

```bash
git clone https://github.com/nano-rex/qemu-manager.git
cd qemu-manager
sudo install -m 755 qemu-manager.sh /usr/local/bin/qemu-manager
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
Press a key when asked to boot from CD. Keep the same flags on every later boot, because
Windows ties its data to that TPM and UEFI state:

```bash
qemu-manager boot -qcow2 win11.qcow2 -iso Win11_English_x64.iso -secureboot -tpm -memory 4G -smp 2
qemu-manager boot -qcow2 win11.qcow2 -secureboot -tpm -memory 4G -smp 2
```

Boot an external disk as a VM, for example to troubleshoot an OS that won't start on
another machine. Pass the whole disk, not a partition (`sdb`, not `sdb1`):

```bash
sudo qemu-manager boot -disk /dev/sdb
```

Inside a Linux guest booted with `-share 9p`, mount the shared `~/Public` folder:

```bash
sudo mount -t 9p -o trans=virtio hostshare /mnt
```

## License

GPL-3.0, see `LICENSE`.
