#!/bin/bash

# DEFAULT CONFIGURATIONS

# MEMORY
memory="2G"  # Default memory if not defined

# DISPLAY CLIENT
display_spice="-display none -spice port=5900,disable-ticketing=on -chardev spiceport,name=org.spice-space.webdav.0,id=spiceport1 -device virtio-serial -device virtserialport,chardev=spiceport1,name=org.spice-space.webdav.0 -device ich9-usb-uhci1 -device usb-tablet"
display_gtk="-display gtk"
display=$display_gtk  # Default display type if not defined

# SOUND
sound_command=""  # Default to no sound

# SHARED FOLDER
shared_folder="$HOME/Public"  # Default shared folder if not defined
share_9p="-fsdev local,security_model=mapped,id=fsdev0,path='${shared_folder}' -device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare"
#share_samba="-net user,smb='${shared_folder}'"
share_samba="-net user,smb=/home/user/Public -net nic,model=virtio"
share=""

# WINDOWS 11 (q35 + Secure Boot UEFI + TPM 2.0, enabled with -win11)
ovmf_code_secboot="/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
ovmf_vars_ms="/usr/share/OVMF/OVMF_VARS_4M.ms.fd"  # Microsoft Secure Boot keys enrolled
win11_memory="4G"  # Windows 11 minimum
win11_smp="4"      # Windows 11 needs at least 2

# Parse command line options
while [[ $# -gt 0 ]]; do
  case $1 in
    -qcow2)
      qcow2_file="$2"
      shift 2
      ;;
    -disk)
      disk="$2"
      shift 2
      ;;
    -iso)
      iso_file="$2"
      shift 2
      ;;
    -memory)
      memory="$2"
      memory_set=1
      shift 2
      ;;
    -smp)
      smp="$2"
      shift 2
      ;;
    -win11)
      win11=1
      shift
      ;;
    -sound)
      #sound_command="-audiodev alsa,id=alsa -device AC97,id=snd0,audiodev=alsa"
      #sound_command="-audiodev pa,id=pa,server=unix:${XDG_RUNTIME_DIR}/pulse/native,out.stream-name=foobar,in.stream-name=foobar -device AC97,audiodev=pa"
      #sound_command="-audiodev pa,id=pa,server=unix:${XDG_RUNTIME_DIR}/pulse/native,out.stream-name=foobar,in.stream-name=foobar -device ich9-intel-hda"
      sound_command="-device ich9-intel-hda -device hda-output,audiodev=pa -audiodev pa,id=pa,server=unix:${XDG_RUNTIME_DIR}/pulse/native"
      shift
      ;;
    -share)
      if [[ $2 == "9p" ]]; then
        share="$share_9p"
      elif [[ $2 == "samba" ]]; then
        share="$share_samba"
      fi
      shift 2
      ;;
    -display)
      if [[ $2 == "spice" ]]; then
        display=$display_spice
      elif [[ $2 == "gtk" ]]; then
        display=$display_gtk
      fi
      shift 2
      ;;
    create)
      read -p "Name of virtual disk: " disk_name
      read -p "Size of virtual disk (GB): " size
      qemu-img create -f qcow2 "${disk_name}.qcow2" "${size}G"
      exit 0
      ;;
    -uefi)
      uefi="-drive if=pflash,format=raw,file=/usr/share/qemu/OVMF.fd"
      #uefi="-drive if=pflash,format=raw,file=/usr/share/ovmf/x64//OVMF.4m.fd"
      #boot_command="boot"
      shift
      ;;
    -test)
      uefi="-drive if=pflash,format=raw,file=/home/user/github/coreboot-rust/bin/qemu_i440fx_8mb/qemu_i440fx_8mb.flash.bin"
      shift
      ;;
    boot)
      boot_command="boot"
      shift
      ;;
    view|client)
      remote-viewer spice://localhost:5900 > /home/user/Public/remote-viewer.log 2>&1
      printf "\\\\10.0.2.4\\qemu\n"
      exit 0
      ;;
    --help|-h|help)
      printf "Usage: $0 [OPTIONS]\n\n"
      printf "OPTIONS:\n"
      printf "  -qcow2 FILE      Specify the QCOW2 image file to use.\n"
      printf "  -disk DEVICE     Specify the disk device (e.g., /dev/sdb).\n"
      printf "  -iso FILE        Specify the ISO image file to boot from.\n"
      printf "  -memory SIZE     Set memory size (default: 2G, or 4G with -win11). Example: 4G, 1024M.\n"
      printf "  -smp N           Number of virtual CPUs (default: 1, or 4 with -win11).\n"
      printf "  -win11           Meet Windows 11 requirements: q35, Secure Boot UEFI, TPM 2.0.\n"
      printf "                   UEFI vars and TPM state are kept in <disk>.win11/ next to the disk.\n"
      printf "  -sound           Enable sound output.\n"
      printf "  -share TYPE      Share folder options: '9p' or 'samba'.\n"
      printf "  -display TYPE    Specify display type: 'spice' or 'gtk' (default: gtk).\n"
      printf "  create           Create a new virtual disk.\n"
      printf "  boot             Boot the VM using specified flags.\n"
      printf "  view             Open the remote-viewer to connect to the VM.\n"
      printf "  --help/-h        Show this help message.\n"
      printf "\nEXAMPLES:\n"
      printf "  $0 create\n"
      printf "  $0 boot -qcow2 Public/test.qcow2 -iso Downloads/Win10_22H2_English_x64.iso -memory 8G -sound -share 9p -display spice\n"
      printf "  $0 boot -win11 -qcow2 win11.qcow2 -iso Downloads/Win11_English_x64.iso\n"
      printf "  $0 view\n"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

