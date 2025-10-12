#!/bin/bash
#-------------------------------------------------------------------------------------#
# Fedora Post-Installation Utility Script                                             #
# This script facilitates the installation and configuration of various applications  #
# and settings on a Fedora system. It includes functions to manage system updates,    #
# install essential software, and configure system settings.                          #
#                                                                                     #
# Functions:                                                                          #
#   - install_rpm_fusion: Installs RPM Fusion repositories for additional software.   #
#     This function adds both free and non-free RPM Fusion repositories, and installs #
#     necessary appstream data and tainted releases.                                  #
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
# menu_title = "Enable RPM Fusion"
# menu_function = "install_rpm_fusion" 
# menu_order = 300
# menu_category = 1
###############################################################################
# This Function Install RPM Fusion Repos
install_rpm_fusion() {
    echo "Install RPM Fusion"
    
    fedora_version=$(rpm -E %fedora)
    rpmfusion_free_url="https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm"
    rpmfusion_nonfree_url="https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"

    dnf install -y --nogpgcheck "$rpmfusion_free_url" "$rpmfusion_nonfree_url"
    dnf install -y rpmfusion-free-appstream-data rpmfusion-nonfree-appstream-data 
    dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted
    clear
}
