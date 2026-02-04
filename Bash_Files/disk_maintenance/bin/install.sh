#!/bin/bash
# Install script for utility

# Check if iostat command is available
if ! command -v iostat &> /dev/null; then
    echo "iostat command not found. Please install sysstat package."
    exit 1
fi

# Check if the crontab command is available
if ! command -v crontab &> /dev/null; then
    echo "crontab command not found. Please install cron."
    exit 1
fi

DISK_TYPE=$(jq -r '.disk_type' "$CONFIG_FILE")
UTIL_NAME="disk_cleanup"
if [ "$DISK_TYPE" == "SSD" ]
then
    UTIL_CMD="/jidoka/disk_maintenance/bin/disk_cleanup.sh --ssd"
else
    UTIL_CMD="/jidoka/disk_maintenance/bin/disk_cleanup.sh"
fi
DESKTOP_FILE="/jidoka/disk_maintenance/bin/Apps/disk_check.desktop"
CONFIG_FILE="/jidoka/disk_maintenance/config/disk_cleanup_config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file $CONFIG_FILE not found."
    exit 1
fi

if [ -f "$DESKTOP_FILE" ]
then
    echo "Copying Disk check executable file to desktop"
    cp -v $DESKTOP_FILE $HOME/Desktop/
else
    echo "ERROR: $DESKTOP_FILE is not present"
fi

DAYS_INTERVAL=$(jq -r '.days_interval' "$CONFIG_FILE")
# Validate the days interval (should be either * or a positive integer)
if ! [[ "$DAYS_INTERVAL" =~ ^\*|^[1-9][0-9]*$ ]]; then
    echo "Invalid days interval in $CONFIG_FILE. Expected '*' or a positive integer."
    exit 1
fi
# If the days interval is a number, check if it's between 1 and 7
if [[ "$DAYS_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
    if [ "$DAYS_INTERVAL" -lt 1 ] || [ "$DAYS_INTERVAL" -gt 7 ]; then
        echo "Invalid days interval in $CONFIG_FILE. Expected a number between 1 and 7."
        exit 1
    fi
fi
# If DAYS_INTERVAL is not *, convert it to a cron format
if [[ "$DAYS_INTERVAL" != "*" ]]; then
    DAYS_INTERVAL="*/$DAYS_INTERVAL"
fi

DAILY_RUN_TIME=$(jq -r '.daily_run_time' "$CONFIG_FILE")
if [[ "$DAILY_RUN_TIME" == "null" ]]; then
    echo "No daily run time defined in $CONFIG_FILE."
    exit 1
fi

# Validate the daily run time format (HH:MM)
if ! [[ "$DAILY_RUN_TIME" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
    echo "Invalid daily run time format in $CONFIG_FILE. Expected format is HH:MM."
    exit 1
fi

# Convert the daily run time to cron format
HOUR=$(echo "$DAILY_RUN_TIME" | cut -d':' -f1)
MINUTE=$(echo "$DAILY_RUN_TIME" | cut -d':' -f2)

# Crontab job command
CRON_CMD=${UTIL_CMD}
CRON_JOB="$MINUTE $HOUR $DAYS_INTERVAL * * $CRON_CMD"

# Ensure the script is executable
if [ ! -x "$CRON_CMD" ]; then
    chmod +x "$CRON_CMD"
fi

# Extract current crontab
CURRENT_CRONTAB=$(crontab -l 2>/dev/null)

# Check if an entry exists for the backup script
EXISTING_JOB=$(echo "$CURRENT_CRONTAB" | grep "$CRON_CMD")

if [[ -n "$EXISTING_JOB" ]]
then
    if [[ "$EXISTING_JOB" == "$CRON_JOB" ]]
    then
        echo "${UTIL_NAME} is already enabled in crontab with correct timing."
    else
        echo "Updating ${UTIL_NAME} timing in crontab."
        # Remove the old job and add the new one
        UPDATED_CRONTAB=$(echo "$CURRENT_CRONTAB" | grep -v "$CRON_CMD"; echo "$CRON_JOB")
        echo "$UPDATED_CRONTAB" | crontab -
        if [ $? -eq 0 ]; then
            echo "${UTIL_NAME} timing updated in crontab successfully."
        else
            echo "Failed to update crontab."
            exit 1
        fi
    fi
else
    echo "Adding ${UTIL_NAME} script to crontab."
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    if [ $? -eq 0 ]; then
        echo "Cloud backup added to crontab successfully."
    else
        echo "Failed to add ${UTIL_NAME} to crontab."
        exit 1
    fi
fi
