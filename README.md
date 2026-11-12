# qemu-manager

Quickly create and run QEMU/KVM virtual machines from the terminal, without writing long
`qemu-system-x86_64` command lines.

- `qemu-manager.sh` creates disks and boots VMs, including Windows 11 (Secure Boot + TPM 2.0)
  and VMs with host USB/PCI devices attached.
- `qemu-devices.sh` lists the host's PCI and USB devices and the flag to attach each one.

## Install

Requires QEMU with KVM (Debian/Ubuntu: `sudo apt install qemu-system-x86 qemu-utils`;
Arch: `sudo pacman -S qemu-full`). Optional, per feature:

| Package | Needed for |
|---|---|
| `ovmf` | `-secureboot`, `-uefi` |
| `swtpm` | `-tpm` |
| `python3` | pressing "any key" at an ISO's boot prompt for you |
| `pciutils` (`lspci`) | readable device names in `qemu-devices` |
| `virt-viewer` | `-display spice` with `qemu-manager view` |

Your user must be in the `kvm` group (`sudo usermod -aG kvm $USER`, then log out and in).
There's nothing to build:

```bash
git clone https://github.com/nano-rex/qemu-manager.git
cd qemu-manager
sudo install -m 755 qemu-manager.sh /usr/local/bin/qemu-manager
sudo install -m 755 qemu-devices.sh /usr/local/bin/qemu-devices
```

The examples below use the installed names. Without installing, run `./qemu-manager.sh`
and `./qemu-devices.sh` from the repository folder instead.

`qemu-manager.ps1` is an unfinished Windows draft: it calls `New-QemuDisk` /
`Start-QemuSystem`, which aren't shipped with QEMU, so use the Linux script.

## Quick start

```bash
qemu-manager create                                   # name: VM, size: 20 -> VM.qcow2
qemu-manager boot -qcow2 VM.qcow2 -iso debian-13-amd64-netinst.iso   # install
qemu-manager boot -qcow2 VM.qcow2                     # run it afterwards
```

## Usage

```
qemu-manager COMMAND [OPTIONS]
```

Options can be given in any order, before or after the command. A mistyped or incomplete
option stops with an error instead of being ignored.

### Commands

| Command | What it does |
|---|---|
| `create` | Asks for a name and a size in GB, and creates `<name>.qcow2`. |
| `boot` | Boots a VM from the options below. |
| `view` | Opens `remote-viewer` on a VM started with `-display spice`. |
| `help` | Shows the built-in help (also `--help`, `-h`). |

### Boot options

