#!/bin/bash
# qemu-manager: create and boot QEMU/KVM virtual machines.
# Flags can be given in any order, before or after the command.

# DEFAULT CONFIGURATIONS

# MEMORY
memory="2G"  # Default memory if not defined

# SHARED FOLDER
shared_folder="$HOME/Public"  # Default shared folder if not defined

# CD BOOT KEY
# Windows ISOs only boot after "Press any key to boot from CD or DVD". When an ISO is
# attached, Enter is pressed for this many seconds after start (0 turns it off).
iso_keypress_seconds=10

# DISPLAY CLIENT
display_gtk=(-display gtk)
display_spice=(
  -display none
  -spice port=5900,disable-ticketing=on
  -chardev spiceport,name=org.spice-space.webdav.0,id=spiceport1
  -device virtio-serial
  -device virtserialport,chardev=spiceport1,name=org.spice-space.webdav.0
  -device ich9-usb-uhci1
  -device usb-tablet
)
display=("${display_gtk[@]}")  # Default display type if not defined

# SOUND
#sound=(-audiodev alsa,id=alsa -device AC97,id=snd0,audiodev=alsa)
sound_pa=(-device ich9-intel-hda -device hda-output,audiodev=pa -audiodev "pa,id=pa,server=unix:${XDG_RUNTIME_DIR}/pulse/native")
sound=()  # Default to no sound

# UEFI FIRMWARE (-uefi). Firmware paths differ per distro; Arch: /usr/share/edk2/x64/OVMF_CODE.4m.fd
# and OVMF_VARS.4m.fd (secure boot: OVMF_CODE.secboot.4m.fd, and enroll keys yourself).
ovmf_code="/usr/share/OVMF/OVMF_CODE_4M.fd"
ovmf_vars="/usr/share/OVMF/OVMF_VARS_4M.fd"
uefi_test="/home/user/github/coreboot-rust/bin/qemu_i440fx_8mb/qemu_i440fx_8mb.flash.bin"

# SECURE BOOT UEFI FIRMWARE (-secureboot)
ovmf_code_secboot="/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
ovmf_vars_ms="/usr/share/OVMF/OVMF_VARS_4M.ms.fd"  # Microsoft Secure Boot keys enrolled

# DEVICE PASSTHROUGH (-pci, -usb; list devices with qemu-devices.sh)
sys="/sys"  # sysfs root
pci_devs=()
usb_devs=()

die() {
  echo "Error: $*" >&2
  exit 1
}

# --- PCI passthrough helpers (same rules as qemu-devices.sh) ---

