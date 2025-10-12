WIFI_SSID=""
REMOTE_SERVER=""
REMOTESHARE_1=""
LOCALMOUNT_1=""
REMOTESHARE_2=""
LOCALMOUNT_2=""

echo $REMOTE_SERVER  # Corrected: echo the variable's value

# Function to check if WiFi is connected
check_wifi_connected() {
    if nmcli | grep -q "$WIFI_SSID"; then
        return 0  # WiFi connected
    else
        return 1  # WiFi not connected
    fi
}

# Function to check if the server is reachable
check_server_reachable() {
    if ping -c 1 "$REMOTE_SERVER" >/dev/null 2>&1; then
        return 0  # Server reachable
    else
        return 1  # Server unreachable
    fi
}

# Main loop
while :
do
    # Check if WiFi is connected
    if check_wifi_connected; then
        echo "WiFi connected"

        # Check if the server is reachable
        if check_server_reachable; then
            echo "Server reachable"
            break  # Exit the loop if both WiFi and server are reachable
        else
            echo "Server not reachable, retrying in 5 seconds..."
        fi
    else
        echo "WiFi not connected, retrying in 5 seconds..."
    fi

    # Wait for 5 seconds before retrying
    sleep 5
done

# If both WiFi and server are reachable, connect to NFS shares
for (( i=1; i<=num_shares; i++ )); do
    eval "mount -t nfs \"\$REMOTE_SERVER:\${REMOTESHARE_$i}\" \"\${LOCALMOUNT_$i}\""
done
