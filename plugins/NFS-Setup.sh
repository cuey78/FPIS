#!/bin/bash

################################################################################
# Plugin metadata (new format)
# menu_title = "Network File System (NFS) Configuration"
# menu_function = "nfs_setup" 
# menu_order = 600
# menu_category = 1
###############################################################################

# Check and install nfs-utils if not present (Fedora)
check_install_nfs_utils() {
    echo "Checking for NFS utilities..."
    
    # Check if nfs-utils is installed
    if command -v showmount &> /dev/null; then
        echo "NFS utilities are already installed."
        return 0
    fi
    
    echo "NFS utilities are not installed. This package is required for NFS configuration."
    
    # Prompt user to install nfs-utils
    if dialog --yesno "NFS utilities (nfs-utils) are required but not installed.\n\nDo you want to install them now?" 10 60; then
    	clear
        echo "Installing nfs-utils package..."
        if sudo dnf install -y nfs-utils; then
            dialog --msgbox "nfs-utils installed successfully!" 8 40
            return 0
        else
            dialog --msgbox "Failed to install nfs-utils. Please check your network connection and try again." 8 60
            return 1
        fi
    else
        dialog --msgbox "NFS utilities are required to continue. Exiting NFS configuration." 8 50
        return 1
    fi
}

# Enhanced version that returns success/failure
check_nfs_dependencies() {
    if command -v showmount &> /dev/null; then
        return 0
    else
        return 1
    fi
}