# Full PCI address: 00:14.3 -> 0000:00:14.3
pci_full_addr() {
  local a="${1,,}"
  [[ $a =~ ^[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]] && a="0000:$a"
  echo "$a"
}

# sysfs paths of the disks holding the root filesystem
root_disk_paths() {
  local src disk type
  src=$(findmnt -no SOURCE / 2>/dev/null) || return
  lsblk -nrso NAME,TYPE "$src" 2>/dev/null | while read -r disk type; do
    [[ $type == disk ]] && readlink -f "$sys/block/$disk"
  done
}

# Why a PCI device must never be detached from the host (empty if it may be)
pci_blocker() {
  local addr="$1" dev="$sys/bus/pci/devices/$1"
  if [[ $(cat "$dev/class") == 0x06* ]]; then
    echo "bridge"
  elif [[ $(cat "$dev/boot_vga" 2>/dev/null) == 1 ]]; then
    echo "host display"
  elif grep -q "/$addr/" <<< "$root_disks"; then
    echo "host system disk"
  fi
}

# Why a PCI device can't be attached: a hard blocker, or a platform device a VM has no use for
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

# Detach a PCI device from its host driver and bind it to vfio-pci, remembering the
# original driver so restore_pci can give it back when the VM exits
pci_restore=()
bind_vfio() {
  local addr="$1" dev="$sys/bus/pci/devices/$1" drv
  drv=$(basename "$(readlink "$dev/driver")" 2>/dev/null)
  [[ $drv == vfio-pci ]] && return 0  # already bound, by the user or earlier in this run
  pci_restore+=("$addr|$drv")
  echo vfio-pci > "$dev/driver_override" || die "could not prepare $addr for vfio-pci."
  if [[ -n $drv ]]; then
    echo "$addr" > "$dev/driver/unbind" || die "could not detach $addr from $drv."
  fi
  echo "$addr" > "$sys/bus/pci/drivers_probe"
  drv_now=$(basename "$(readlink "$dev/driver")" 2>/dev/null)
  [[ $drv_now == vfio-pci ]] || die "could not bind $addr to vfio-pci."
  echo "Detached ${addr#0000:} from the host (was: ${drv:-no driver})."
}

# Give every device bind_vfio detached back to its original host driver
restore_pci() {
  local entry addr drv
  for entry in "${pci_restore[@]}"; do
    addr="${entry%%|*}"
    drv="${entry#*|}"
    echo "$addr" > "$sys/bus/pci/drivers/vfio-pci/unbind" 2> /dev/null
    echo > "$sys/bus/pci/devices/$addr/driver_override"  # a bare newline clears it
    echo "$addr" > "$sys/bus/pci/drivers_probe" 2> /dev/null
    echo "Returned ${addr#0000:} to the host (${drv:-no driver})."
  done
}

usage() {
  printf "Usage: %s COMMAND [OPTIONS]   (options may come in any order)\n\n" "$0"
  printf "COMMANDS:\n"
  printf "  create           Create a new virtual disk.\n"
  printf "  boot             Boot the VM using specified flags.\n"
  printf "  view             Open the remote-viewer to connect to a -display spice VM.\n"
  printf "  help             Show this help message (also --help, -h).\n"
  printf "\nOPTIONS (for boot):\n"
  printf "  -qcow2 FILE      Disk image to boot (.qcow2, or a raw image such as .img).\n"
  printf "  -disk DEVICE     Physical disk to boot (e.g., /dev/sdb).\n"
  printf "  -iso FILE        ISO image to boot from (attached as a CD-ROM). Enter is pressed for the\n"
  printf "                   first %ss to get past \"Press any key to boot from CD\" (needs python3).\n" "$iso_keypress_seconds"
  printf "  -memory SIZE     Memory size (default: 2G). Example: 4G, 1024M.\n"
  printf "  -smp N           Number of virtual CPUs (default: 1).\n"
  printf "  -tpm             Attach an emulated TPM 2.0 chip (needs swtpm).\n"
  printf "  -secureboot      Boot with Secure Boot UEFI (Microsoft keys) on a q35 machine (needs ovmf).\n"
  printf "  -uefi            Boot with plain (non-Secure Boot) UEFI firmware.\n"
  printf "                   -tpm, -secureboot and -uefi keep their state in <disk>.vmstate/ next to the disk.\n"
  printf "  -sound           Enable sound output (PulseAudio/PipeWire).\n"
  printf "  -share TYPE      Share %s with the guest: '9p' or 'samba'.\n" "$shared_folder"
  printf "  -display TYPE    Display type: 'gtk' (default) or 'spice'.\n"
  printf "  -pci ADDR        Attach a host PCI device, e.g. -pci 00:14.3 (needs sudo). It is detached\n"
  printf "                   from the host while the VM runs, then given back. Repeat for more devices.\n"
  printf "  -usb ID          Attach a host USB device by VENDOR:PRODUCT (e.g. 0951:1666) or by port\n"
  printf "                   (e.g. 3-1). Repeat for more devices. Usually needs sudo.\n"
  printf "                   List devices and their -pci/-usb values with: qemu-devices.sh\n"
  printf "\nA disk image or ISO can also be given without a flag: %s boot vm.qcow2 os.iso\n" "$0"
  printf "\nWINDOWS 11:\n"
  printf "  Windows 11 setup checks for Secure Boot, TPM 2.0, 4G memory, 2 CPUs and a 64G disk.\n"
  printf "  Create a disk of at least 64 GB, then boot with all of:\n"
  printf "    -secureboot -tpm -memory 4G -smp 2\n"
  printf "  Keep the same flags on every later boot: Windows ties its data to that TPM and UEFI state.\n"
  printf "\nEXAMPLES:\n"
  printf "  %s create\n" "$0"
  printf "  %s boot -qcow2 Public/test.qcow2 -iso Downloads/Win10_22H2_English_x64.iso -memory 8G -sound -share 9p -display spice\n" "$0"
  printf "  %s boot -qcow2 win11.qcow2 -iso Downloads/Win11_English_x64.iso -secureboot -tpm -memory 4G -smp 2\n" "$0"
  printf "  %s view\n" "$0"
}

# Set a command, refusing a second, different one (e.g. "boot create")
set_command() {
  if [[ -n $cmd && $cmd != "$1" ]]; then
    die "choose one command, got both '$cmd' and '$1'."
  fi
  cmd="$1"
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  opt="$1"
  case $opt in
    -qcow2|-disk|-iso|-memory|-smp|-share|-display|-pci|-usb)
      # These flags take a value: it must exist and must not be another flag
      if [[ $# -lt 2 || $2 == -* ]]; then
        die "$opt needs a value (see --help)."
      fi
      value="$2"
      shift 2
      case $opt in
        -qcow2)   qcow2_file="$value" ;;
        -disk)    disk="$value" ;;
        -iso)     iso_file="$value" ;;
        -memory)  memory="$value" ;;
        -smp)     smp="$value" ;;
        -pci)     pci_devs+=("$value") ;;
        -usb)     usb_devs+=("$value") ;;
        -share)
          case $value in
            9p|samba) share_type="$value" ;;
            *) die "-share must be '9p' or 'samba', got '$value'." ;;
          esac
          ;;
        -display)
          case $value in
            gtk)   display=("${display_gtk[@]}") ;;
            spice) display=("${display_spice[@]}") ;;
            *) die "-display must be 'gtk' or 'spice', got '$value'." ;;
          esac
          ;;
      esac
      ;;
    -secureboot) secureboot=1; shift ;;
    -tpm)    tpm=1; shift ;;
    -sound)  sound=("${sound_pa[@]}"); shift ;;
    -uefi)   uefi=1; shift ;;
    -test)   uefi_file="$uefi_test"; shift ;;
    boot|create)        set_command "$opt"; shift ;;
    view|client)        set_command view; shift ;;
    help|--help|-h)     usage; exit 0 ;;
    -*)
      die "unknown option '$opt' (see --help)."
      ;;
    *)
      # Bare file name: an ISO goes to -iso, anything else is the disk
      shopt -s nocasematch
      if [[ $opt == *.iso ]]; then
        [[ -z $iso_file ]] || die "two ISO files given: '$iso_file' and '$opt'."
        iso_file="$opt"
      elif [[ -z $qcow2_file && -z $disk ]]; then
        qcow2_file="$opt"
      else
        die "unexpected argument '$opt' (see --help)."
      fi
      shopt -u nocasematch
      shift
      ;;
  esac
