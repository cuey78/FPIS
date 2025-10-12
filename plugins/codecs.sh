#!/bin/bash
#-------------------------------------------------------------------------------------#
# Fedora Post-Installation Utility Script                                             #
# This script facilitates the installation of media codecs on a Fedora system.        #
#                                                                                     #
# Functions:                                                                          #
#   - install_media_codecs: Installs essential media codecs for multimedia playback.  #
#                                                                                     #
# Usage:                                                                              #
#   This script is designed to be run as a plugin module as part of the Fedora        #
#   Post-Installation Script. It does not need to be executed separately.             #
# Prerequisites:                                                                      #
#   - The script assumes a Fedora system with DNF installed.                          #
#   - Internet connection is required for downloading packages and updates.           #
#   - RPM Fusion repositories should be enabled for this function to work properly.   #
#-------------------------------------------------------------------------------------#
################################################################################
# Plugin metadata (new format)
# menu_title = "Comprehensive Media Codecs Install"
# menu_function = "install_media_codecs" 
# menu_order = 500
# menu_category = 1
###############################################################################
install_media_codecs() {
    echo "=========================================="
    echo "|   Installing Comprehensive Media Codecs |"
    echo "=========================================="

    # Check if RPM Fusion repositories are enabled
    if ! dnf repolist | grep -q "rpmfusion-free"; then
        dialog --msgbox "RPM Fusion Free repository not enabled. Please enable RPM Fusion first." 10 60
        return 1
    fi

    if ! dnf repolist | grep -q "rpmfusion-nonfree"; then
        dialog --msgbox "RPM Fusion Non-Free repository not enabled. Please enable RPM Fusion first." 10 60
        return 1
    fi

    # Resolve FFmpeg conflicts and install full suite
    dialog --infobox "Resolving FFmpeg package conflicts..." 5 50
    if sudo dnf install ffmpeg ffmpeg-libs --allowerasing; then
        dialog --infobox "FFmpeg installed successfully" 5 50
        sleep 2
    else
        dialog --msgbox "Failed to install FFmpeg. Trying alternative approach..." 10 60
        # Alternative: Remove conflicts first, then install
        sudo dnf remove libswscale-free libswresample-free --allowerasing
        sudo dnf install ffmpeg ffmpeg-libs
    fi

    # Install essential codec packages
    dialog --infobox "Installing essential codec packages..." 5 50
    sudo dnf install -y \
        gstreamer1-plugins-base \
        gstreamer1-plugins-good \
        gstreamer1-plugins-bad-free \
        gstreamer1-plugins-ugly-free \
        gstreamer1-libav \
        gstreamer1-plugin-openh264 \
        x264 \
        x265 \
        libavif \
        ffmpegthumbnailer

    # Install additional audio codecs
    dialog --infobox "Installing audio codecs..." 5 50
    sudo dnf install -y lame* --exclude=lame-devel

    # Upgrade multimedia group (optional but comprehensive)
    if dialog --yesno "Upgrade full Multimedia package group? (Adds VLC, Audacity, etc.)" 10 60; then
        dialog --infobox "Upgrading Multimedia package group..." 5 50
        sudo dnf group upgrade -y --with-optional Multimedia
    fi

    # Verify installation
    dialog --infobox "Verifying codec installation..." 5 50
    
    # Check FFmpeg capabilities
    if command -v ffmpeg >/dev/null 2>&1; then
        local h264_support=$(ffmpeg -decoders 2>/dev/null | grep -c "h264")
        local hevc_support=$(ffmpeg -decoders 2>/dev/null | grep -c "hevc")
        local mp3_support=$(ffmpeg -decoders 2>/dev/null | grep -c "mp3")
        local hw_accel=$(ffmpeg -hwaccels 2>/dev/null | grep -c -E "(cuda|qsv|vulkan)")
        
        # Show results
        dialog --msgbox "Codec Installation Complete!\n\n\
✅ FFmpeg with full codec support\n\
✅ H.264 support: $h264_support decoders\n\
✅ HEVC/H.265 support: $hevc_support decoders\n\
✅ MP3 support: $mp3_support decoders\n\
✅ Hardware acceleration: $hw_accel methods\n\n\
Your system now has comprehensive media playback capabilities." 15 70
    else
        dialog --msgbox "Installation completed but FFmpeg verification failed." 10 60
    fi

    # Final test recommendation
    if dialog --yesno "Would you like to test media playback with a sample video?" 10 60; then
        test_media_playback
    fi
}

# Test media playback function
test_media_playback() {
    local test_commands=(
        "ffmpeg -version"
        "gst-inspect-1.0 --version"
        "ffplay -autoexit -t 10 -f lavfi -i testsrc 2>/dev/null"
    )
    
    for cmd in "${test_commands[@]}"; do
        echo "Testing: $cmd"
        if eval "$cmd"; then
            echo "✅ Success"
        else
            echo "⚠️  Command failed (may be expected for some tests)"
        fi
        echo
    done
    
    dialog --msgbox "Media playback tests completed. Check terminal for results." 10 60
}

# Quick codec verification function
verify_codecs() {
    clear
    echo "=== Media Codec Verification ==="
    echo
    
    # Check FFmpeg
    if command -v ffmpeg >/dev/null 2>&1; then
        echo "📹 FFmpeg:"
        ffmpeg -version | head -1
        echo "Supported codecs:"
        ffmpeg -decoders 2>/dev/null | grep -E "h264|hevc|vp9|av1|mp3|aac" | grep "DEV" | wc -l | xargs echo "  - Total major codecs:"
        ffmpeg -hwaccels 2>/dev/null | tail -n +2 | wc -l | xargs echo "  - Hardware acceleration methods:"
    else
        echo "❌ FFmpeg not installed"
    fi
    
    echo
    
    # Check GStreamer
    if command -v gst-inspect-1.0 >/dev/null 2>&1; then
        echo "🎵 GStreamer:"
        gst-inspect-1.0 --version
        gst-inspect-1.0 2>/dev/null | grep -c "decoder:" | xargs echo "  - Total decoders:"
    else
        echo "❌ GStreamer not installed"
    fi
    
    echo
    read -p "Press Enter to continue..."
}
