#!/bin/bash
#-------------------------------------------------------------------------------------#
# Font Installation Dialog Script                                                     #
# This script provides a dialog interface for installing Nerd Fonts and               #
# Microsoft Core Fonts as part of the Fedora Post-Installation Utility.               #
#-------------------------------------------------------------------------------------#
################################################################################
# Plugin metadata (new format)
# menu_title = "Fonts - Msfonts / Nerdfont"
# menu_function = "font_installation_menu" 
# menu_order = 1200
# menu_category = 1
###############################################################################
# Function to display the font installation menu
font_installation_menu() {
    while true; do
        choice=$(dialog --clear \
                --backtitle "Fedora Post-Installation - Font Installation" \
                --title "Font Installation Options" \
                --menu "Choose which fonts to install:" 15 60 4 \
                1 "Install JetBrains Mono Nerd Font" \
                2 "Install Microsoft Core Fonts" \
                3 "Install Both Fonts" \
                b "Back" \
                2>&1 >/dev/tty)
        
        case $choice in
            1)
                dialog --clear --title "Confirm Installation" \
                    --yesno "This will install JetBrains Mono Nerd Font.\n\nDo you want to continue?" 10 50
                if [ $? -eq 0 ]; then
                    install_nerd_fonts
                    show_result "Nerd Font installation completed!"
                fi
                ;;
            2)
                dialog --clear --title "Confirm Installation" \
                    --yesno "This will install Microsoft Core Fonts.\n\nDo you want to continue?" 10 50
                if [ $? -eq 0 ]; then
                    install_microsoft_core_fonts
                    show_result "Microsoft Core Fonts installation completed!"
                fi
                ;;
            3)
                dialog --clear --title "Confirm Installation" \
                    --yesno "This will install both JetBrains Mono Nerd Font and Microsoft Core Fonts.\n\nDo you want to continue?" 10 50
                if [ $? -eq 0 ]; then
                    install_nerd_fonts
                    install_microsoft_core_fonts
                    show_result "Both font installations completed!"
                fi
                ;;
            b | B)
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    done
}

# Function to show installation result
show_result() {
    local message="$1"
    dialog --clear --title "Installation Result" \
        --msgbox "$message" 10 50
}

# Your existing functions (slightly modified for better integration)
install_nerd_fonts() {
    # Variables
    LATEST_VERSION="v3.4.0"
    URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${LATEST_VERSION}/JetBrainsMono.zip"
    ZIP_FILE="/tmp/JetBrainsMono.zip"
    EXTRACT_DIR="/tmp/JetBrainsMono"
    FONT_DIR="/usr/share/fonts/JetBrainsMono"
    LOG_FILE="/tmp/install_nerd_fonts.log"

    # Create temp directory
    mkdir -p "$EXTRACT_DIR"

    # Show progress dialog
    (
        echo "10" ; echo "# Starting installation of Nerd Fonts version ${LATEST_VERSION}" ; sleep 1
        
        echo "20" ; echo "# Downloading JetBrains Mono Nerd Font..." ; sleep 1
        wget -O "$ZIP_FILE" "$URL" 2>&1 | grep -oP '[0-9]+%' | while read -r percent; do
            echo "20" ; echo "# Downloading: $percent complete"
        done
        
        # Check if download was successful
        if [ $? -ne 0 ]; then
            echo "100" ; echo "# Download failed!"
            return 1
        fi
        
        echo "50" ; echo "# Extracting font files..." ; sleep 1
        unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR"
        
        echo "70" ; echo "# Creating font directory..." ; sleep 1
        sudo mkdir -p "$FONT_DIR"
        
        echo "80" ; echo "# Copying fonts to system directory..." ; sleep 1
        sudo cp -r "$EXTRACT_DIR"/* "$FONT_DIR"/
        
        echo "90" ; echo "# Setting permissions..." ; sleep 1
        sudo chown -R root: "$FONT_DIR"
        sudo find "$FONT_DIR" -type f -exec chmod 644 {} \;
        sudo restorecon -vFr "$FONT_DIR" > /dev/null 2>&1
        
        echo "95" ; echo "# Cleaning up temporary files..." ; sleep 1
        rm -rf "$ZIP_FILE" "$EXTRACT_DIR"
        
        echo "100" ; echo "# Nerd Font installation completed successfully!" ; sleep 1
    ) | dialog --clear --title "Installing Nerd Fonts" --gauge "Please wait..." 10 60 0
    
    # Refresh font cache
    fc-cache -f -v > /dev/null 2>&1
}

install_microsoft_core_fonts() {
    (
        echo "10" ; echo "# Updating system packages..." ; sleep 1
        sudo dnf upgrade --refresh -y > /dev/null 2>&1
        
        echo "30" ; echo "# Installing required dependencies..." ; sleep 1
        sudo dnf install -y curl cabextract xorg-x11-font-utils fontconfig > /dev/null 2>&1
        
        echo "60" ; echo "# Downloading and installing Microsoft Core Fonts..." ; sleep 1
        sudo rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm > /dev/null 2>&1
        
        echo "90" ; echo "# Finalizing installation..." ; sleep 1
        # Refresh font cache
        fc-cache -f -v > /dev/null 2>&1
        
        echo "100" ; echo "# Microsoft Core Fonts installation completed!" ; sleep 1
    ) | dialog --clear --title "Installing Microsoft Core Fonts" --gauge "Please wait..." 10 60 0
}