done

case $cmd in
  create)
    read -r -p "Name of virtual disk: " disk_name
    read -r -p "Size of virtual disk (GB): " size
    [[ $size =~ ^[0-9]+$ ]] || die "size must be a whole number of GB, got '$size'."
    qemu-img create -f qcow2 "${disk_name}.qcow2" "${size}G"
    exit $?
    ;;
  view)
    remote-viewer spice://localhost:5900 > "$shared_folder/remote-viewer.log" 2>&1
    printf "\\\\\\\\10.0.2.4\\\\qemu\n"
    exit 0
    ;;
  boot)
    ;;  # handled below
  *)
    die "please specify 'boot', 'create' or 'view' (see --help)."
    ;;
esac

# Error checking for boot command
if [[ -n $qcow2_file && -n $disk ]]; then
  die "use either -qcow2 or -disk, not both."
fi
target="${qcow2_file:-$disk}"
[[ -n $target ]] || die "you must specify a disk with -qcow2 FILE or -disk DEVICE when booting."
[[ -e $target ]] || die "disk '$target' does not exist."
if [[ -n $iso_file && ! -f $iso_file ]]; then
  die "ISO '$iso_file' does not exist."
fi
if [[ -n $smp && ! $smp =~ ^[0-9]+$ ]]; then
  die "-smp must be a number, got '$smp'."
