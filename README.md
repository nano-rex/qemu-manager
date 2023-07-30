# Qemu-Manager

## Quick deploy virtual machine from the terminal

### Examples:

#### Create a new virtual machine
- this will generate a new .qcow2 file

``qemu-manager create``

#### Installing OS to the created virtual machine
``qemu-manager boot VM.qcow2 OS.iso``

#### Run the virtual machine
``qemu-manager boot VM.qcow2``

#### Run external disk as virtual machine
- this can be useful when troubleshooting an OS booting on another disk

``sudo qemu-manager boot /dev/sdb  # don't specify the partition Eg:sdb1 as you want to boot into the entire disk``
