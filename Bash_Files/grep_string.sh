#!/bin/bash

# Read all .log files in the current directory
LOG_FILES=$(ls *.log)
# Iterate over each file
for LOG_FILE in $LOG_FILES
do
    # Print the file name
    echo "Processing $LOG_FILE"
    # Grep the word "emergency" in the file
    # grep "wait for PLC to become available" $LOG_FILE
    grep "Unsure" $LOG_FILE

    # Print empty line
    echo ""
done