fi

# Disk: qcow2 images by extension, everything else (block devices, .img, .raw) as raw
shopt -s nocasematch
if [[ $target == *.qcow2 ]]; then
  disk_format=qcow2
else
  disk_format=raw
fi
shopt -u nocasematch
args=(-enable-kvm -cpu host)

# Boot order: CD first when an ISO is given, then the disk. bootindex works for both
# BIOS and UEFI (UEFI ignores -boot d).
args+=(
  -drive "if=none,id=hd0,file=$target,format=$disk_format"
  -device ide-hd,drive=hd0,bus=ide.0,bootindex=1
)
if [[ -n $iso_file ]]; then
  args+=(
    -drive "if=none,id=cd0,file=$iso_file,format=raw,media=cdrom,readonly=on"
    -device ide-cd,drive=cd0,bus=ide.1,bootindex=0
  )
fi

# No network boot (PXE): without it, a missed "Press any key to boot from CD" falls
# through to the disk instead of minutes of "Start PXE over IPv4". Networking still works.
args+=(-global e1000e.romfile= -global e1000.romfile= -global virtio-net-pci.romfile=)

# USB passthrough: each device on its own guest xHCI controller port
if [[ ${#usb_devs[@]} -gt 0 ]]; then
  args+=(-device qemu-xhci,id=usbpass)
  for u in "${usb_devs[@]}"; do
    if [[ $u =~ ^([0-9a-fA-F]{4}):([0-9a-fA-F]{4})$ ]]; then
      vid="${BASH_REMATCH[1],,}"
      pid="${BASH_REMATCH[2],,}"
      matches=()
      for d in "$sys"/bus/usb/devices/*; do
        [[ -f $d/idVendor && $(cat "$d/idVendor") == "$vid" && $(cat "$d/idProduct") == "$pid" ]] && matches+=("$d")
      done
      [[ ${#matches[@]} -gt 0 ]] || die "USB device $u is not plugged in (list devices with qemu-devices.sh usb)."
      [[ ${#matches[@]} -eq 1 ]] || die "${#matches[@]} USB devices have ID $u; attach one by port instead (see qemu-devices.sh usb)."
      usb_dev="${matches[0]}"
      args+=(-device "usb-host,bus=usbpass.0,vendorid=0x$vid,productid=0x$pid")
    elif [[ $u =~ ^([0-9]+)-([0-9.]+)$ ]]; then
      usb_dev="$sys/bus/usb/devices/$u"
      [[ -f $usb_dev/idVendor ]] || die "no USB device at port $u (list devices with qemu-devices.sh usb)."
      args+=(-device "usb-host,bus=usbpass.0,hostbus=${BASH_REMATCH[1]},hostport=${BASH_REMATCH[2]}")
    else
      die "-usb takes VENDOR:PRODUCT (e.g. 0951:1666) or a port (e.g. 3-1), got '$u'."
    fi
    node=$(printf "/dev/bus/usb/%03d/%03d" "$(cat "$usb_dev/busnum")" "$(cat "$usb_dev/devnum")")
    [[ -w $node ]] || die "no permission to use USB device $u ($node); run with sudo."
  done
fi

# PCI passthrough (VFIO): detach each device, and the rest of its IOMMU group, from the
# host; restore_pci gives them back when the script exits, however it exits
if [[ ${#pci_devs[@]} -gt 0 ]]; then
  [[ $EUID -eq 0 ]] || die "-pci needs root to detach devices from the host; run with sudo."
  [[ -n $(ls -A "$sys/kernel/iommu_groups" 2> /dev/null) ]] ||
    die "the IOMMU is off. Add intel_iommu=on (Intel) or amd_iommu=on (AMD) to the kernel command line and reboot."
  modprobe vfio-pci || die "could not load the vfio-pci kernel module."
  root_disks=$(root_disk_paths)
  trap restore_pci EXIT
  attached=()
  for a in "${pci_devs[@]}"; do
    addr=$(pci_full_addr "$a")
    pci_dev="$sys/bus/pci/devices/$addr"
    [[ -e $pci_dev ]] || die "no PCI device $a (list devices with qemu-devices.sh pci)."
    [[ " ${attached[*]} " == *" $addr "* ]] && continue  # given twice
    reason=$(pci_unattachable "$addr")
    [[ -z $reason ]] || die "PCI device $a can't be attached: $reason."
    group=$(basename "$(readlink "$pci_dev/iommu_group")")
    for m in "$sys/kernel/iommu_groups/$group/devices"/*; do
      m="${m##*/}"
      reason=$(pci_blocker "$m")
      [[ $reason == bridge ]] && continue
      [[ -z $reason ]] || die "PCI device $a shares IOMMU group $group with ${m#0000:} ($reason), which must stay with the host."
    done
    for m in "$sys/kernel/iommu_groups/$group/devices"/*; do
      m="${m##*/}"
      [[ $(pci_blocker "$m") == bridge ]] || bind_vfio "$m"
    done
    attached+=("$addr")
    args+=(-device "vfio-pci,host=$addr")
  done
fi

# Per-VM state (TPM, UEFI vars) lives next to the disk, e.g. vm.qcow2 -> vm.vmstate/
if [[ $target == /dev/* ]]; then
  state_dir="$HOME/.local/share/qemu-manager/$(basename "$target").vmstate"  # E.g., /dev/sdb
elif [[ ${target##*/} == *.* ]]; then
  state_dir="${target%.*}.vmstate"  # strip the extension of the file name only
