#!/bin/bash
#-------------------------------------------------------------------------------------#
# Fedora Post-Installation Utility Script                                             #
# This script facilitates the installation and configuration of various applications  #
# and settings on a Fedora system. It includes functions to manage Flatpak and        #
# install applications via Flatpak.                                                   #
#                                                                                     #
# Functions:                                                                          #
#   - enable_flathub: Adds the Flathub repository and installs Flatpak.               #
#   - flatpak_menu: Provides a menu for Flatpak-related operations.                   #
#   - install_flatpaks: Installs applications via Flatpak (implementation not shown). #
#                                                                                     #
# Usage:                                                                              #
#   This script is designed to be run as a plugin module as part of the Fedora        #
#   Post-Installation Script. It does not need to be executed separately.             #
#                                                                                     #
# Prerequisites:                                                                      #
#   - The script assumes a Fedora system with DNF installed.                          #
#   - Internet connection is required for downloading packages and updates.           #
#-------------------------------------------------------------------------------------#
################################################################################
# Plugin metadata (new format)
# menu_title = "Flatpak Setup / Application Selection"
# menu_function = "flatpak_menu" 
# menu_order = 700
# menu_category = 1
###############################################################################
# Installs Flatpak and Enables Flathub
enable_flathub() {
    # Check if flatpak is installed
    if ! command -v flatpak &> /dev/null; then
        echo "Flatpak is not installed. Installing flatpak..."
        
        # Install flatpak using dnf
        sudo dnf install -y flatpak
        if [[ $? -ne 0 ]]; then
            echo "Failed to install flatpak. Please check your package manager."
            return 1
        fi
    fi

    # Add the Flathub repository
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    if [[ $? -eq 0 ]]; then
        dialog --msgbox "Flathub Enabled" 0 0
    else
        dialog --msgbox "Failed to add Flathub repository." 0 0
        return 1
    fi
}

flatpak_menu() {
    # Loop indefinitely to show the menu until the user chooses to exit
    while true; do
        # Display a menu using dialog and store the user's choice in the variable CHOICE
        CHOICE=$(dialog --clear \
                --title "Configure Flatpak and Manage Applications" \
                --nocancel \
                --menu "Choose an option:" \
                15 60 3 \
                1 "Enable Flatpak Support" \
                2 "Install Applications via Flatpak" \
                b "Back" \
                3>&1 1>&2 2>&3)

        # Clear the screen after the dialog closes
        clear
        # Handle the user's choice
        case $CHOICE in
            1) 
                # Option 1: Enable Flatpak through the enable_flathub function
                enable_flathub ;;
            2) 
                # Option 2: Install Flatpak apps through the install_flatpaks function
                install_flatpaks ;;
            b | B) 
                # Option 3: Exit the menu loop
                break ;;
            *) 
                # Handle any other input as an invalid option
                echo "Invalid option. Please try again." ;;
        esac
    done
}



# Installs selected Flatpak applications from a predefined list in flatapps.txt using dialog interface
install_flatpaks() {
# Path to the file with the list of apps
file="./plugins/flatapps.txt"

# Check if the file exists
if [[ ! -f "$file" ]]; then
    echo "File $file not found!"
    exit 1
fi


# Read the list of apps into an array
apps=()
while IFS= read -r line; do
    if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
        apps+=("$line")
    fi
done < "$file"

# Check if the list is empty
if [[ ${#apps[@]} -eq 0 ]]; then
    echo "No apps found in $file"
    exit 1
fi

# Create dialog options array
local options=()
local i=0
for app in "${apps[@]}"; do
    options+=($i "$app" off)
    ((i++))
done

# Use dialog to create a checklist for app selection
local choices=$(dialog --title "Select Flatpak Apps to Install" \
                      --checklist "Select apps to install:" \
                      15 60 5 "${options[@]}" \
                      3>&1 1>&2 2>&3 3>&-)

if [[ -z "$choices" ]]; then
    dialog --msgbox "No apps selected." 0 0
    return 1
fi

# Convert dialog output into array of indices
local selected_indices=($choices)

# Install the selected apps
for index in "${selected_indices[@]}"; do
    clear
    app="${apps[$index]}"
    echo "Installing $app..."
    runuser -l $USER -c "flatpak install -y flathub \"$app\" || { echo \"Failed to install $app\"; exit 1; }"
done

echo "Installation complete."
}
