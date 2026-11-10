# qemu-manager

Quickly create and run QEMU/KVM virtual machines from the terminal, without writing long
`qemu-system-x86_64` command lines.

## Functionality

- `create` — asks for a name and size and creates a `<name>.qcow2` disk image.
- `boot <disk> [<os.iso>]` — boots a `.qcow2` image, or a whole physical disk such as
  `/dev/sdb`, optionally with an installer ISO attached as a CD-ROM.
- Every VM runs with KVM acceleration, the host CPU model, 4 GB RAM (`memory=` at the top
  of the script), and shares `~/Public` with the guest over virtio-9p (mount tag `hostshare`).

## Install

Requires QEMU with KVM (Debian/Ubuntu: `sudo apt install qemu-system-x86 qemu-utils`;
Arch: `sudo pacman -S qemu-full`). There's nothing to build:

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
qemu-manager boot VM.qcow2 debian-13-amd64-netinst.iso
```

Run it afterwards:

```bash
qemu-manager boot VM.qcow2
```

Boot an external disk as a VM, for example to troubleshoot an OS that won't start on
another machine. Pass the whole disk, not a partition (`sdb`, not `sdb1`):

```bash
sudo qemu-manager boot /dev/sdb
```

Inside a Linux guest, mount the shared `~/Public` folder:

```bash
sudo mount -t 9p -o trans=virtio hostshare /mnt
```

## License

GPL-3.0, see `LICENSE`.
