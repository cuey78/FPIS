#!/bin/bash

################################################################################
# Plugin metadata (new format)
# menu_title = "System Tweaks"
# menu_function = "system_tweaks" 
# menu_order = 1100
# menu_category = 1
###############################################################################

# This function checks and modifies the GRUB command line settings.
check_grub_cmdline() {
    # Read the current GRUB_CMDLINE_LINUX line from /etc/default/grub
    current_line=$(grep "^GRUB_CMDLINE_LINUX=" /etc/default/grub)

    # Extract the content within the quotes
    current_content=$(echo "$current_line" | sed 's/GRUB_CMDLINE_LINUX="//;s/"$//')

    # Display current GRUB line and confirmation dialog
    dialog --title "Current GRUB Configuration" --yesno "Current GRUB configuration is: \n\n$current_content\n\nDo you want to reset it to defaults?" 0 0

    # Check user response
    response=$?
    if [ $response -eq 0 ]; then
        # Automatically replace the content within the quotes
        new_content="rhgb quiet"
        # Replace the line in the file
        sed -i "s/^GRUB_CMDLINE_LINUX=\"$current_content\"/GRUB_CMDLINE_LINUX=\"$new_content\"/" /etc/default/grub
        dialog --title "Update Successful" --infobox "GRUB Defaults Have been Restored" 0 0
        sleep 2
        return 1  # Return 1 for success
    else
        dialog --title "Update Cancelled" --infobox "No changes made to GRUB configuration" 0 0
        sleep 2
        return 0  # Return 0 for cancellation
    fi
}


# Function to update GRUB_TIMEOUT in /etc/default/grub
update_grub_timeout() {
    local new_timeout
    local grub_file="/etc/default/grub"

    # Prompt the user for the new GRUB_TIMEOUT value using dialog
    new_timeout=$(dialog --inputbox "Enter the new GRUB_TIMEOUT value: " 8 40 3>&1 1>&2 2>&3 3>&-)

    # Validate the input (ensure it's a non-negative integer)
    if [[ $new_timeout =~ ^[0-9]+$ ]]; then
        # Check if the grub file exists
        if [[ ! -f $grub_file ]]; then
            echo "Error: $grub_file does not exist."
            return 1
        fi

        # Backup the current grub file
        cp $grub_file ${grub_file}.bak

        # Update the GRUB_TIMEOUT value
        sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${new_timeout}/" $grub_file

        # Inform the user of the change
        dialog --msgbox "GRUB_TIMEOUT set to ${new_timeout} in ${grub_file}\n\nGRUB configuration updated." 8 50
        clear
        # Update GRUB configuration
        update_grub_config
    else
        dialog --msgbox "Error: Please enter a valid non-negative integer." 8 50
    fi
}

# This function updates the GRUB configuration for both BIOS and UEFI systems.
# It uses grub2-mkconfig to generate the configuration files.
# If the generation fails, it will return an error and stop the process.
# End Generation Here
update_grub_config() {
    grub2-mkconfig -o /boot/grub2/grub.cfg
    if [ $? -ne 0 ]; then
        echo "Failed to update GRUB configuration for BIOS."
        return 1
    fi

    grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
    if [ $? -ne 0 ]; then
        echo "Failed to update GRUB configuration for UEFI."
        return 1
    fi

    echo "GRUB configuration updated successfully."
}

# Adds theme and options
FIX_GRUB(){
    # Define the GRUB configuration file path
    local GRUB_FILE="/etc/default/grub"
    # Define the backup file path for the GRUB configuration
    local BACKUP_FILE="${GRUB_FILE}.bak"
    # Define the directory path for the GRUB theme
    local THEME_DIR="/boot/grub2/theme/fedora/"
    local THEME_DIR2="/boot/grub2/theme/"
    # Define the theme file path
    local THEME_FILE="${THEME_DIR}theme.txt"
    # Define the graphics mode setting
    local GFXMODE="1920x1080,auto"

    # Check if the GRUB configuration file exists
    echo "Checking GRUB configuration file..."
    if [[ ! -f "$GRUB_FILE" ]]; then
        echo "Error: $GRUB_FILE does not exist."
        return 1
    fi

    # Create a backup of the original GRUB configuration file
    echo "Creating backup of the original GRUB file..."
    cp "$GRUB_FILE" "$BACKUP_FILE" || { echo "Failed to create backup."; return 1; }

    # Remove existing configurations related to terminal output, theme, and graphics mode
    echo "Cleaning up existing configurations..."
    sed -i "/GRUB_TERMINAL_OUTPUT=/d; /GRUB_THEME=/d; /GRUB_GFXMODE=/d" "$GRUB_FILE"

    # Append new configurations for terminal output, graphics mode, and theme
    echo "Appending new configurations..."
    {
        echo '#GRUB_TERMINAL_OUTPUT="console"'
        echo "GRUB_GFXMODE=$GFXMODE"
        echo "GRUB_THEME=\"$THEME_FILE\""
    } >> "$GRUB_FILE"

    # Ensure the theme directory exists and create it if it doesn't
    #echo "Ensuring theme directory exists..."
    mkdir -p "$THEME_DIR2" || { echo "Failed to create theme directory."; return 1; }

    # Copy theme files to the theme directory
    echo "Copying theme files..."
    cp -r theme/* "$THEME_DIR" || { echo "Failed to copy theme files."; return 1; }

    # Update the GRUB configuration to apply changes
    echo "Updating GRUB configuration..."
    update_grub_config
}


# Changes System Hostname
CH_HOSTNAME() {
    # Capture user input for the hostname
    hostname=$(dialog --inputbox "Enter new hostname:" 0 0 3>&1 1>&2 2>&3 3>&-)

    # Check if the user pressed Cancel or provided an empty input
    if [ $? -eq 0 ] && [ -n "$hostname" ]; then
        # Set the hostname
        hostnamectl set-hostname "$hostname"

        # Display a message box with the new hostname
        dialog --msgbox "Hostname set to $hostname" 0 0
    else
        dialog --msgbox "Hostname not set or input cancelled" 0 0
    fi
}


# Main menu function
function system_tweaks() {
    while true; do
        choice=$(dialog \
            --backtitle "System Tweaks" \
            --title "System Tweaks" \
            --menu "System Tweaks:" 0 0 0 \
            1 "Change System Host Name" \
            2 "Install Fedora Grub Theme" \
            b "Back" \
            3>&1 1>&2 2>&3)
        
        case $choice in
            1)
                CH_HOSTNAME
                ;;
            2)
                FIX_GRUB
                ;;
            b|"")
                clear
                return 1
                ;;
        esac
    done
}
