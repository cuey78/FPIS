#!/bin/bash
################################################################################
# Plugin metadata (new format)
# menu_title = "gnome fixs"
# menu_function = "tweaks_gnome" 
# menu_order = 
# menu_category = 0
###############################################################################
tweaks_gnome() {
    while true; do
        # Display the menu using dialog
        dialog --clear \
            --backtitle "Fedora 41 GNOME Tweaks" \
            --title "GNOME Tweaks Menu" \
            --menu "Select an option:" 0 0 0 \
            1 "Set Custom Location for GNOME Weather" \
            2 "Set GTK Theme for non GTK Apps" \
            3 "Set GDM login Screen to Primary Monitor" \
            4 "Install Custom set of Gnome Extensions:" \
            b "Back" 2>menu_selection

        # Read the user's choice
        choice=$(<menu_selection)
        rm -f menu_selection

        # Handle the user's choice
        case $choice in
            1)
                gnome_weather
                ;;
            2)
                choose_gtk_theme
                ;;
            3)
                fix_gdm_login
                ;;
            4)  gnome_extensions_main
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

# Set GDM Login to Primary Monitor
fix_gdm_login() {
    clear
    dialog --msgbox "Setting GDM Login to Primary Display" 0 0

    # Get the username of the logged-in user
    local usern
    usern=$(logname)
    if [[ -z "$usern" ]]; then
        dialog --msgbox "Error: Unable to determine the logged-in user." 0 0
        return 1
    fi

    # Get GDM's home directory
    local gdm_home
    gdm_home=$(getent passwd gdm | cut -d: -f6)

    # Check if GDM's home directory was found
    if [[ -z "$gdm_home" ]]; then
        dialog --msgbox "Error: Unable to determine GDM's home directory." 0 0
        return 1
    fi

    # Check if the user's monitors.xml file exists
    local user_monitors_file="/home/$usern/.config/monitors.xml"
    if [[ ! -f "$user_monitors_file" ]]; then
        dialog --msgbox "Error: $user_monitors_file not found. Please configure your displays first." 0 0
        return 1
    fi

    # Create the GDM .config directory if it doesn't exist
    sudo mkdir -p "$gdm_home/.config"

    # Copy the monitors.xml file to GDM's config directory
    if sudo cp -f "$user_monitors_file" "$gdm_home/.config/monitors.xml"; then
        sudo chown gdm:gdm "$gdm_home/.config/monitors.xml"
        dialog --msgbox "GDM login screen monitor configuration updated successfully." 0 0
    else
        dialog --msgbox "Error: Failed to copy monitors.xml to GDM's config directory." 0 0
        return 1
    fi
}

# Sets gtk theme dark/light/etc 
set_gtk_theme() {
    local theme_name="$1"
    
    # Get the actual desktop user (not root)
    if [ -z "$SUDO_USER" ]; then
        desktop_user=$(whoami)
    else
        desktop_user="$SUDO_USER"
    fi
    
    echo "DEBUG: Theme: $theme_name, User: $desktop_user"
    
    # Install package if missing
    if ! rpm -q gnome-themes-extra &>/dev/null; then
        echo "DEBUG: Installing gnome-themes-extra"
        sudo dnf install -y gnome-themes-extra
    fi
    
    echo "DEBUG: Running gsettings command..."
    # Set DBUS_SESSION_BUS_ADDRESS in the sudo command itself
    if sudo -u $desktop_user DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $desktop_user)/bus gsettings set org.gnome.desktop.interface gtk-theme "$theme_name"; then
        echo "DEBUG: Command successful"
        dialog --msgbox "GTK theme set to $theme_name" 0 0
    else
        echo "DEBUG: Command failed"
        dialog --msgbox "Error: Failed to set theme" 0 0
        return 1
    fi
}

# Main Function for Set Gtk Theme 
choose_gtk_theme() {
# Show dialog menu for theme selection
CHOICE=$(dialog --clear --title "GTK Theme Selector" \
    --menu "Choose a GTK theme:" 15 40 4 \
    1 "Adwaita" \
    2 "Adwaita-dark" \
    3 "HighContrast" \
    4 "Raleigh" \
    3>&1 1>&2 2>&3)

clear  # Clear dialog output

# Map user choice to theme name
case $CHOICE in
    1) set_gtk_theme "Adwaita" ;;
    2) set_gtk_theme "Adwaita-dark" ;;
    3) set_gtk_theme "HighContrast" ;;
    4) set_gtk_theme "Raleigh" ;;
    *) echo "No selection made. Exiting."; return 1 ;;
