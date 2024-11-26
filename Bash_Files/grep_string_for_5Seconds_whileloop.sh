#!/bin/bash

while true; do
    # Your grep command goes here
    result=$(your_grep_command_here)

    # Check if there is any result
    if [ -n "$result" ]; then
        echo "$result"
    else
        echo "No match found."
    fi

    # Sleep for 5 seconds
    sleep 5
done

