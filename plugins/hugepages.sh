#!/bin/bash
# Automatic Hugepages 
################################################################################
# Plugin metadata
# menu_title = "Setup Hugepages for VM"
# menu_function = "auto_huge" 
# menu_order = 
# menu_category = 0
###############################################################################

configure_hugepages() {
    # Use dialog to ask the user for the memory size in GB
    memory_gb=$(dialog --stdout --inputbox "Enter the amount of memory to allocate for HugePages (in GB):" 0 0)
    
    # Validate input
    if [[ -z "$memory_gb" || ! "$memory_gb" =~ ^[0-9]+$ ]]; then
        dialog --msgbox "Error: Please provide a valid memory size in GB." 0 0
        return 1
    fi

    # Calculate required pages for 2MB hugepages (2048KB per page)
    local memory_kb=$((memory_gb * 1024 * 1024))
    required_pages=$((memory_kb / 2048))
    
    # Add 10% buffer for safety
    required_pages=$((required_pages + (required_pages / 10)))
    
    dialog --msgbox "Configuring HugePages for ${memory_gb} GB memory using 2MB HugePages...\nHugePages required: $required_pages" 0 0
}

create_kvm_config() {
    if [[ -z "$required_pages" || -z "$vm_name" ]]; then
        dialog --msgbox "Error: Configuration incomplete. Please run previous steps first." 0 0
        return 1
    fi

    # Create kvm.conf directly in /etc/libvirt/hooks/
    cat <<EOF > /etc/libvirt/hooks/kvm.conf
## Virtual Machine
VM_NAME=$vm_name
MEMORY=$required_pages
EOF

    dialog --title "kvm.conf Created Successfully" --msgbox "The following configuration has been written to /etc/libvirt/hooks/kvm.conf:\n\nVM_NAME=$vm_name\nMEMORY=$required_pages" 0 0
}

create_nosleep_service() {
    # Create the nosleep service file
    cat <<'EOF' > /etc/systemd/system/libvirt-nosleep@.service
[Unit]
Description=Prevent sleep for VM %i
Before=sleep.target

[Service]
Type=simple
ExecStart=/usr/bin/systemd-inhibit --what=sleep --who="libvirt" --why="VM %i running" --mode=block sleep infinity

[Install]
WantedBy=multi-user.target
EOF

    dialog --msgbox "Nosleep service created successfully" 0 0
}

setup_libvirt_hooks() {
    if [[ -z "$vm_name" ]]; then
        dialog --msgbox "Error: VM name not set. Please run previous steps first." 0 0
        return 1
    fi

    # Create the proper libvirt hooks directory structure
    mkdir -p /etc/libvirt/hooks/qemu.d/$vm_name/prepare/begin
    mkdir -p /etc/libvirt/hooks/qemu.d/$vm_name/release/end

    # Create the alloc script
    cat <<'EOF' > /etc/libvirt/hooks/qemu.d/$vm_name/prepare/begin/alloc_hugepages.sh
#!/bin/bash

# Load the config file
if [[ -f "/etc/libvirt/hooks/kvm.conf" ]]; then
    source "/etc/libvirt/hooks/kvm.conf"
else
    echo "ERROR: kvm.conf not found!" >&2
    exit 1
fi

# Only run for our specific VM
if [[ "$1" != "$VM_NAME" ]]; then
    exit 0
fi

echo "$(date): Allocating hugepages for VM: $VM_NAME" >> /var/log/libvirt/hooks.log

# Use the pre-calculated value directly
HUGEPAGES=$MEMORY

echo "$(date): Allocating $HUGEPAGES hugepages (2MB each)..." >> /var/log/libvirt/hooks.log

# Drop caches to free up memory
echo 3 > /proc/sys/vm/drop_caches

# Allocate hugepages
echo $HUGEPAGES > /proc/sys/vm/nr_hugepages
ALLOC_PAGES=$(cat /proc/sys/vm/nr_hugepages)

TRIES=0
while [[ $ALLOC_PAGES -lt $HUGEPAGES ]] && [[ $TRIES -lt 30 ]]
do
    echo "$(date): Attempt $((TRIES + 1)): Allocated $ALLOC_PAGES / $HUGEPAGES hugepages" >> /var/log/libvirt/hooks.log
    
    # Try to compact memory and clear caches
    echo 1 > /proc/sys/vm/compact_memory
    echo 3 > /proc/sys/vm/drop_caches
    sleep 1
    
    # Retry allocation
    echo $HUGEPAGES > /proc/sys/vm/nr_hugepages
    ALLOC_PAGES=$(cat /proc/sys/vm/nr_hugepages)
    
    let TRIES+=1
done

if [[ $ALLOC_PAGES -lt $HUGEPAGES ]]
then
    echo "$(date): ERROR: Only allocated $ALLOC_PAGES / $HUGEPAGES hugepages after $TRIES attempts" >> /var/log/libvirt/hooks.log
    echo "Reverting allocation..."
    echo 0 > /proc/sys/vm/nr_hugepages
    exit 1
fi

echo "$(date): Successfully allocated $ALLOC_PAGES hugepages!" >> /var/log/libvirt/hooks.log
echo "HugePages_Total: $ALLOC_PAGES" >> /var/log/libvirt/hooks.log
EOF

    # Create the dealloc script
    cat <<'EOF' > /etc/libvirt/hooks/qemu.d/$vm_name/release/end/dealloc_hugepages.sh
#!/bin/bash

# Load the config file
if [[ -f "/etc/libvirt/hooks/kvm.conf" ]]; then
    source "/etc/libvirt/hooks/kvm.conf"
else
    echo "ERROR: kvm.conf not found!" >&2
    exit 1
fi

# Only run for our specific VM
if [[ "$1" != "$VM_NAME" ]]; then
    exit 0
fi

echo "$(date): Deallocating hugepages for VM: $VM_NAME" >> /var/log/libvirt/hooks.log
echo 0 > /proc/sys/vm/nr_hugepages
echo "$(date): Hugepages deallocated" >> /var/log/libvirt/hooks.log
EOF

    # Make scripts executable
    chmod +x /etc/libvirt/hooks/qemu.d/$vm_name/prepare/begin/alloc_hugepages.sh
    chmod +x /etc/libvirt/hooks/qemu.d/$vm_name/release/end/dealloc_hugepages.sh

    dialog --msgbox "Libvirt hooks configured for VM: $vm_name" 0 0
}

