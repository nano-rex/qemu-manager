#!/bin/bash
# qemu-manager: create and boot QEMU/KVM virtual machines.
# Flags can be given in any order, before or after the command.

# DEFAULT CONFIGURATIONS

# MEMORY
memory="2G"  # Default memory if not defined

# SHARED FOLDER
shared_folder="$HOME/Public"  # Default shared folder if not defined

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

# UEFI FIRMWARE
uefi_plain="/usr/share/qemu/OVMF.fd"
uefi_test="/home/user/github/coreboot-rust/bin/qemu_i440fx_8mb/qemu_i440fx_8mb.flash.bin"

# SECURE BOOT UEFI FIRMWARE (-secureboot)
ovmf_code_secboot="/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
ovmf_vars_ms="/usr/share/OVMF/OVMF_VARS_4M.ms.fd"  # Microsoft Secure Boot keys enrolled

die() {
  echo "Error: $*" >&2
  exit 1
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
  printf "  -iso FILE        ISO image to boot from (attached as a CD-ROM).\n"
  printf "  -memory SIZE     Memory size (default: 2G). Example: 4G, 1024M.\n"
  printf "  -smp N           Number of virtual CPUs (default: 1).\n"
  printf "  -tpm             Attach an emulated TPM 2.0 chip (needs swtpm).\n"
  printf "  -secureboot      Boot with Secure Boot UEFI (Microsoft keys) on a q35 machine (needs ovmf).\n"
  printf "  -uefi            Boot with plain (non-Secure Boot) UEFI firmware.\n"
  printf "                   -tpm and -secureboot keep their state in <disk>.vmstate/ next to the disk.\n"
  printf "  -sound           Enable sound output (PulseAudio/PipeWire).\n"
  printf "  -share TYPE      Share %s with the guest: '9p' or 'samba'.\n" "$shared_folder"
  printf "  -display TYPE    Display type: 'gtk' (default) or 'spice'.\n"
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
    -qcow2|-disk|-iso|-memory|-smp|-share|-display)
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
    -uefi)   uefi_file="$uefi_plain"; shift ;;
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
  [[ -z $uefi_file ]] || die "use either -secureboot or -uefi/-test, not both."
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

# Run QEMU, then print the exact command line used
qemu-system-x86_64 "${args[@]}"
status=$?
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
