#!/bin/bash

#-------------------------------------------------------------------------------------#
# Fedora Post-Installation Script                                                     #
# This script automates the configuration and installation of the Looking Glass client #
# on a Fedora system. It includes functions for downloading, building, and installing #
# Looking Glass, as well as setting up necessary system configurations such as SELinux #
# permissions and a systemd service for managing shared memory.                       #
#                                                                                     #
# Functions:                                                                          #
#   - setup_looking_glass_version: Prompts the user to select a version of Looking    #
#                                  Glass and downloads the selected version.          #
#   - build_and_install_looking_glass: Builds and installs the Looking Glass client.  #
#   - create_looking_glass_service: Creates a systemd service to manage shared memory #
#                                   permissions for Looking Glass.                    #
#   - set_selinux_permissions: Configures SELinux permissions for Looking Glass.      #
#   - cleanup_looking_glass: Cleans up temporary files and directories after          #
#                            installation.                                            #
#                                                                                     #
# Usage:                                                                              #
#   This script is designed to be run as part of a Fedora post-installation process.  #
#   It does not need to be executed separately.                                       #
# Prerequisites:                                                                      #
#   - The script assumes a Fedora system with root privileges.                        #
#   - Internet connection is required for downloading files and packages.             #
#   - Additional dependencies may be required for Looking Glass installation.         #
#-------------------------------------------------------------------------------------#
################################################################################
# Plugin metadata (new format)
# menu_title = "Looking Glass / Build and Install"
# menu_function = "looking-glass-install" 
# menu_order = 600
# menu_category = 0
setup_looking_glass_version() {
    # Initialize local variables for version selection and file handling
    current_dir="$(pwd)"
    local version=""
    local stable_version="looking-glass-B7"
    local rc1_version="looking-glass-B7-rc1"
    local stable_file="${stable_version}.tar.gz"
    local rc1_file="${rc1_version}.tar.gz"
    local stable_url="https://looking-glass.io/artifact/stable/source/"
    local rc1_url="https://looking-glass.io/artifact/rc/source/"
    selected_file=""
    local selected_url=""
    extracted_folder=""

    # Use dialog to prompt the user to select the release version of Looking Glass
    version=$(dialog --title "Looking Glass Version" --stdout --radiolist "Please select the Looking Glass release version:" 0 0 2 \
        1 "$stable_version" on \
        2 "$rc1_version" off)

    # Check if the user cancelled the dialog
    if [[ -z "$version" ]]; then
        echo "User cancelled the operation."
        return 1
    fi

    # Conditional logic to handle different versions based on user selection
    if [[ "$version" == "1" ]]; then
        selected_file="$stable_file"
        selected_url="$stable_url"
        extracted_folder="$stable_version"
    else
        selected_file="$rc1_file"
        selected_url="$rc1_url"
        extracted_folder="$rc1_version"
    fi

    # Download the selected version of Looking Glass using curl with headers
    echo "Downloading $selected_file from $selected_url..."
    if ! curl -o "$selected_file" \
         -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0" \
         -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
         -H "Accept-Language: en-US,en;q=0.5" \
         -H "Referer: https://looking-glass.io/" \
         -H "DNT: 1" \
         -H "Connection: keep-alive" \
         -H "Upgrade-Insecure-Requests: 1" \
         -H "Sec-Fetch-Dest: document" \
         -H "Sec-Fetch-Mode: navigate" \
         -H "Sec-Fetch-Site: same-origin" \
         -H "Sec-Fetch-User: ?1" \
         "$selected_url"; then
        echo "Failed to download $selected_file."
        return 1
    fi

    # Verify the downloaded file is a valid gzip archive
    if ! file "$selected_file" | grep -q "gzip compressed data"; then
        echo "Downloaded file is not a valid gzip archive. It may be an HTML page (e.g., Cloudflare CAPTCHA)."
        echo "Please manually download the file from: $selected_url"
        return 1
    fi

    # Extract the downloaded tar.gz file
    echo "Extracting $selected_file..."
    if ! tar -xvzf "$selected_file"; then
        echo "Failed to extract $selected_file."
        return 1
    fi

    echo "Successfully downloaded and extracted $selected_file."
  
}

