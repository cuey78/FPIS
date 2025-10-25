#!/bin/bash
################################################################################
# Plugin metadata (new format)
# menu_title = "Shell Improvements - ohhmyzsh / ohhmybash"
# menu_function = "main_menu" 
# menu_order = 1000
# menu_category = 1
###############################################################################
# Function to install Zsh and Oh My Zsh
function install_oh_my_zsh() {
    local USER2
    USER2=$(logname 2>/dev/null || echo "$SUDO_USER" || echo "$USER")
    
    # Check if running with sufficient privileges
    if [[ $EUID -eq 0 ]] && [[ -z "$SUDO_USER" ]]; then
        dialog --msgbox "Error: Please run this script with sudo rather than as root." 0 0
        return 1
    fi
    
    dialog --infobox "Installing Zsh..." 0 0
    sleep 2
    
    # Install Zsh
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y zsh
    elif command -v yum >/dev/null 2>&1; then
        yum install -y zsh
    else
        dialog --msgbox "Error: Cannot find package manager (dnf or yum)" 0 0
        return 1
    fi
    
    if [[ $? -ne 0 ]]; then
        dialog --msgbox "Error: Failed to install Zsh" 0 0
        return 1
    fi
    
    # Change default shell to Zsh
    if command -v chsh >/dev/null 2>&1; then
        if [[ $EUID -eq 0 ]]; then
            runuser -u "$USER2" -- chsh -s "$(which zsh)"
        else
            chsh -s "$(which zsh)"
        fi
    fi
    
    dialog --infobox "Installing Oh My Zsh..." 0 0
    sleep 2
    
    # Install Oh My Zsh
    if command -v runuser >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
        runuser -u "$USER2" -- sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        dialog --msgbox "Oh My Zsh installed successfully! Please restart your terminal or run 'zsh' to start using it." 0 0
    else
        dialog --msgbox "Oh My Zsh installation completed with exit code: $result" 0 0
    fi
    
    return $result
}

# Function to install Oh My Bash
function install_oh_my_bash() {
    local USER2
    USER2=$(logname 2>/dev/null || echo "$SUDO_USER" || echo "$USER")
    
    # Validate that we have a valid user
    if [[ -z "$USER2" ]]; then
        dialog --msgbox "Error: Could not determine the original user." 0 0
        return 1
    fi
    
    # Check if running with sufficient privileges
    if [[ $EUID -eq 0 ]] && [[ -z "$SUDO_USER" ]]; then
        dialog --msgbox "Error: Please run this script with sudo rather than as root." 0 0
        return 1
    fi
    
    dialog --infobox "Installing Oh My Bash..." 0 0
    sleep 2
    
    # Create a temporary file for the installation script
    local temp_script
    temp_script=$(mktemp)
    
    # Fetch script from URL with error handling
    local script_url="https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh"
    
    if ! curl -fsSL "$script_url" -o "$temp_script"; then
        dialog --msgbox "Error: Failed to download Oh My Bash installation script." 0 0
        rm -f "$temp_script"
        return 1
    fi
    
    # Make the script executable and run it
    chmod +x "$temp_script"
    
    if command -v runuser >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
        runuser -u "$USER2" -- "$temp_script" --unattended
    else
        # Fallback for systems without runuser or when not root
        "$temp_script" --unattended
    fi
    
    local result=$?
    
    # Clean up temporary file
    rm -f "$temp_script"
    
    if [[ $result -eq 0 ]]; then
        dialog --msgbox "Oh My Bash installed successfully! Please restart your terminal to apply changes." 0 0
    else
        dialog --msgbox "Oh My Bash installation completed with exit code: $result" 0 0
    fi
    
    return $result
}

# Function to check if dialog is installed
function check_dependencies() {
    if ! command -v dialog >/dev/null 2>&1; then
        echo "Installing dialog..."
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y dialog
        elif command -v yum >/dev/null 2>&1; then
            yum install -y dialog
        else
            echo "Error: Cannot install dialog - no supported package manager found"
            exit 1
        fi
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        echo "Installing curl..."
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y curl
        elif command -v yum >/dev/null 2>&1; then
            yum install -y curl
        fi
    fi
}

# Main menu function
function main_menu() {
    while true; do
        choice=$(dialog \
            --backtitle "Shell Installation Menu" \
            --title "Choose Shell to Install" \
            --menu "Select which shell framework to install:" 0 0 0 \
            1 "Install Oh My Zsh only" \
            2 "Install Oh My Bash only" \
            b "Back" \
            3>&1 1>&2 2>&3)
        
        case $choice in
            1)
                install_oh_my_zsh
                ;;
            2)
                install_oh_my_bash
                ;;
            b|"")
                clear
                return 1
                ;;
        esac
    done
}

