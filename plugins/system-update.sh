#!/bin/bash
#-------------------------------------------------------------------------------------#
# Fedora Post-Installation Utility Script                                             #
# This script facilitates the installation and configuration of various applications  #
# and settings on a Fedora system. It includes functions to manage system updates,    #
# install essential software, and configure system settings.                          #
#                                                                                     #
# Functions:                                                                          #
#   - fix_and_clean_dnf: Optimizes and updates DNF package manager settings.          #
#   - system_update: Performs a system update using DNF.                              #
#                                                                                     #
# Usage:                                                                              #
#   This script is designed to be run as a plugin module as part of the Fedora        #
#   Post-Installation Script. It does not need to be executed separately.             #
# Prerequisites:                                                                      #
#   - The script assumes a Fedora system with DNF package manager installed.          #
#   - Internet connection is required for downloading packages and updates.           #
#-------------------------------------------------------------------------------------#
################################################################################
# Plugin metadata (new format)
# menu_title = "System Update and Upgrade"
# menu_function = "system_update" 
# menu_order = 200
# menu_category = 1
################################################################################

system_update(){
   # Ask user if they want to clean dnf
    dialog --title "System Update" --yesno "Would you like to Perform and System Update" 7 60
    response=$?
    if [[ $response -eq 0 ]]; then
        clear
        dnf update -y
        messages+=("'System update completed")
    else
        messages+=("Skipped System Update'.")
    fi
    return 0
}