| Option | What it does |
|---|---|
| `-qcow2 FILE` | Disk image to boot: `.qcow2`, or a raw image such as `.img`. |
| `-disk DEVICE` | Whole physical disk to boot, e.g. `/dev/sdb` (usually needs `sudo`). |
| `-iso FILE` | ISO attached as a CD-ROM and booted first. |
| `-memory SIZE` | Guest memory, e.g. `4G`, `1024M`. Default `2G`. |
| `-smp N` | Number of virtual CPUs. Default `1`. |
| `-secureboot` | Secure Boot UEFI firmware (Microsoft keys) on a q35 machine. |
| `-tpm` | Emulated TPM 2.0 chip. |
| `-uefi` | Plain UEFI firmware, without Secure Boot. |
| `-sound` | Sound output through PulseAudio/PipeWire. |
| `-share 9p\|samba` | Shares `~/Public` with the guest (see [Shared folder](#shared-folder)). |
| `-display gtk\|spice` | VM window (`gtk`, default) or a SPICE server for `qemu-manager view`. |
| `-usb ID` | Attaches a host USB device by `VENDOR:PRODUCT` or by port. Repeatable. |
| `-pci ADDR` | Attaches a host PCI device, e.g. `00:14.3` (needs `sudo`). Repeatable. |

A disk image and an ISO can also be given without flags:
`qemu-manager boot VM.qcow2 debian.iso`.

After the VM shuts down, the script prints the exact `qemu-system-x86_64` command it ran.

`-secureboot` and `-tpm` keep the VM's UEFI settings and TPM state in a folder next to the
disk (`VM.qcow2` → `VM.vmstate/`; for a physical disk, under
`~/.local/share/qemu-manager/`). Keep that folder with the image and keep using the same
flags, or the guest loses its TPM data (BitLocker keys, Windows Hello).

### qemu-devices

```
qemu-devices [pci|usb]
```

Lists the host's PCI and USB devices (both, or one kind). The `ATTACH` column shows the
`-pci` / `-usb` value to pass to `qemu-manager boot`, or `no (reason)` when the device must
stay with the host.

## Guides

### Install an operating system

1. Create a disk: `qemu-manager create` (enter a name and a size in GB).
2. Boot it with the installer ISO:
   `qemu-manager boot -qcow2 VM.qcow2 -iso installer.iso -memory 4G -smp 2`
3. When the install is finished, boot without the ISO:
   `qemu-manager boot -qcow2 VM.qcow2 -memory 4G -smp 2`

When an ISO is attached, the script presses Enter for you during the first 10 seconds, to
get past prompts such as Windows' "Press any key to boot from CD or DVD". Change the time
with `iso_keypress_seconds` at the top of the script, or set it to `0` to turn this off.

### Windows 11

Windows 11 Setup checks for Secure Boot, a TPM 2.0, 4 GB of memory, 2 CPUs and a 64 GB
disk. These flags provide all of them:

```bash
qemu-manager create                  # size: 64 or more
qemu-manager boot -qcow2 win11.qcow2 -iso Win11_English_x64.iso -secureboot -tpm -memory 4G -smp 2
```

1. Setup starts on its own (the script presses the "boot from CD" key).
2. Click inside the VM window, so Setup gets keyboard focus.
3. Install as usual. Setup restarts the VM a few times; let it boot from the disk.
4. After installing, boot without `-iso`, and always with the same flags:
   `qemu-manager boot -qcow2 win11.qcow2 -secureboot -tpm -memory 4G -smp 2`

Windows 11 Home requires internet and a Microsoft account during first setup. The VM has
internet through QEMU's built-in network, so that works. Pro also allows a local account.

### Attach host devices (USB and PCI)

1. List the devices:

   ```bash
   qemu-devices
   ```

   ```
   PCI DEVICES (IOMMU on, 15 groups)
   ADDR     GROUP DRIVER            ATTACH                  DEVICE
   00:02.0  0     i915              no (host display)       VGA compatible controller: Intel ... UHD Graphics
   00:14.0  6     xhci_hcd          -pci 00:14.0            USB controller: ...  [also detaches: 00:14.2]  [host loses USB: ...]
   00:14.3  7     iwlwifi           -pci 00:14.3            Network controller: Intel ... WiFi
   01:00.0  13    nvme              no (host system disk)   Non-Volatile memory controller: Samsung ...
   02:00.0  14    sdhci-pci         -pci 02:00.0            SD Host controller: Genesys Logic ...

   USB DEVICES
   ATTACH                 PORT      DEVICE
   -usb 0951:1666         3-1       Kingston DataTraveler 3.0
   -usb 174f:2465         3-8       Integrated Camera
   ```

2. Copy the value from the `ATTACH` column into the boot command:

   ```bash
   sudo qemu-manager boot -qcow2 VM.qcow2 -usb 0951:1666 -pci 02:00.0
   ```

How each works:

- **USB (`-usb`)** passes through a single device. Use `VENDOR:PRODUCT`, or the port
  (e.g. `-usb 3-1`) when two devices share an ID. It needs `sudo` unless your user can write
  to the device under `/dev/bus/usb`. The device disappears from the host while the VM runs.
- **PCI (`-pci`)** needs `sudo` and the IOMMU (turn it on with `intel_iommu=on` or
  `amd_iommu=on` on the kernel command line if `qemu-devices` says it's off). The device is
  detached from its host driver while the VM runs, and given back when the VM shuts down or
  the script fails.
  - Devices in the same IOMMU group must leave the host together; the list shows them as
    `also detaches`.
  - Attaching a USB controller takes every USB device on it away from the host (listed as
    `host loses USB`), which may include your mouse. Attach single USB devices with `-usb`
    instead when you can.
  - Attaching the Wi-Fi card cuts the host's Wi-Fi until the VM shuts down.
  - The host's display, the disk the host runs from, bridges and internal platform devices
    (BIOS flash, I2C, SMBus, thermal) are refused.

### Boot a physical disk

Boot an external disk as a VM, for example to troubleshoot an OS that won't start on
another machine. Pass the whole disk, not a partition (`sdb`, not `sdb1`):

```bash
sudo qemu-manager boot -disk /dev/sdb
```

Add `-uefi` if the OS on it was installed in UEFI mode.

### Shared folder

`-share 9p` shares `~/Public`. Inside a Linux guest, mount it with:

```bash
sudo mount -t 9p -o trans=virtio hostshare /mnt
```

`-share samba` shares it over SMB instead (needs `samba` on the host). In a Windows guest,
open `\\10.0.2.4\qemu`.

### Remote display (SPICE)

```bash
qemu-manager boot -qcow2 VM.qcow2 -display spice    # terminal 1
qemu-manager view                                    # terminal 2
```

## Troubleshooting

**"Could not access KVM kernel module: Permission denied"**: your user isn't in the `kvm`
group. Run `sudo usermod -aG kvm $USER`, then log out and back in.

**"Start PXE over IPv4", or "No bootable option or device was found"**: the CD boot prompt
was missed. Network boot is turned off, so the VM stops at "Press any key to enter the
Boot Manager Menu": press a key, choose the DVD drive, then press a key at the CD prompt.

**"This PC can't run Windows 11"**: boot with all of `-secureboot -tpm -memory 4G -smp 2`
on a disk of at least 64 GB. If you must install without them (another VM tool, older
hardware), press Shift+F10 on that screen, run

```
for %k in (TPM SecureBoot RAM CPU Storage) do reg add HKLM\SYSTEM\Setup\LabConfig /v Bypass%kCheck /t REG_DWORD /d 1 /f
```

type `exit`, click Setup's back arrow, then Next again. Windows then installs without the
checks, but features that need a TPM or Secure Boot, such as BitLocker, won't be available.

**"could not start swtpm. Is this VM already running?"**: the same disk is already booted,
or a previous run left `swtpm` behind. Close the other VM, or end it with
`pkill -f '<name>.vmstate/tpm'`.

**Keys do nothing in Windows Setup**: click inside the VM window first, so it has focus.

## License

GPL-3.0, see `LICENSE`.