# Error checking for boot command
if [[ $boot_command == "boot" ]]; then
  if [[ -z $qcow2_file && -z $disk ]]; then
    echo "Error: You must specify either the -qcow2 flag or the -disk flag when booting."
    exit 1
  fi

  # Set boot options
  if [[ -n $qcow2_file ]]; then
    if [[ $qcow2_file == *.qcow2 ]]; then
      boot="-hda $qcow2_file"  # E.g., disk.qcow2
    elif [[ $qcow2_file == /dev/* ]]; then
      boot="-drive format=raw,file=$qcow2_file"  # E.g., /dev/sdb
    fi
  elif [[ -n $disk ]]; then
    boot="-drive format=raw,file=$disk"  # Use disk directly
  fi

  if [[ -n $iso_file ]]; then
    if [[ $iso_file == *.iso ]]; then
      cdrom="-boot d -cdrom $iso_file"  # E.g., image.iso
    fi
  fi

  # Windows 11: q35 with SMM, Secure Boot firmware, per-VM UEFI vars and a swtpm TPM 2.0
  extra_args=()
  if [[ $win11 == 1 ]]; then
    for f in "$ovmf_code_secboot" "$ovmf_vars_ms"; do
      if [[ ! -f $f ]]; then
        echo "Error: $f not found (Debian/Ubuntu: sudo apt install ovmf)."
        exit 1
      fi
    done
    if ! command -v swtpm > /dev/null; then
      echo "Error: swtpm not found (Debian/Ubuntu: sudo apt install swtpm)."
      exit 1
    fi

    target="${qcow2_file:-$disk}"
    if [[ $target == *.qcow2 ]]; then
      state_dir="${target%.qcow2}.win11"
    else
      state_dir="$HOME/.local/share/qemu-manager/$(basename "$target").win11"  # E.g., /dev/sdb
    fi
    mkdir -p "$state_dir/tpm" || exit 1
    if [[ ! -f $state_dir/vars.fd ]]; then
      cp "$ovmf_vars_ms" "$state_dir/vars.fd" || exit 1
    fi

    # --terminate makes swtpm exit when QEMU disconnects
    if ! swtpm socket --tpm2 --tpmstate dir="$state_dir/tpm" \
        --ctrl type=unixio,path="$state_dir/tpm/sock" --terminate --daemon; then
      echo "Error: could not start swtpm. Is this VM already running?"
      exit 1
    fi

    [[ $memory_set == 1 ]] || memory="$win11_memory"
    [[ -n $smp ]] || smp="$win11_smp"
    uefi=""  # replaced by the Secure Boot firmware below
    extra_args=(
      -machine q35,smm=on
      -global driver=cfi.pflash01,property=secure,value=on
      -drive "if=pflash,format=raw,unit=0,file=$ovmf_code_secboot,readonly=on"
      -drive "if=pflash,format=raw,unit=1,file=$state_dir/vars.fd"
      -chardev "socket,id=chrtpm,path=$state_dir/tpm/sock"
      -tpmdev emulator,id=tpm0,chardev=chrtpm
      -device tpm-tis,tpmdev=tpm0
    )
  fi
  [[ -n $smp ]] && extra_args+=(-smp "$smp")

  # Run QEMU
  qemu-system-x86_64 -enable-kvm -m "$memory" -cpu host "${extra_args[@]}" $boot $cdrom $uefi $display $sound_command $share
  printf "\nqemu-system-x86_64 -enable-kvm -m \"$memory\" -cpu host ${extra_args[*]} $boot $cdrom $uefi $display $sound_command $share\n"
elif [[ -z $boot_command ]]; then
  echo "Error: Please specify 'boot' or 'create'."
  exit 1
fi
