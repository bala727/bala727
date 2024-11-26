#!/bin/bash

# Script to stop and start a Docker container

# Define the name of the Docker container
CONTAINER_NAME="your_container_name"

# Function to stop the Docker container
stop_container() {
    echo "Stopping Docker container: $CONTAINER_NAME"
    docker stop $CONTAINER_NAME
}

# Function to start the Docker container
start_container() {
    echo "Starting Docker container: $CONTAINER_NAME"
    docker start $CONTAINER_NAME
}

# Check if the Docker container is already running
if docker ps --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
    # Container is running, so stop it
    stop_container
else
    echo "Docker container $CONTAINER_NAME is not running."
fi

# Start the Docker container
start_container