esac
}


# Function to detect GNOME shell version and format it for extensions API
get_gnome_shell_version() {
    local full_version=$(gnome-shell --version | awk '{print $3}')
    local major_version=$(echo "$full_version" | cut -d'.' -f1)
    local minor_version=$(echo "$full_version" | cut -d'.' -f2)
    echo "${major_version}.${minor_version}"
}

# Function to fetch the download URL for a given extension UUID
fetch_download_url() {
    local UUID="$1"
    local SHELL_VERSION=$(get_gnome_shell_version)
    local API_URL="https://extensions.gnome.org/extension-info/?uuid=${UUID}&shell_version=${SHELL_VERSION}"
    
    echo "Detected GNOME Shell version: $SHELL_VERSION" >&2
    echo "Fetching extension: $UUID" >&2
    
    local DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r '.download_url')
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        echo "Error: Unable to fetch download URL for extension $UUID with GNOME $SHELL_VERSION." >&2
        return 1
    fi
    echo "https://extensions.gnome.org${DOWNLOAD_URL}"
}

# Function to install GNOME extensions from the array
install_gnome_extensions() {
    local USER=$(logname)  # Capture the current user
    
    # Loop through the extensions in the array and install them
    for EXTENSION_UUID in "${EXTENSIONS[@]}"; do
        # Check if the UUID is not empty
        if [ -n "$EXTENSION_UUID" ]; then
            echo "Downloading and installing extension: $EXTENSION_UUID"
            
            # Fetch the download URL for the extension
            DOWNLOAD_URL=$(fetch_download_url "$EXTENSION_UUID")
            if [ -z "$DOWNLOAD_URL" ]; then
                echo "Skipping extension $EXTENSION_UUID due to missing download URL."
                continue
            fi
            
            # Download the extension
            wget -O /tmp/${EXTENSION_UUID}.zip "$DOWNLOAD_URL"
            
            # Check if the download was successful
            if [ ! -f "/tmp/${EXTENSION_UUID}.zip" ]; then
                echo "Error: Failed to download extension $EXTENSION_UUID."
                continue
            fi
            
            # Install the extension using gnome-extensions tool
            # Suppress connection errors - they're normal in script context
            sudo -u $USER gnome-extensions install /tmp/${EXTENSION_UUID}.zip 2>/dev/null
            
            # Enable the extension (also suppress connection errors)
            sudo -u $USER gnome-extensions enable "$EXTENSION_UUID" 2>/dev/null
            
            # Clean up the downloaded zip file
            rm /tmp/${EXTENSION_UUID}.zip
            
            echo "Completed: $EXTENSION_UUID"
            echo "------------------------------------------"
        else
            echo "Skipping empty UUID in extensions array."
        fi
    done

    echo "Installation complete."
    echo "Note: Some 'Failed to connect to GNOME Shell' messages are normal in script context."
    echo "Extensions should be installed and will be active after restarting GNOME Shell (Alt+F2, then 'r')"
}

gnome_extensions_main(){
    # Define the array of GNOME extension UUIDs
    EXTENSIONS=(
        "openbar@neuromorph"
        "dash-to-dock@micxgx.gmail.com"
        "add-to-desktop@tommimon.github.com"
        "trayIconsReloaded@selfmade.pl"
        "auto-accent-colour@Wartybix"
        "reboottouefi@ubaygd.com"
        "no-overview@fthx"
        "accent-directories@taiwbi.com"
        "lan-ip-address@mrhuber.com"
        "editdesktopfiles@dannflower"
        "tiling-assistant@leleat-on-github"
        "caffeine@patapon.info"
        "gamemodeshellextension@trsnaqe.com"
        "quick-settings-audio-panel@rayzeq.github.io"
        "launch-new-instance@gnome-shell-extensions.gcampax.github.com"
        "appindicatorsupport@rgcjonas.gmail.com"
        "move-to-next-screen@wosar.me"
        "app-grid-wizard@mirzadeh.pro"
        "blur-my-shell@aunetx"
        "rounded-window-corners@fxgn"
    )
    
    # Call the function to install GNOME extensions
    install_gnome_extensions
}