build_and_install_looking_glass() {
    local extracted_folder="$1"
    local build_dir="client/build"

    # Check if the extracted folder is provided
    if [[ -z "$extracted_folder" ]]; then
        echo "Error: Extracted folder name not provided."
        return 1
    fi

    # Change into the extracted folder
    if [[ ! -d "$extracted_folder" ]]; then
        echo "Error: Extracted folder '$extracted_folder' not found."
        return 1
    fi
    cd "$extracted_folder" || return 1

    # Install required dependencies
    echo "Installing dependencies..."
    if ! sudo dnf install -y cmake gcc gcc-c++ libglvnd-devel fontconfig-devel spice-protocol make nettle-devel \
        pkgconf-pkg-config binutils-devel libXi-devel libXinerama-devel libXcursor-devel \
        libXpresent-devel libxkbcommon-x11-devel wayland-devel wayland-protocols-devel \
        libXScrnSaver-devel libXrandr-devel dejavu-sans-mono-fonts libdecor-devel pipewire-devel libsamplerate-devel pulseaudio-libs-devel; then
        echo "Failed to install dependencies."
        return 1
    fi

    # Create and change into the build directory
    echo "Setting up build directory..."
    mkdir -p "$build_dir"
    cd "$build_dir" || return 1

    # Run CMake and build the project
    echo "Configuring and building Looking Glass client..."
    if ! cmake ..; then
        echo "CMake configuration failed."
        return 1
    fi

    if ! make; then
        echo "Build failed."
        return 1
    fi

    # Install the built binaries
    echo "Installing Looking Glass client..."
    if ! sudo make install; then
        echo "Installation failed."
        return 1
    fi

    echo "Looking Glass client successfully built and installed."
}

create_looking_glass_service() {
    VIRT_USER=$(logname)
    local SERVICE_FILE="/etc/systemd/system/looking-glass-shm.service"

    # Check if VIRT_USER is provided
    if [[ -z "$VIRT_USER" ]]; then
        echo "Error: VIRT_USER must be provided."
        return 1
    fi

    # Create the service file content
    cat <<EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=Setup Looking Glass shared memory permissions
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'touch /dev/shm/looking-glass && chown $VIRT_USER:kvm /dev/shm/looking-glass && chmod 660 /dev/shm/looking-glass'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd to recognize the new service
    sudo systemctl daemon-reload

    # Enable and start the service
    sudo systemctl enable looking-glass-shm.service
    sudo systemctl start looking-glass-shm.service

    echo "Service 'looking-glass-shm.service' created and started successfully."
}

set_selinux_permissions() {
    echo "Setting SELinux permissions..."

    # Create a custom SELinux policy module for qemu-system-x86
    if ! ausearch -c 'qemu-system-x86' --raw | audit2allow -M my-qemusystemx86 &>/dev/null; then
        echo "Failed to create SELinux policy module."
        return 1
    fi

    # Install the custom SELinux policy module
    if ! semodule -X 300 -i my-qemusystemx86.pp &>/dev/null; then
        echo "Failed to install SELinux policy module."
        return 1
    fi

    # Set the domain_can_mmap_files SELinux boolean
    if ! setsebool -P domain_can_mmap_files 1 &>/dev/null; then
        echo "Failed to set SELinux boolean."
        return 1
    fi

    echo "SELinux permissions successfully set."
}
    
cleanup_looking_glass() {
    local extracted_folder="$1"
    local selected_file="$2"

    if [[ -z "$extracted_folder" || -z "$selected_file" ]]; then
        echo "Error: Missing arguments. Usage: cleanup_looking_glass <extracted_folder> <selected_file>"
        return 1
    fi

    # Move up three directories
    cd ../../../ || { echo "Error: Failed to change directory."; return 1; }

    # Change ownership to the current user (assuming $USER is the correct user)
    chown -R "$USER":"$USER" "$extracted_folder" "$selected_file" || {
        echo "Error: Failed to change ownership of files/folders.";
        return 1;
    }

    # Remove the extracted folder and selected file
    rm -rf "$extracted_folder"
    rm -f "$selected_file"

    echo "Cleanup completed."
}

# Main body of script to be run from fedora-post-install main script
looking-glass-install(){
    # Download User Selected Version
    if ! setup_looking_glass_version; then
        echo "Looking Glass installation cancelled by user."
        return 1
    fi
    
    # Call the build_and_install_looking_glass function with the extracted folder
    if ! build_and_install_looking_glass "$extracted_folder"; then
        echo "Looking Glass build/install failed."
        return 1
    fi
    
    # Set SELinux permissions
    if ! set_selinux_permissions; then
        echo "SELinux permissions setup failed."
        return 1
    fi
    
    # Setup Looking-glass Shim
    if ! create_looking_glass_service; then
        echo "Service creation failed."
        return 1
    fi
    
    # Cleanup downloads and temp folder
    cleanup_looking_glass "$extracted_folder" "$selected_file"
    
    echo "Looking Glass installation completed successfully!"
}