create_main_qemu_hook() {
    # Create the main qemu hook file that libvirt will call
    cat <<'EOF' > /etc/libvirt/hooks/qemu
#!/bin/bash

# Main libvirt hook script
# This gets called by libvirt and dispatches to scripts in qemu.d

OBJECT="$1"
OPERATION="$2"
SUBOPERATION="$3"

# Log hook call
echo "$(date): Hook called: $OBJECT $OPERATION $SUBOPERATION" >> /var/log/libvirt/hooks.log

# Execute scripts in the appropriate qemu.d directory
if [[ -n "$OBJECT" && -n "$OPERATION" && -n "$SUBOPERATION" ]]; then
    HOOK_DIR="/etc/libvirt/hooks/qemu.d/$OBJECT/$OPERATION/$SUBOPERATION"
    
    if [[ -d "$HOOK_DIR" ]]; then
        for script in "$HOOK_DIR"/*; do
            if [[ -x "$script" ]]; then
                echo "$(date): Executing hook: $script" >> /var/log/libvirt/hooks.log
                "$script" "$@" &
            fi
        done
    fi
    
    # Nosleep service control for all VMs
    case "$OPERATION" in
        "prepare")
            echo "$(date): Starting nosleep service for $OBJECT" >> /var/log/libvirt/hooks.log
            systemctl start libvirt-nosleep@"$OBJECT" 2>/dev/null || echo "$(date): Nosleep service not available for $OBJECT" >> /var/log/libvirt/hooks.log
            ;;
        "release")  
            echo "$(date): Stopping nosleep service for $OBJECT" >> /var/log/libvirt/hooks.log
            systemctl stop libvirt-nosleep@"$OBJECT" 2>/dev/null || echo "$(date): Nosleep service not available for $OBJECT" >> /var/log/libvirt/hooks.log
            ;;
    esac
fi

# Wait for background processes
wait
EOF

    chmod +x /etc/libvirt/hooks/qemu
    dialog --msgbox "Main qemu hook created successfully" 0 0
}

install_hooks() {
    # Create necessary directories
    mkdir -p /etc/libvirt/hooks
    mkdir -p /var/log/libvirt
    
    # Create log file with proper permissions
    touch /var/log/libvirt/hooks.log
    chmod 666 /var/log/libvirt/hooks.log

    # Create kvm config
    create_kvm_config

    # Create nosleep service
    create_nosleep_service

    # Create main qemu hook
    create_main_qemu_hook

    # Setup libvirt hooks structure for the VM
    setup_libvirt_hooks
    
    # Reload systemd and restart libvirt to ensure hooks are loaded
    systemctl daemon-reload
    systemctl restart libvirtd
    
    dialog --msgbox "Hooks installed successfully!\n\nVM: $vm_name\nHugePages: $required_pages\nNosleep Service: Enabled\n\nLibvirt restarted to load new hooks." 0 0
}

auto_huge() {
    configure_hugepages || return 1
    
    # Get VM name here since we removed hook_config()
    vm_name=$(dialog --stdout --inputbox "Enter the name of the VM to allocate HugePages for:" 0 0)
    if [[ -z "$vm_name" ]]; then
        dialog --msgbox "Error: Please provide a valid VM name." 0 0
        return 1
    fi
    
    install_hooks
}
