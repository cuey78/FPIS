#!/bin/bash
# Automatic Hugepages for Multiple VMs
################################################################################
# Plugin metadata
# menu_title = "Setup Hugepages for VMs"
# menu_function = "auto_huge" 
# menu_order = 
# menu_category = 0
###############################################################################

# Global arrays to store VM configurations
declare -A vm_configs
declare -a vm_names

configure_hugepages() {
    # Use dialog to ask the user for VM name and memory
    vm_name=$(dialog --stdout --inputbox "Enter the name of the VM:" 0 0)
    if [[ -z "$vm_name" ]]; then
        dialog --msgbox "Error: Please provide a valid VM name." 0 0
        return 1
    fi

    memory_gb=$(dialog --stdout --inputbox "Enter the amount of memory to allocate for HugePages for $vm_name (in GB):" 0 0)
    
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
    
    # Store configuration in arrays
    vm_names+=("$vm_name")
    vm_configs["${vm_name}_pages"]=$required_pages
    vm_configs["${vm_name}_memory"]=$memory_gb
    
    dialog --msgbox "Configuration added for VM: $vm_name\nMemory: ${memory_gb} GB\nHugePages required: $required_pages" 0 0
}

create_kvm_config() {
    if [[ ${#vm_names[@]} -eq 0 ]]; then
        dialog --msgbox "Error: No VMs configured. Please add VMs first." 0 0
        return 1
    fi

    # Create kvm.conf with all VM configurations
    cat <<EOF > /etc/libvirt/hooks/kvm.conf
# Multiple VM HugePages Configuration
# Format: VM_NAME:PAGES

EOF

    # Add each VM configuration
    for vm in "${vm_names[@]}"; do
        pages=${vm_configs["${vm}_pages"]}
        echo "${vm}:${pages}" >> /etc/libvirt/hooks/kvm.conf
    done

    # Show summary
    summary="The following configuration has been written to /etc/libvirt/hooks/kvm.conf:\n\n"
    for vm in "${vm_names[@]}"; do
        pages=${vm_configs["${vm}_pages"]}
        memory=${vm_configs["${vm}_memory"]}
        summary+="VM: $vm - Memory: ${memory}GB - Pages: $pages\n"
    done
    
    dialog --title "kvm.conf Created Successfully" --msgbox "$summary" 0 0
}

create_nosleep_service() {
    # Create the nosleep service file (same as before)
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

check_vm_running() {
    local target_vm="$1"
    
    # Check if any other configured VM is running
    for vm in "${vm_names[@]}"; do
        if [[ "$vm" != "$target_vm" ]]; then
            # Check if VM is running using virsh
            if virsh list --state-running --name | grep -q "^${vm}$"; then
                echo "$vm"
                return 0
            fi
        fi
    done
    echo ""
    return 1
}

setup_libvirt_hooks() {
    if [[ ${#vm_names[@]} -eq 0 ]]; then
        dialog --msgbox "Error: No VMs configured. Please add VMs first." 0 0
        return 1
    fi

    # Create hook structure for each VM
    for vm_name in "${vm_names[@]}"; do
        # Create the proper libvirt hooks directory structure
        mkdir -p /etc/libvirt/hooks/qemu.d/$vm_name/prepare/begin
        mkdir -p /etc/libvirt/hooks/qemu.d/$vm_name/release/end

        # Create the alloc script with VM conflict checking
        cat <<EOF > /etc/libvirt/hooks/qemu.d/$vm_name/prepare/begin/alloc_hugepages.sh
#!/bin/bash

# Load the config file
if [[ -f "/etc/libvirt/hooks/kvm.conf" ]]; then
    source "/etc/libvirt/hooks/kvm.conf"
else
    echo "ERROR: kvm.conf not found!" >&2
    exit 1
fi

# Function to get pages for a VM
get_vm_pages() {
    local vm="\$1"
    while IFS=: read -r config_vm config_pages; do
        if [[ "\$config_vm" == "\$vm" ]]; then
            echo "\$config_pages"
            return 0
        fi
    done < /etc/libvirt/hooks/kvm.conf
}

# Only run for our specific VM
if [[ "\$1" != "$vm_name" ]]; then
    exit 0
fi

echo "\$(date): Allocating hugepages for VM: $vm_name" >> /var/log/libvirt/hooks.log

# Check if any other configured VM is running
CONFLICT_VM=""
for vm in "\${!vm_configs[@]}"; do
    if [[ "\$vm" != "$vm_name" ]]; then
        if virsh list --state-running --name | grep -q "^\$vm$"; then
            CONFLICT_VM="\$vm"
            break
        fi
    fi
done

if [[ -n "\$CONFLICT_VM" ]]; then
    echo "\$(date): ERROR: Cannot start $vm_name - VM \$CONFLICT_VM is already running!" >> /var/log/libvirt/hooks.log
    echo "ERROR: VM \$CONFLICT_VM is already running. Only one VM can run at a time with hugepages." >&2
    exit 1
fi

# Get pages for this VM
HUGEPAGES=\$(get_vm_pages "$vm_name")

if [[ -z "\$HUGEPAGES" ]]; then
    echo "\$(date): ERROR: No hugepages configuration found for $vm_name" >> /var/log/libvirt/hooks.log
    exit 1
fi

echo "\$(date): Allocating \$HUGEPAGES hugepages (2MB each) for $vm_name..." >> /var/log/libvirt/hooks.log

# Drop caches to free up memory
echo 3 > /proc/sys/vm/drop_caches

# Allocate hugepages
echo \$HUGEPAGES > /proc/sys/vm/nr_hugepages
ALLOC_PAGES=\$(cat /proc/sys/vm/nr_hugepages)

TRIES=0
while [[ \$ALLOC_PAGES -lt \$HUGEPAGES ]] && [[ \$TRIES -lt 30 ]]
do
    echo "\$(date): Attempt \$((TRIES + 1)): Allocated \$ALLOC_PAGES / \$HUGEPAGES hugepages" >> /var/log/libvirt/hooks.log
    
    # Try to compact memory and clear caches
    echo 1 > /proc/sys/vm/compact_memory
    echo 3 > /proc/sys/vm/drop_caches
    sleep 1
    
    # Retry allocation
    echo \$HUGEPAGES > /proc/sys/vm/nr_hugepages
    ALLOC_PAGES=\$(cat /proc/sys/vm/nr_hugepages)
    
    let TRIES+=1
done

if [[ \$ALLOC_PAGES -lt \$HUGEPAGES ]]
then
    echo "\$(date): ERROR: Only allocated \$ALLOC_PAGES / \$HUGEPAGES hugepages after \$TRIES attempts" >> /var/log/libvirt/hooks.log
    echo "Reverting allocation..."
    echo 0 > /proc/sys/vm/nr_hugepages
    exit 1
fi

echo "\$(date): Successfully allocated \$ALLOC_PAGES hugepages for $vm_name!" >> /var/log/libvirt/hooks.log
echo "HugePages_Total: \$ALLOC_PAGES" >> /var/log/libvirt/hooks.log
EOF

        # Create the dealloc script
        cat <<EOF > /etc/libvirt/hooks/qemu.d/$vm_name/release/end/dealloc_hugepages.sh
#!/bin/bash

# Only run for our specific VM
if [[ "\$1" != "$vm_name" ]]; then
    exit 0
fi

echo "\$(date): Deallocating hugepages for VM: $vm_name" >> /var/log/libvirt/hooks.log
echo 0 > /proc/sys/vm/nr_hugepages
echo "\$(date): Hugepages deallocated for $vm_name" >> /var/log/libvirt/hooks.log
EOF

        # Make scripts executable
        chmod +x /etc/libvirt/hooks/qemu.d/$vm_name/prepare/begin/alloc_hugepages.sh
        chmod +x /etc/libvirt/hooks/qemu.d/$vm_name/release/end/dealloc_hugepages.sh

        echo "Libvirt hooks configured for VM: $vm_name"
    done

    dialog --msgbox "Libvirt hooks configured for all VMs: ${vm_names[*]}" 0 0
}

create_main_qemu_hook() {
    # Create the main qemu hook file (same as before)
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

add_more_vms() {
    while true; do
        dialog --yesno "Do you want to add another VM configuration?" 0 0
        if [[ $? -eq 0 ]]; then
            configure_hugepages || break
        else
            break
        fi
    done
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

    # Setup libvirt hooks structure for all VMs
    setup_libvirt_hooks
    
    # Reload systemd and restart libvirt to ensure hooks are loaded
    systemctl daemon-reload
    systemctl restart libvirtd
    
    # Show final summary
    summary="Hooks installed successfully!\n\nConfigured VMs:\n"
    for vm in "${vm_names[@]}"; do
        pages=${vm_configs["${vm}_pages"]}
        memory=${vm_configs["${vm}_memory"]}
        summary+="• $vm: ${memory}GB ($pages pages)\n"
    done
    summary+="\nNote: Only one VM can run at a time to prevent hugepages conflicts."
    
    dialog --msgbox "$summary" 0 0
}

auto_huge() {
    # Clear any previous configurations
    declare -gA vm_configs
    declare -ga vm_names
    vm_configs=()
    vm_names=()
    
    # Configure first VM
    configure_hugepages || return 1
    
    # Ask if user wants to add more VMs
    add_more_vms
    
    # Proceed with installation
    install_hooks
}
