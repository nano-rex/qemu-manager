#Requires -RunAsAdministrator

$memory = 4096

mkdir $HOME\Public

if ($args[0] -eq "create") {
    $disk = Read-Host "Name of virtual disk"
    $size = Read-Host "Size of virtual disk (GB)"
    New-QemuDisk -Format qcow2 -Path "${disk}.qcow2" -Size ${size}GB
}
elseif ($args[0] -eq "boot") {
    if ($args[1] -like "*.qcow2") {
        $boot = "-hda $args[1]" #Eg: disk.qcow2
    }
    elseif ($args[1] -like "/dev/*") {
        $boot = "-drive format=raw,file=$args[1]" #Eg: /dev/sdb
    }
    else {
        $boot = ""
    }
    if ($args[2] -like "*.iso") {
        $cdrom = "-boot d -cdrom $args[2]" #Eg: image.iso
    }
    else {
        $cdrom = ""
    }
    Start-QemuSystem -EnableKvm $boot $cdrom -Memory $memory -Cpu host -Fsdev @{SecurityModel="mapped";Id="fsdev0";Path="$HOME\Public"} -Device @{Driver="virtio-9p-pci";Id="fs0";Fsdev="fsdev0";MountTag="hostshare"}
}
elseif ($args[0] -eq "--help" -or $args[0] -eq "") {
    Write-Host "Examples:"
    Write-Host "$($MyInvocation.MyCommand.Name) boot disk.qcow2 image.iso"
    Write-Host "$($MyInvocation.MyCommand.Name) boot /dev/sdb"
    Write-Host "$($MyInvocation.MyCommand.Name) boot create"
}