gnome_weather() {
    # Get the actual desktop user (not root)
    if [ -z "$SUDO_USER" ]; then
        desktop_user=$(whoami)
    else
        desktop_user="$SUDO_USER"
    fi
    
    # Check if GNOME Weather is installed
    if command -v gnome-weather &>/dev/null; then
        system=1
    fi

    if flatpak list --user | grep -q org.gnome.Weather; then
        flatpak=1
    fi

    if [[ -z $system && -z $flatpak ]]; then
        dialog --msgbox "GNOME Weather isn't installed" 0 0
        return 1
    fi

    language=$(locale | sed -n 's/^LANG=\([^_]*\).*/\1/p')

    if [[ -n "$*" ]]; then
        query="$*"
    else
        query=$(dialog --inputbox "Enter location:" 0 0 --stdout)
    fi

    query="$(echo "$query" | sed 's/ /+/g')"
    request=$(curl -s "https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1" -H "Accept-Language: $language")

    if [[ $request == "[]" ]]; then
        dialog --msgbox "No locations found, consider removing some search terms" 0 0
        return 1
    fi

    location_name=$(echo "$request" | sed 's/.*"display_name":"//' | sed 's/".*//')
    dialog --yesno "If this is not the location you wanted, consider adding search terms.\n\nAre you sure you want to add \"$location_name\"?" 10 60
    
    if [[ $? -ne 0 ]]; then
        dialog --msgbox "Not adding location" 0 0
        return 1
    else
        dialog --msgbox "Adding location" 0 0
    fi

    id=$(echo "$request" | sed 's/.*"place_id"://' | sed 's/,.*//')
    details=$(curl -s "https://nominatim.openstreetmap.org/details.php?place_id=$id&format=json")

    if [[ $details == *"name:$language"* ]]; then
        name=$(echo "$details" | sed "s/.*\"name:$language\": \"//" | sed 's/\".*//')
    else
        name=$(echo "$details" | sed 's/.*"name": "//' | sed 's/".*//')
    fi

    lat=$(echo "$request" | sed 's/.*"lat":"//' | sed 's/".*//')
    lat=$(echo "$lat / (180 / 3.141592654)" | bc -l)

    lon=$(echo "$request" | sed 's/.*"lon":"//' | sed 's/".*//')
    lon=$(echo "$lon / (180 / 3.141592654)" | bc -l)

    # Correct the location format
    location="<(uint32 2, <('$name', '', false, [($lat, $lon)], @a(dd) [])>)>"

    if [[ $system == 1 ]]; then
        # Export the user's DBUS_SESSION_BUS_ADDRESS to interact with their GNOME session
        export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $desktop_user)/bus
        
        locations=$(sudo -u $desktop_user gsettings get org.gnome.Weather locations)

        if [[ "$locations" != "@av []" ]]; then
            updated_locations=$(echo "$locations" | sed "s|>]$|>, $location]|")
            sudo -u $desktop_user gsettings set org.gnome.Weather locations "$updated_locations"
        else
            sudo -u $desktop_user gsettings set org.gnome.Weather locations "[$location]"
        fi
    fi

    if [[ $flatpak == 1 ]]; then
        # For Flatpak, we need to use the flatpak run command
        export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $desktop_user)/bus
        
        locations=$(sudo -u $desktop_user flatpak run --command=gsettings org.gnome.Weather get org.gnome.Weather locations)

        if [[ "$locations" != "@av []" ]]; then
            updated_locations=$(echo "$locations" | sed "s|>]$|>, $location]|")
            sudo -u $desktop_user flatpak run --command=gsettings org.gnome.Weather set org.gnome.Weather locations "$updated_locations"
        else
            sudo -u $desktop_user flatpak run --command=gsettings org.gnome.Weather set org.gnome.Weather locations "[$location]"
        fi
    fi
    
    dialog --msgbox "Location '$name' added successfully to GNOME Weather!" 0 0
}
