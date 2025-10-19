#!/bin/bash
#Automatic Hugepages 
################################################################################
# Plugin metadata (new format)
# menu_title = "Setup Hugepages for VM"
# menu_function = "auto_huge" 
# menu_order = 
# menu_category = 0
###############################################################################



configure_hugepages() {
    local fstab_entry="hugetlbfs /dev/hugepages hugetlbfs mode=01770,gid=kvm 0 0"

    # Use dialog to ask the user for the memory size in GB
    memory_gb=$(dialog --stdout --inputbox "Enter the amount of memory to allocate for HugePages (in GB):" 0 0)
    
    # Validate input
    if [[ -z "$memory_gb" || ! "$memory_gb" =~ ^[0-9]+$ ]]; then
        dialog --msgbox "Error: Please provide a valid memory size in GB." 0 0
        return 1
    fi

    # Ask the user to choose between 1 MB and 2 MB HugePages
    page_size_choice=$(dialog --stdout --menu "Choose HugePage size:" 0 0 0 \
        1 "1 MB HugePages" \
        2 "2 MB HugePages")

    # Set the HugePage size based on the user's choice
    if [[ "$page_size_choice" == "1" ]]; then
        page_size_kb=1024 # 1 MB
        page_size_mb=1
    else
        page_size_kb=2048 # 2 MB
        page_size_mb=2
    fi

    # Calculate the required number of HugePages
    local memory_kb=$((memory_gb * 1024 * 1024))
    required_pages=$((memory_kb / page_size_kb))
    
    # Display the result using dialog
    dialog --msgbox "Configuring HugePages for ${memory_gb} GB memory using ${page_size_mb} MB HugePages...\nHugePages required: $required_pages" 0 0
}

hook_config() {
    # Check if required_pages is set
    if [[ -z "$required_pages" ]]; then
        dialog --msgbox "Error: HugePages calculation not done. Please run 'configure_hugepages' first." 0 0
        return 1
    fi

    # Ask the user for the VM name using dialog
    vm_name=$(dialog --stdout --inputbox "Enter the name of the VM to allocate HugePages for:" 0 0)

    # Validate VM name input
    if [[ -z "$vm_name" ]]; then
        dialog --msgbox "Error: Please provide a valid VM name." 0 0
        return 1
    fi

    # Write the kvm.conf file in the ./hooks folder
    cat <<EOF > ./hooks/kvm.conf
## Virtual Machine
VM_NAME=$vm_name
MEMORY=$required_pages
EOF

    # Display the contents of the kvm.conf file using dialog
    dialog --title "kvm.conf Created Successfully" --msgbox "The following configuration has been written to ./hooks/kvm.conf:\n\nVM_NAME=$vm_name\nMEMORY=$required_pages" 0 0
}

update_qemu_file() {
    # Check if required_pages is set
    if [[ -z "$required_pages" ]]; then
        dialog --msgbox "Error: HugePages calculation not done. Please run 'configure_hugepages' first." 0 0
        return 1
    fi

    # Validate VM name input
    if [[ -z "$vm_name" ]]; then
        dialog --msgbox "Error: Please provide a valid VM name." 0 0
        return 1
    fi

    # Define the new block to add for the VM
    new_block=$(cat <<EOF
if [[ \$OBJECT == "$vm_name" ]]; then
    case "\$OPERATION" in
        "prepare")
            systemctl start libvirt-nosleep@"$vm_name"  2>&1 | tee -a /var/log/libvirt/custom_hooks.log
            /bin/alloc_hugepages.sh 2>&1 | tee -a /var/log/libvirt/custom_hooks.log
            ;;

        "release")
            systemctl stop libvirt-nosleep@"$vm_name"  2>&1 | tee -a /var/log/libvirt/custom_hooks.log
            /bin/dealloc_hugepages.sh 2>&1 | tee -a /var/log/libvirt/custom_hooks.log
            ;;
    esac
fi
EOF
    )

    # Check if the qemu file exists in the hooks folder
    if [[ ! -f ./hooks/qemu ]]; then
        # Create the qemu file with the initial shebang and instructions
        cat <<EOF > ./hooks/qemu
#!/bin/bash

# IMPORTANT! If you want to add more VMs with different names, copy the if/fi block below as is and change "win10" to the name of the VM.
OBJECT="\$1"
OPERATION="\$2"

$new_block
EOF
    else
        # Append the new block to the existing qemu file
        echo "$new_block" >> ./hooks/qemu
    fi

    # Make the qemu file executable
    chmod +x ./hooks/qemu

    # Notify the user
    dialog --title "qemu Hook Updated" --msgbox "A new block for VM '$vm_name' has been added to ./hooks/qemu." 0 0
}

install_hooks() {
    # Backup existing dealloc_hugepages.sh if it exists
    if test -e /bin/dealloc_hugepages.sh; then
        mv /bin/dealloc_hugepages.sh /bin/dealloc_hugepages.sh.bkp
    fi

    # Remove existing libvirt-nosleep service if it exists
    if test -e /etc/systemd/system/libvirt-nosleep@.service; then
        rm /etc/systemd/system/libvirt-nosleep@.service
    fi

    # Copy necessary files to their respective locations
    mkdir -p /etc/libvirt/hooks
    cp systemd-no-sleep/libvirt-nosleep@.service /etc/systemd/system/libvirt-nosleep@.service
    cp hooks/alloc_hugepages.sh /bin/alloc_hugepages.sh
    cp hooks/dealloc_hugepages.sh /bin/dealloc_hugepages.sh
    cp hooks/qemu /etc/libvirt/hooks/qemu
    cp hooks/kvm.conf /etc/libvirt/hooks/kvm.conf

    # Set executable permissions on the scripts
    chmod +x /bin/alloc_hugepages.sh
    chmod +x /bin/dealloc_hugepages.sh
    chmod +x /etc/libvirt/hooks/qemu
    
    dialog --msgbox "Hooks installed successfully!" 0 0
    return 0
}

auto_huge(){
    #Main Body of script
    configure_hugepages
    hook_config
    update_qemu_file
    install_hooks
}

