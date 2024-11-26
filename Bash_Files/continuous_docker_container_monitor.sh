#!/bin/bash

# Define the name or ID of the Docker container you want to monitor
CONTAINER_NAME="jidoka-kompass_mvc-1"

# Get the current timestamp
current_time=$(date +%s)

# Get the status of the container
container_status=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME")

# Proceed only if the container is not running
if [ "$container_status" != "running" ]; then
    # Get the time the container exited
    container_exit_time=$(docker inspect -f '{{.State.FinishedAt}}' "$CONTAINER_NAME")
    
    # Convert the exit time to a timestamp
    container_exit_timestamp=$(date -d "$container_exit_time" +%s)
    
    # Calculate the difference in seconds
    time_difference=$((current_time - container_exit_timestamp))
    
    # Check if the container has been down for more than 5 minutes (300 seconds)
    if [ "$time_difference" -gt 300 ]; then
        echo "Container has been exited for more than 5 minutes. Restarting the container..."
        RESTART_TIME=`date`
        echo "${CONTAINER_NAME} restarted at ${RESTART_TIME}" >> /jidoka/mvc_restart.log
        docker start "$CONTAINER_NAME"
    else
        echo "Container has not been exited for more than 5 minutes. No action taken."
    fi
else
    echo "Container is running. No action needed."
fi