#Scans for Wifi Networks
setup_wifi_nfs_shares() {
    # Check dependencies at the start of each function
    if ! check_nfs_dependencies; then
        dialog --msgbox "NFS utilities are not available. Please install nfs-utils first." 8 50
        return 1
    fi

# Check if Wi-Fi is enabled and working
check_wifi_adapter() {
    if ! nmcli radio wifi | grep -q "enabled"; then
        dialog --yesno "Wi-Fi is currently disabled. Would you like to enable it?" 8 50
        if [ $? -eq 0 ]; then
            nmcli radio wifi on
            sleep 2
        else
            return 1
        fi
    fi
    
    # Check if any Wi-Fi adapter is available
    if ! nmcli dev status | grep -q "wifi"; then
        dialog --msgbox "No Wi-Fi adapter found. Please check your hardware." 8 50
        return 1
    fi
    return 0
}
scan_and_select_wifi() {
    WIFI_SSID=""
    
    # Check Wi-Fi adapter first
    if ! check_wifi_adapter; then
        return 1
    fi
    
    dialog --infobox "Scanning for available Wi-Fi networks...\nThis may take a few seconds." 10 50
    sleep 1
    
    # Multiple scan attempts with forced rescan
    for attempt in 1 2 3; do
        sudo nmcli dev wifi rescan 2>/dev/null
        sleep 3  # Give more time for scanning
        
        AVAILABLE_SSIDS=$(nmcli -t -f SSID,SIGNAL dev wifi list | sort -r -t: -k2 | cut -d: -f1 | grep -v '^$' | sort -u)
        
        if [ -n "$AVAILABLE_SSIDS" ]; then
            break
        fi
        
        if [ $attempt -lt 3 ]; then
            dialog --infobox "Scan attempt $attempt failed, retrying..." 5 50
            sleep 2
        fi
    done

    if [ -z "$AVAILABLE_SSIDS" ]; then
        dialog --msgbox "No Wi-Fi networks found after multiple attempts.\n\nPossible reasons:\n• Wi-Fi adapter disabled\n• No networks in range\n• Driver issues\n• Airplane mode enabled" 12 60
        return 1
    fi

    # Prepare list for dialog with signal strength
    SSID_LIST=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            SSID_LIST+=("$line" "$line" OFF)
        fi
    done <<< "$AVAILABLE_SSIDS"

    WIFI_SSID=$(dialog --radiolist "Available Wi-Fi networks (sorted by signal strength):" 20 60 15 "${SSID_LIST[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$WIFI_SSID" ]; then
        dialog --infobox "No selection made. Exiting..." 10 50
        sleep 1
        return 1
    else
        dialog --infobox "Selected Wi-Fi SSID: $WIFI_SSID" 10 50
        sleep 1
    fi
}

    # Function to update the nfs1.sh script
    update_nfs_script() {
        local wifi_ssid="$1"
        local remote_server="$2"
        local nfs_shares=("${!3}")
        local mount_points=("${!4}")
        local script_path="./service/nfs1.sh"

        if [ -z "$wifi_ssid" ] || [ -z "$remote_server" ]; then
            echo "Error: Wi-Fi SSID or remote server IP is null or empty." >&2
            return 1
        fi

        # Temporary file to store the new content
        local temp_script="${script_path}.tmp"

        # Read the existing content of the nfs1.sh script, excluding any previous variable definitions
        local existing_content=$(grep -vE '^WIFI_SSID=|^REMOTE_SERVER=|^REMOTESHARE_|^LOCALMOUNT_' "$script_path")

        # Write the new variables at the top of the temporary script
        {   echo "#!/bin/bash"
            echo "num_shares=\"$num_shares\""
            echo "WIFI_SSID=\"$wifi_ssid\""
            echo "REMOTE_SERVER=\"$remote_server\""
            for (( j=0; j<${#nfs_shares[@]}; j++ )); do
                echo "REMOTESHARE_$((j+1))=\"${nfs_shares[j]}\""
                echo "LOCALMOUNT_$((j+1))=\"${mount_points[j]}\""
            done
            # Append the rest of the original script
            echo "$existing_content"
        } > "$temp_script"

        mv "$temp_script" "$script_path"
    }

    # Main function to handle Wi-Fi NFS Shares setup
    wifi_nfs_shares() {
        echo "Enable Wi-Fi NFS Shares"
        clear # Clear the screen

        # Scan and select Wi-Fi
        scan_and_select_wifi
        if [ -n "$WIFI_SSID" ]; then
            echo "Continuing with selected Wi-Fi SSID: $WIFI_SSID"
        else
            echo "No Wi-Fi SSID selected. Exiting setup..."
            return
        fi

        # Prompt the user for the IP of the server using dialog and check if it is not empty
        while true; do
            REMOTE_SERVER=$(dialog --inputbox "Enter NFS server address (IP or hostname):" 8 40 3>&1 1>&2 2>&3)
            if [ -z "$REMOTE_SERVER" ]; then
                dialog --no-cancel --msgbox "IP address cannot be empty. Please enter a valid IP." 8 40
            else
                break
            fi
        done

        # Discover available NFS shares using showmount -e
        dialog --infobox "Discovering NFS shares on ${REMOTE_SERVER}..." 5 50
        sleep 1

        # Get available exports
        available_shares=$(showmount -e "$REMOTE_SERVER" 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$available_shares" ]; then
            dialog --msgbox "Failed to discover NFS shares on ${REMOTE_SERVER}. Please check the server address and ensure NFS services are running." 8 60
            return 1
        fi

        # Parse the showmount output (skip the first line which is header and filter out "Export list" line)
        shares_list=()
        while IFS= read -r line; do
            # Skip lines containing "export list" or "Export list"
            if [[ $line == *"export list"* ]] || [[ $line == *"Export list"* ]]; then
                continue
            fi
            # Extract share path (first field) and skip empty lines
            share_path=$(echo "$line" | awk '{print $1}')
            if [[ -n "$share_path" ]]; then
                shares_list+=("$share_path" "" "off")
            fi
        done <<< "$available_shares"

        if [ ${#shares_list[@]} -eq 0 ]; then
            dialog --msgbox "No NFS shares found on ${REMOTE_SERVER}." 8 40
            return 1
        fi

        # Present checklist of available shares
        selected_shares=$(dialog --cancel-label "Exit" --checklist "Select NFS shares to mount from ${REMOTE_SERVER}:" 20 60 10 "${shares_list[@]}" 3>&1 1>&2 2>&3)
        
        # Check if user pressed Cancel or Escape
        if [ $? -ne 0 ] || [[ -z "$selected_shares" ]]; then
            dialog --msgbox "Operation cancelled. No shares were selected." 8 40
            return 1
        fi

        # Process selected shares
        IFS=' ' read -ra selected_share_array <<< "$selected_shares"
        num_shares=${#selected_share_array[@]}
        
        nfs_shares=()
        mount_points=()

        for share in "${selected_share_array[@]}"; do
            # Remove quotes from the selected share
            share=$(echo "$share" | sed "s/\"//g")
            
            # Suggest a default mount point based on share name
            default_mount_point="/mnt/nfs/$(basename "$share")"
            
            # Prompt for mount point with suggestion
            mount_point=$(dialog --cancel-label "Skip" --inputbox "Enter mount point for ${share}:" 8 60 "$default_mount_point" 3>&1 1>&2 2>&3)
            
            # Check if user pressed Cancel or Escape
            if [ $? -ne 0 ] || [[ -z "$mount_point" ]]; then
                dialog --msgbox "Skipping ${share}." 5 40
                continue
            fi

            # Create the mount point directory if it doesn't exist
            if [ ! -d "${mount_point}" ]; then
                mkdir -p "${mount_point}"
                dialog --infobox "Created mount point directory ${mount_point}" 0 0
                sleep 1
            else
                dialog --infobox "Mount point directory ${mount_point} already exists" 0 0
                sleep 1
            fi

            nfs_shares+=("$share")
            mount_points+=("$mount_point")
        done

        # Check if we have any shares left after potential skips
        if [ ${#nfs_shares[@]} -eq 0 ]; then
            dialog --msgbox "No shares were configured. Operation cancelled." 8 40
            return 1
        fi

        # Update the actual number of shares after potential skips
        num_shares=${#nfs_shares[@]}

        # Update the nfs1.sh script with the new values
        update_nfs_script "$WIFI_SSID" "$REMOTE_SERVER" nfs_shares[@] mount_points[@]

        dialog --infobox "All specified NFS shares have been added to the nfs script." 0 0
        sleep 1

        # Message indicating that Wi-Fi shares will be active on the next reboot
        dialog --infobox "Wi-Fi Shares Active on Next Reboot" 0 0

        sleep 2
        # Install Service
        cp ./service/nfs-start.service /etc/systemd/system/
        cp ./service/nfs1.sh /usr/bin/
        chmod +x /usr/bin/nfs1.sh
        systemctl enable nfs-start.service
    }

    # Call the main function
    wifi_nfs_shares
}


# Setup NFS shares via FSTAB with showmount discovery
nfs_shares_via_fstab() {
    # Check dependencies at the start of each function
    if ! check_nfs_dependencies; then
        dialog --msgbox "NFS utilities are not available. Please install nfs-utils first." 8 50
        return 1
    fi
    
    echo "NFS Shares Via FSTAB (Wired Only)"
    # Connect NFS Shares VIA FSTAB
    clear
    echo "NFS Shares Via FSTAB (WIRED ONLY)"
    
    # Function to remove ALL control characters and ANSI codes
    clean_string() {
        echo "$1" | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b\][0-9;]*//g' -e 's/[\x00-\x1F\x7F]//g' -e 's/\r//g' | tr -d '\000-\037\177'
    }
    
    # Function specifically for dialog display
    clean_for_dialog() {
        echo "$1" | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b\][0-9;]*//g' -e 's/[\x00-\x1F\x7F]//g' -e 's/\r//g' | tr -cd '[:print:]'
    }
    
    # NEW: Function specifically for mount point names - very aggressive cleaning
    clean_for_mountpoint() {
        echo "$1" | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b\][0-9;]*//g' -e 's/[\x00-\x1F\x7F]//g' -e 's/\r//g' \
                        -e 's/[^a-zA-Z0-9._-]//g' -e 's/^[-._]*//' -e 's/[-._]*$//' | head -c 30
    }
    
    # Initialize variables
    local nfs_server=""
    local available_shares=""
    local shares_list=()
    local selected_shares=""
    local selected_share_array=()
    local share=""
    local clean_share_name=""
    local default_mount_point=""
    local mount_point=""
    local full_nfs_share=""
    
    add_to_fstab() {
        local nfs_share=$1
        local mount_point=$2
        local options="rw,sync,hard,intr,rsize=8192,wsize=8192,timeo=14"

        # Backup /etc/fstab before making changes (only once)
        if [ ! -f /etc/fstab.bak ]; then
            cp /etc/fstab /etc/fstab.bak
        fi

        # Append the NFS entry to the end of /etc/fstab
        echo "${nfs_share} ${mount_point} nfs ${options} 0 0" >> /etc/fstab

        dialog --infobox "Added ${nfs_share} to /etc/fstab" 5 50
        sleep .5
    }

    # Prompt for NFS server address
    nfs_server=$(dialog --inputbox "Enter NFS server address (IP or hostname):" 8 50 3>&1 1>&2 2>&3)
    if [[ -z "$nfs_server" ]]; then
        dialog --msgbox "NFS server address cannot be empty. Please try again." 8 40
        return 1
    fi

    # Discover available NFS shares using showmount -e
    dialog --infobox "Discovering NFS shares on ${nfs_server}..." 5 50
    sleep 1
    
    # Check if showmount command is available
    if ! command -v showmount &> /dev/null; then
        dialog --msgbox "showmount command not found. Please install nfs-utils package." 8 50
        return 1
    fi

    # Get available exports and strip ALL control characters
    available_shares=$(showmount -e "$nfs_server" 2>/dev/null | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\x1b\][0-9].*\x1b\\//g' | tr -cd '\11\12\15\40-\176')
    if [ $? -ne 0 ] || [ -z "$available_shares" ]; then
        dialog --msgbox "Failed to discover NFS shares on ${nfs_server}. Please check the server address and ensure NFS services are running." 8 60
        return 1
    fi

    # Parse the showmount output (skip lines containing export list headers)
    shares_list=()
    while IFS= read -r line; do
        # Remove any remaining control characters from the line
        line=$(clean_string "$line")
        # Skip lines containing "export list" or "Export list" in any case
        if [[ $line =~ [Ee]xport.list ]]; then
            continue
        fi
        # Extract share path (first field)
        share_path=$(echo "$line" | awk '{print $1}')
        share_path=$(clean_string "$share_path")
        if [[ -n "$share_path" ]]; then
            shares_list+=("$share_path" "" "off")
        fi
    done <<< "$available_shares"

    if [ ${#shares_list[@]} -eq 0 ]; then
        dialog --msgbox "No NFS shares found on ${nfs_server}." 8 40
        return 1
    fi

    # Present checklist of available shares
    selected_shares=$(dialog --checklist "Select NFS shares to mount from ${nfs_server}:" 20 60 10 "${shares_list[@]}" 3>&1 1>&2 2>&3)
    
    if [[ -z "$selected_shares" ]]; then
        dialog --msgbox "No shares selected. Exiting." 8 40
        return 1
    fi

    # Process selected shares
    IFS=' ' read -ra selected_share_array <<< "$selected_shares"
    
    for share in "${selected_share_array[@]}"; do
        # Remove quotes and clean the selected share
        share=$(echo "$share" | sed "s/\"//g")
        share=$(clean_string "$share")
        
        # NEW: Use the aggressive cleaning specifically for mount point names
        clean_share_name=$(basename "$share" 2>/dev/null)
        # If basename fails or returns empty, create a safe name
        if [[ $? -ne 0 ]] || [[ -z "$clean_share_name" ]]; then
            clean_share_name="nfs_share_$((RANDOM % 1000))"
        fi
        
        # Apply aggressive cleaning for mount point
        clean_share_name=$(clean_for_mountpoint "$clean_share_name")
        
        # If we ended up with empty string after cleaning, use a default
        if [[ -z "$clean_share_name" ]]; then
            clean_share_name="nfs_share_$((RANDOM % 1000))"
        fi
        
        default_mount_point="/mnt/nfs/${clean_share_name}"
        
        # Create a clean prompt for display (less aggressive)
        clean_share_prompt=$(clean_for_dialog "$share")
        
        # DEBUG: Show what we're working with
        echo "DEBUG: share='$share'" > /tmp/nfs_debug.log
        echo "DEBUG: clean_share_name='$clean_share_name'" >> /tmp/nfs_debug.log
        echo "DEBUG: default_mount_point='$default_mount_point'" >> /tmp/nfs_debug.log
        
        # Prompt for mount point
        mount_point=$(dialog --inputbox "Enter mount point for $clean_share_prompt:" 8 60 "$default_mount_point" 3>&1 1>&2 2>&3)
        
        if [[ -z "$mount_point" ]]; then
            dialog --msgbox "Mount point cannot be empty. Skipping $clean_share_prompt." 8 50
            continue
        fi

        # Clean the mount point input
        mount_point=$(clean_string "$mount_point")

        # Create the mount point directory if it doesn't exist
        if [ ! -d "${mount_point}" ]; then
            mkdir -p "${mount_point}"
            dialog --infobox "Created mount point directory ${mount_point}" 5 50
            sleep .5
        else
            dialog --infobox "Mount point directory ${mount_point} already exists" 5 50
            sleep .5
        fi

        # Construct full NFS share path
        full_nfs_share="${nfs_server}:${share}"
        
        # Add the NFS entry to /etc/fstab
        add_to_fstab "${full_nfs_share}" "${mount_point}"
    done

    # Mount all NFS shares
    mount -a

    dialog --msgbox "All selected NFS shares have been configured and mounted." 8 50
}

# Main Function to Setup Shares
nfs_setup(){
    # Check for NFS dependencies at the very beginning
    if ! check_install_nfs_utils; then
        return 1
    fi

    while true; do
        CHOICE=$(dialog --clear \
                --title "NFS Share Setup" \
                --nocancel \
                --menu "Choose an option:" \
                15 60 5 \
                1 "WIFI NFS Shares" \
                2 "NFS Shares Via FSTAB ( WIRED ONLY )" \
                B "Back" \
                3>&1 1>&2 2>&3)

        clear
        case $CHOICE in
            1) setup_wifi_nfs_shares ;;
            2) nfs_shares_via_fstab ;;
            B) break ;;
            *) echo "Invalid option. Please try again." ;;
        esac
    done
}