else
  state_dir="$target.vmstate"
fi

# Secure Boot: q35 with SMM (required by the firmware), Secure Boot OVMF and per-VM UEFI vars
if [[ $secureboot == 1 ]]; then
  [[ -z $uefi_file && $uefi != 1 ]] || die "use either -secureboot or -uefi/-test, not both."
  for f in "$ovmf_code_secboot" "$ovmf_vars_ms"; do
    [[ -f $f ]] || die "$f not found (Debian/Ubuntu: sudo apt install ovmf)."
  done
  mkdir -p "$state_dir" || exit 1
  if [[ ! -f $state_dir/vars.fd ]]; then
    cp "$ovmf_vars_ms" "$state_dir/vars.fd" || exit 1
  fi

  args+=(
    -machine q35,smm=on
    -global driver=cfi.pflash01,property=secure,value=on
    -drive "if=pflash,format=raw,unit=0,file=$ovmf_code_secboot,readonly=on"
    -drive "if=pflash,format=raw,unit=1,file=$state_dir/vars.fd"
  )
fi

# Plain UEFI: read-only firmware plus this VM's own copy of the UEFI settings, so no system
# file has to be writable (uefi-vars.fd; vars.fd belongs to -secureboot)
if [[ $uefi == 1 ]]; then
  [[ -z $uefi_file ]] || die "use either -uefi or -test, not both."
  for f in "$ovmf_code" "$ovmf_vars"; do
    [[ -f $f ]] || die "$f not found (Debian/Ubuntu: sudo apt install ovmf)."
  done
  mkdir -p "$state_dir" || exit 1
  if [[ ! -f $state_dir/uefi-vars.fd ]]; then
    cp "$ovmf_vars" "$state_dir/uefi-vars.fd" || exit 1
  fi
  args+=(
    -drive "if=pflash,format=raw,unit=0,file=$ovmf_code,readonly=on"
    -drive "if=pflash,format=raw,unit=1,file=$state_dir/uefi-vars.fd"
  )
