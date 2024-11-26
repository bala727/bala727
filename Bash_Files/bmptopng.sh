#!/bin/bash

# Check if ImageMagick is installed
if ! command -v convert &> /dev/null; then
    echo "ImageMagick is not installed. Please install it using 'sudo apt-get install imagemagick'."
    exit 1
fi

# Directory to start the search (use current directory if not specified)
DIR=${1:-.}

# Find and process all BMP files in the directory and its subdirectories
find "$DIR" -type f -name "*.bmp" | while read -r file; do
    # Get the directory and base name of the file
    dir_name=$(dirname "$file")
    base_name=$(basename "$file" .bmp)

    # Convert BMP to PNG
    convert "$file" "$dir_name/$base_name.png"

    # Check if the conversion was successful
    if [ $? -eq 0 ]; then
        echo "Converted $file to $dir_name/$base_name.png"
    else
        echo "Failed to convert $file"
    fi
done
