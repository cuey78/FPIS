#!/bin/bash
################################################################################
# Plugin metadata
# menu_title = "GPU Drivers"
# menu_function = "install_drivers"
# menu_order = 400
# menu_category = 1
################################################################################

# Check if dnf5 is installed
check_dnf5_installed() {
    command -v dnf5 &> /dev/null
}

# Check RPM Fusion repositories
check_rpmfusion_repos() {
    if check_dnf5_installed; then
        free_repo=$(dnf5 repo list --enabled | grep -i 'rpmfusion-free')
        nonfree_repo=$(dnf5 repo list --enabled | grep -i 'rpmfusion-nonfree')
    else
        free_repo=$(dnf repolist enabled | grep -i 'rpmfusion-free')
        nonfree_repo=$(dnf repolist enabled | grep -i 'rpmfusion-nonfree')
    fi
    [[ -n "$free_repo" && -n "$nonfree_repo" ]]
}

# Safe package installation
safe_install() {
    local package=$1
    if check_dnf5_installed; then
        dnf5 install -y "$package"
    else
        dnf install -y "$package"
    fi
}

# Safe package swap
safe_swap() {
    local from_pkg=$1
    local to_pkg=$2
    if check_dnf5_installed; then
        dnf5 swap -y "$from_pkg" "$to_pkg"
    else
        dnf swap -y "$from_pkg" "$to_pkg"
    fi
}

# Install development dependencies
install_dependencies() {
    echo "Installing development dependencies..."
    safe_install "kernel-devel"
    safe_install "gcc"
    safe_install "make"
}

# Verify AMD drivers
verify_amd_drivers() {
    if command -v vainfo &> /dev/null; then
        if vainfo 2>/dev/null | grep -q "AMD"; then
            echo "✓ AMD drivers working correctly"
        else
            echo "⚠ AMD drivers may need configuration"
        fi
    fi
}

# Verify Intel drivers
verify_intel_drivers() {
    if command -v vainfo &> /dev/null; then
        if vainfo 2>/dev/null | grep -q "Intel"; then
            echo "✓ Intel drivers working correctly"
        else
            echo "⚠ Intel drivers may need configuration"
        fi
    fi
}

# Verify NVIDIA drivers
verify_nvidia_drivers() {
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            echo "✓ NVIDIA drivers working correctly"
            nvidia-smi --query-gpu=driver_version --format=csv,noheader
        else
            echo "⚠ NVIDIA drivers may need reboot"
        fi
    else
        echo "❌ NVIDIA drivers not detected"
    fi
}

# Install AMD Mesa FreeWorld Drivers
install_amd_drivers() {
    clear
    echo "Installing AMD Mesa FreeWorld Drivers..."
    
    install_dependencies
    
    safe_swap "mesa-va-drivers" "mesa-va-drivers-freeworld"
    safe_swap "mesa-vdpau-drivers" "mesa-vdpau-drivers-freeworld"
    safe_install "libva-utils"
    safe_install "vulkan-loader"
    safe_install "vulkan-tools"
    
    verify_amd_drivers
    
    clear
    dialog --msgbox "AMD drivers installation completed!" 0 0
    return 0
}

# Install Intel Media Driver
install_intel_drivers() {
    clear
    echo "Installing Intel Media Drivers..."
    
    install_dependencies
    
    safe_install "intel-media-driver"
    safe_install "libva-utils"
    safe_install "vulkan-loader"
    safe_install "vulkan-tools"
    
    verify_intel_drivers
    
    clear
    dialog --msgbox "Intel drivers installation completed!" 0 0
    return 0
}

# Install NVIDIA Proprietary Drivers with robust error handling
install_nvidia_drivers() {
    clear
    echo "Installing NVIDIA Proprietary Drivers..."
    
    install_dependencies
    
    # Install NVIDIA drivers and CUDA support
    safe_install "akmod-nvidia"
    safe_install "xorg-x11-drv-nvidia-cuda"
    safe_install "nvidia-modprobe"
    safe_install "nvidia-persistenced"
    safe_install "nvidia-container-toolkit"
    
    # Install multimedia packages
    safe_install "nvidia-vaapi-driver"
    safe_install "libva-utils"
    safe_install "vulkan-loader"
    
    # Wait for akmod to build the kernel modules
    echo "Waiting for kernel module build to complete..."
    sleep 5
    
    # Regenerate initramfs to include NVIDIA modules
    echo "Regenerating initramfs with NVIDIA modules..."
    if dracut -f --verbose; then
        echo "✓ Initramfs regenerated successfully"
    else
        echo "⚠ Initramfs regeneration had issues, but continuing..."
    fi
    
    # Load modules immediately without reboot (if possible)
    echo "Loading NVIDIA kernel modules..."
    modprobe nvidia 2>/dev/null || true
    modprobe nvidia_drm 2>/dev/null || true
    modprobe nvidia_modeset 2>/dev/null || true
    modprobe nvidia_uvm 2>/dev/null || true
    
    # Enable and start nvidia-persistenced service
    systemctl enable nvidia-persistenced --now 2>/dev/null || true
    
    verify_nvidia_drivers
    
    clear
    dialog --msgbox "NVIDIA drivers installed. A reboot is recommended for full functionality." 0 0
    return 0
}

# Main driver installation function
install_drivers() {
    if ! check_rpmfusion_repos; then
        dialog --msgbox "RPM Fusion Free and Non-Free repositories must be enabled first." 0 0
        return 1
    fi
    
    while true; do
        CHOICE=$(dialog --clear \
                --title "GPU Drivers Installation" \
                --nocancel \
                --menu "Select your GPU vendor and driver type:" \
                17 65 5 \
                1 "AMD - Mesa FreeWorld Drivers" \
                2 "Intel - Media Driver" \
                3 "NVIDIA - Proprietary Drivers" \
                b "Back" \
                3>&1 1>&2 2>&3)

        case $CHOICE in
            1) install_amd_drivers ;;
            2) install_intel_drivers ;;
            3) install_nvidia_drivers ;;
            b | B) break ;;
        esac
    done
    
    return 0
}
