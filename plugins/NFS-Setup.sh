#!/bin/bash
#----------------------------------------------------------------------------------#
# Fedora Post-Installation Network Configuration Script                            #
# This script assists in setting up Wi-Fi and NFS shares                           #
# on a Fedora system. It includes functions to manage Wi-Fi connections, update NFS#
# scripts, and install fonts, enhancing both connectivity and visual customization.#
#                                                                                  #
# Functions:                                                                       #
#   - setup_wifi_nfs_shares: Scans and connects to Wi-Fi networks, sets up NFS.    #
#   - update_nfs_script: Updates NFS configuration scripts based on user input.    #
#   - wifi_nfs_shares: Main function to handle Wi-Fi and NFS shares setup.         #
#   - nfs_shares_via_fstab: Sets up NFS shares using fstab for wired connections.  #
#   - install_nerd_fonts: Downloads and installs Nerd Fonts.                       #
#   - nfs_setup: Provides a menu to choose between Wi-Fi or wired NFS setup.       #
#                                                                                  #
# Usage:                                                                           #
#   This script is designed to be run as a plugin module as part of the Fedora     #
#   Post-Installation Script. It does not need to be executed separately.          #
# Prerequisites:                                                                   #
#   - The script assumes a Fedora system with network manager and systemd.         #
#   - Internet connection is required for downloading fonts and updating NFS.      #
#----------------------------------------------------------------------------------#
################################################################################
# Plugin metadata (new format)
# menu_title = "Network File System (NFS) Configuration"
# menu_function = "nfs_setup" 
# menu_order = 600
# menu_category = 1
###############################################################################
#Scans for Wifi Networks
setup_wifi_nfs_shares() {
    # Function to scan for available Wi-Fi networks and select one
 scan_and_select_wifi() {
    WIFI_SSID=""
        dialog --infobox "Scanning for available Wi-Fi networks..." 10 50
        sleep 0.5
        AVAILABLE_SSIDS=$(nmcli -t -f SSID dev wifi | sort -u)

        if [ -z "$AVAILABLE_SSIDS" ]; then
            dialog --infobox "No Wi-Fi networks found. Exiting..." 10 50
            sleep 1
            return 1
        fi

        # Prepare list for dialog
        SSID_LIST=()
        for SSID in $AVAILABLE_SSIDS; do
            SSID_LIST+=("$SSID" "$SSID" OFF)
        done

        WIFI_SSID=$(dialog --radiolist "Available Wi-Fi networks:" 15 50 8 "${SSID_LIST[@]}" 3>&1 1>&2 2>&3)

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

        # Prompt the user for the number of NFS shares to add using dialog and check if the input is not empty or zero
        while true; do
            num_shares=$(dialog --inputbox "How many NFS shares would you like to add?" 8 40 3>&1 1>&2 2>&3)
            if [[ -z "$num_shares" || "$num_shares" -eq 0 ]]; then
                dialog --msgbox "Please enter a valid number greater than zero." 0 0 
            else
                break
            fi
        done
        # Prompt the user for the IP of the server using dialog and check if it is not empty
        while true; do
            REMOTE_SERVER=$(dialog --inputbox "Enter IP of Server (e.g., 10.0.0.10):" 8 40 3>&1 1>&2 2>&3)
            if [ -z "$REMOTE_SERVER" ]; then
                dialog --no-cancel --msgbox "IP address cannot be empty. Please enter a valid IP." 8 40
            else
                break
            fi
        done

        nfs_shares=()
        mount_points=()

        # Loop through the number of shares and prompt the user for each share
        for (( i=1; i<=num_shares; i++ )); do
            nfs_share=$(dialog --inputbox "Enter the NFS share #$i (e.g., /example/path):" 8 50 3>&1 1>&2 2>&3)
            mount_point=$(dialog --inputbox "Enter the mount point #$i (e.g., /mnt/nfs):" 8 50 3>&1 1>&2 2>&3)

            # Create the mount point directory if it doesn't exist
            if [ ! -d "${mount_point}" ]; then
                mkdir -p "${mount_point}"
                dialog --infobox "Created mount point directory ${mount_point}" 0 0
                sleep 1
            else
                dialog --infobox "Mount point directory ${mount_point} already exists" 0 0
                sleep 1
            fi

            nfs_shares+=("$nfs_share")
            mount_points+=("$mount_point")
        done

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

#Setup NFS shares via FSTAB
nfs_shares_via_fstab() {
    echo "NFS Shares Via FSTAB (Wired Only)"
     # Connect NFS Shares VIA FSTAB
            clear # clear screen
            echo "NFS Shares Via FSTAB ( WIRED ONLY )"
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

            # Prompt the user for the number of shares to add
            num_shares=$(dialog --inputbox "How many NFS shares would you like to add?" 8 40 3>&1 1>&2 2>&3)
            if [[ -z "$num_shares" || "$num_shares" -eq 0 ]]; then
                dialog --msgbox "Number of NFS shares cannot be empty or zero. Please try again." 8 40
                return 1
            fi

            for (( i=1; i<=num_shares; i++ )); do
            # Prompt the user for the NFS share and mount point using dialog
            while true; do
                nfs_share=$(dialog --inputbox "Enter the NFS share #$i (e.g., server:/path):" 8 50 3>&1 1>&2 2>&3)
                if [[ -z "$nfs_share" ]]; then
                    dialog --msgbox "NFS share cannot be empty. Please try again." 8 50
                else
                    break
                fi
            done

            while true; do
                mount_point=$(dialog --inputbox "Enter the mount point #$i (e.g., /mnt/nfs):" 8 50 3>&1 1>&2 2>&3)
                if [[ -z "$mount_point" ]]; then
                    dialog --msgbox "Mount point cannot be empty. Please try again." 8 50
                else
                    break
                fi
            done

            # Create the mount point directory if it doesn't exist
            if [ ! -d "${mount_point}" ]; then
                mkdir -p "${mount_point}"
                dialog --infobox "Created mount point directory ${mount_point}" 5 50
                sleep .5
            else
                dialog --infobox "Mount point directory ${mount_point} already exists" 5 50
                sleep .5
            fi

            # Add the NFS entry to /etc/fstab
            add_to_fstab "${nfs_share}" "${mount_point}"
            done

            # Mount all NFS shares
            mount -a

            dialog --infobox "All specified NFS shares have been mounted." 5 50
            sleep .5
}

# Main Function to Setup Shares
nfs_setup(){
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

