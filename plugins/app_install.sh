#!/bin/bash
#-------------------------------------------------------------------------------------#
# Fedora 41 Application Installer Script                                             #
# This script automates the installation of various software applications on a       #
# Fedora 41 system. It provides a menu-driven interface for users to select and      #
# install applications like Cooler Control, gaming utilities, GNOME Software,        #
# and development tools.                                                             #
#                                                                                     #
# Functions:                                                                          #
#   - display_menu: Displays a menu for user selection of applications to install.    #
#   - install_cooler_lact: Installs Cooler Control and LACT.                          #
#   - install_gaming_utils: Installs gaming-related utilities like Steam and Lutris.  #
#   - install_gnome_software: Installs GNOME Software for application management.     #
#   - install_dev_tools: Installs development tools like wget and git.                #
#                                                                                     #
# Usage:                                                                              #
#   This script is designed to be run as a plugin for fedora post install.              #
# Prerequisites:                                                                      #
#   - The script assumes a Fedora 41 system with DNF and internet access.             #
#   - Ensure sudo privileges for software installation and system configuration.      #
#-------------------------------------------------------------------------------------#
################################################################################
# Plugin metadata (new format)
# menu_title = "Install Additional Apps"
# menu_function = "app_install" 
# menu_order = 900
# menu_category = 1
###############################################################################
heroic(){
# GitHub releases URL
RELEASES_URL="https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/"

# Fetch the latest release page
echo "Fetching latest release information from GitHub..."
RELEASE_PAGE=$(curl -s "$RELEASES_URL")

# Extract the RPM file URL
RPM_URL=$(echo "$RELEASE_PAGE" | grep -oP 'href="\K[^"]+\.rpm(?=")' | head -n 1)

# Check if RPM URL was found
if [ -z "$RPM_URL" ]; then
    echo "Error: No RPM file found in the latest release."
    exit 1
fi

# Construct the full download URL
DOWNLOAD_URL="https://github.com$RPM_URL"

# Extract the RPM file name
RPM_FILE=$(basename "$RPM_URL")

# Download the RPM file
echo "Downloading $RPM_FILE..."
curl -LO "$DOWNLOAD_URL"

# Verify the download
if [ $? -eq 0 ]; then
    echo "Download complete: $RPM_FILE"
else
    echo "Error: Failed to download the RPM file."
    exit 1
fi
#Install heroic game launcher
dnf install $RPM_FILE -y
#remove file after install
rm -f $RPM_FILE
}

# Function to display a menu using dialog
display_menu() {
  dialog --clear \
    --backtitle "Fedora 41 Application Installer" \
    --title "Application Installation Menu" \
    --menu "Select an application to install:" 0 0 0 \
    1 "Cooler Control and LACT - Install tools to control CPU coolers and monitor temperature." \
    2 "Gaming Packages - Install Steam, Lutris, Gamescope, Winetricks , Heroic and other gaming-related tools." \
    3 "Development Tools - Related utilities for development." \
    4 "Tweaks for the Gnome Desktop" \
    5 "Tweaks for the KDE Desktop" \
    b "Back" 2>menu_selection

  choice=$(<menu_selection)
  rm -f menu_selection
}

# Function to install Cooler Control and LACT
install_cooler_lact() {
  clear
  echo "Installing Cooler Control and LACT..."
  dnf copr enable codifryed/CoolerControl -y
  dnf install coolercontrol -y
  systemctl enable --now coolercontrold

  dnf install https://github.com/ilya-zlobintsev/LACT/releases/download/v0.6.0/lact-0.6.0-0.x86_64.fedora-41.rpm -y
  systemctl enable --now lactd
}

winetrick_install(){
 if command -v make &> /dev/null; then
    echo "make is installed."
    echo "installing Winetricks"
else
    echo "make is not installed."
    echo "installing dev tools"
    install_dev_tools
fi
 git clone https://github.com/Winetricks/winetricks
  cd winetricks || exit
  make install
  cd ..
  rm -rf winetricks
}

# Function to install gaming utilities
install_gaming_utils() {
  clear
  echo "Installing Gaming Utilities..."
  dnf install steam lutris gamescope mangohud -y
  #install Heroic Game Luncher
  heroic
  #install newest winetricks from git
  winetrick_install
}

# Function to install development tools
install_dev_tools() {
  clear
  echo "Installing Development Tools..."
  sudo dnf group install -y c-development development-tools 
}

# Function for the main script loop
app_install() {
  clear
  while true; do
    display_menu

    case $choice in
      1)
        install_cooler_lact
        ;;
      2)
        install_gaming_utils
        ;;
      3)
        install_dev_tools
        ;;
      4)
        tweaks_gnome
        ;;
      5)
        kde_tweaks
      ;;
      b)
        return # Exit the function to go back to the main menu
        ;;
      *)
        echo "Invalid option. Please try again."
        ;;
    esac
  done
}
