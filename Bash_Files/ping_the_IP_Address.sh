#!/bin/bash

# Replace this with the IP address you want to ping
ip_address="172.32.131.110"

# Replace this with the path to your log file
log_file="/jidoka/v3.4.10/logs/ping.log"

# Set the interval (in seconds) between pings and log entries
interval=1

# Function to get the current timestamp
get_timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# Main loop
while true; do
    timestamp=$(get_timestamp)
    ping_result=$(ping -c 1 $ip_address)
    echo "$timestamp - $ping_result" >> "$log_file"
    sleep "$interval"  # Adjust the interval here
done
