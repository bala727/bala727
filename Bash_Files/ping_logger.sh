#!/bin/bash

# Define the IP address and log file
IP_ADDRESS="192.168.3.200"  # Replace with the desired IP address
LOG_FILE="ping_log.log"

# Function to log ping results with timestamp
log_ping() {
    while true; do
        # Get the current timestamp
        TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

        # Ping the IP address and extract the result
        PING_RESULT=$(ping -c 1 $IP_ADDRESS | awk -F'[= ]' '/time=/{print $10 " ms"}')

        # Check if ping was successful
        if [ -z "$PING_RESULT" ]; then
            PING_RESULT="Request timed out"
        fi

        # Log the timestamp and ping result
        echo "$TIMESTAMP - $PING_RESULT" | tee -a $LOG_FILE

        # Wait for 1 second before the next ping
        sleep 1
    done
}

# Run the log_ping function
log_ping