fi

if [[ -n $uefi_file ]]; then
  args+=(-drive "if=pflash,format=raw,file=$uefi_file")
fi

# TPM 2.0: emulated by swtpm, state persists in <disk>.vmstate/tpm/
if [[ $tpm == 1 ]]; then
  command -v swtpm > /dev/null || die "swtpm not found (Debian/Ubuntu: sudo apt install swtpm)."
  mkdir -p "$state_dir/tpm" || exit 1
  # --terminate makes swtpm exit when QEMU disconnects
  if ! swtpm socket --tpm2 --tpmstate dir="$state_dir/tpm" \
      --ctrl type=unixio,path="$state_dir/tpm/sock" --terminate --daemon; then
    die "could not start swtpm. Is this VM already running?"
  fi
  args+=(
    -chardev "socket,id=chrtpm,path=$state_dir/tpm/sock"
    -tpmdev emulator,id=tpm0,chardev=chrtpm
    -device tpm-tis,tpmdev=tpm0
  )
fi

args+=(-m "$memory")
[[ -n $smp ]] && args+=(-smp "$smp")
args+=("${display[@]}" "${sound[@]}")

if [[ -n $share_type ]]; then
  mkdir -p "$shared_folder" || die "could not create the shared folder $shared_folder."
fi
case $share_type in
  9p)
    args+=(
      -fsdev "local,security_model=mapped,id=fsdev0,path=$shared_folder"
      -device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare
    )
    ;;
  samba)
    args+=(-net "user,smb=$shared_folder" -net nic,model=virtio)
    ;;
esac

# Press Enter through the "Press any key to boot from CD or DVD" prompt, over QMP
# (a control socket, so the GTK window's own monitor stays as it is). Needs python3.
qmp_dir=""
if [[ -n $iso_file && $iso_keypress_seconds -gt 0 ]] && command -v python3 > /dev/null; then
  qmp_dir=$(mktemp -d) || exit 1
  args+=(-qmp "unix:$qmp_dir/qmp.sock,server=on,wait=off")
  python3 - "$qmp_dir/qmp.sock" "$iso_keypress_seconds" <<'EOF' > /dev/null 2>&1 &
import json, os, socket, sys, time
path, seconds = sys.argv[1], float(sys.argv[2])
deadline = time.time() + 15
while not os.path.exists(path):          # wait for QEMU to open the socket
    if time.time() > deadline:
        sys.exit(0)
    time.sleep(0.1)
s = socket.socket(socket.AF_UNIX)
s.connect(path)
f = s.makefile("rw")
f.readline()                              # QMP greeting
def qmp(cmd, **arguments):
    f.write(json.dumps({"execute": cmd, "arguments": arguments}) + "\n")
    f.flush()
    while True:                           # skip async events until the reply
        line = f.readline()
        if not line:
            sys.exit(0)                   # QEMU exited
        reply = json.loads(line)
        if "return" in reply or "error" in reply:
            return
qmp("qmp_capabilities")
end = time.time() + seconds
while time.time() < end:
    qmp("send-key", keys=[{"type": "qcode", "data": "ret"}])
    time.sleep(0.5)
EOF
  keypress_pid=$!
fi

# Run QEMU, then print the exact command line used
qemu-system-x86_64 "${args[@]}"
status=$?
if [[ -n $qmp_dir ]]; then
  kill "$keypress_pid" 2> /dev/null
  rm -rf "$qmp_dir"
fi
printf "\nqemu-system-x86_64"
for a in "${args[@]}"; do
  if [[ $a =~ ^[A-Za-z0-9_./:,=+@-]+$ ]]; then
    printf " %s" "$a"   # plain argument, print as-is
  else
    printf " %q" "$a"   # spaces or special characters: quote it
  fi
done
printf "\n"
exit $status
