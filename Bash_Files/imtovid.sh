#!/bin/bash

# Function to check and install dependencies
check_dependencies() {
    local deps=("ffmpeg" "yad" "bc")
    local missing=()
    local install_cmd="sudo apt install -y"
    local gui_available=1
    
    # Check if we're running in a GUI environment
    if [ -z "$DISPLAY" ]; then
        gui_available=0
    fi

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
            install_cmd+=" $dep"
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        # Prepare installation instructions
        local message="Missing required packages: ${missing[*]}"
        message+="\n\nTo install, run:\n  ${install_cmd}"
        message+="\n\nOn Ubuntu 22.04, yad is not installed by default."
        
        if [ $gui_available -eq 1 ]; then
            # Try to use yad if available
            if command -v yad &> /dev/null; then
                yad --title="Dependencies Missing" \
                    --text="$message" \
                    --button="Copy Command to Clipboard":0 \
                    --button="Open Terminal":1 \
                    --width=500 --height=200
                    
                response=$?
                if [ $response -eq 0 ]; then
                    echo -n "$install_cmd" | xclip -selection clipboard
                    yad --info --title="Command Copied" \
                        --text="Install command copied to clipboard!\n\nPaste in terminal with Ctrl+Shift+V" \
                        --button=gtk-ok:0
                elif [ $response -eq 1 ]; then
                    x-terminal-emulator -e bash -c "echo 'Run this command:'; echo '$install_cmd'; exec bash"
                fi
            # Fallback to zenity
            elif command -v zenity &> /dev/null; then
                zenity --error --title="Dependencies Missing" \
                    --text="$message" \
                    --ok-label="Copy Command to Clipboard" \
                    --extra-button="Open Terminal" \
                    --no-wrap
                    
                response=$?
                if [ $response -eq 0 ]; then
                    echo -n "$install_cmd" | xclip -selection clipboard
                    zenity --info --title="Command Copied" \
                        --text="Install command copied to clipboard!\n\nPaste in terminal with Ctrl+Shift+V"
                elif [ $response -eq 1 ]; then
                    x-terminal-emulator -e bash -c "echo 'Run this command:'; echo '$install_cmd'; exec bash"
                fi
            else
                # Terminal fallback in GUI environment
                zenity --error --title="Dependencies Missing" \
                    --text="$message" \
                    --ok-label="Exit"
            fi
        else
            # Terminal fallback
            echo -e "\nERROR: $message"
            echo -e "\nYou can install missing packages with:"
            echo "  $install_cmd"
            read -p "Press enter to exit..."
        fi
        exit 1
    fi
}

# Function to parse ffmpeg progress and estimate time
parse_ffmpeg_progress() {
    local total_frames=0
    local duration=0
    
    # Get total frames and duration if available
    if [ -n "$1" ]; then
        total_frames="$1"
    fi
    if [ -n "$2" ]; then
        duration="$2"
    fi
    
    while read -r line; do
        # Output progress to file for yad to read
        if [[ $line =~ frame=[[:space:]]*([0-9]+) ]]; then
            current_frame="${BASH_REMATCH[1]}"
            if [ "$total_frames" -gt 0 ]; then
                percent=$((100 * 10#$current_frame / 10#$total_frames))
                # Calculate estimated time remaining
                if [ "$percent" -gt 0 ] && [ "$(echo "$duration > 0" | bc -l)" -eq 1 ]; then
                    elapsed_time=$(echo "scale=2; $duration * $percent / 100" | bc)
                    remaining_time=$(echo "scale=2; $duration - $elapsed_time" | bc)
                    hours=$(echo "scale=0; $remaining_time/3600" | bc)
                    minutes=$(echo "scale=0; ($remaining_time%3600)/60" | bc)
                    seconds=$(echo "scale=0; $remaining_time%60" | bc)
                    remaining_time_str=$(printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds")
                    echo "$percent"
                    echo "# Processed $current_frame/$total_frames frames ($percent%). Estimated time remaining: $remaining_time_str"
                else
                    echo "$percent"
                    echo "# Processed $current_frame/$total_frames frames ($percent%)"
                fi
            else
                echo "# Processed frame $current_frame"
            fi
        fi
    done
}

# Function to create safe file list
create_safe_filelist() {
    local src_dir="$1"
    local output_file="$2"
    
    # Create a safe file list in the output directory
    local filelist="${output_file%.*}_filelist.txt"
    > "$filelist"
    
    # Counter for progress
    local counter=0
    
    # Create mapping file
    local mapping="${output_file%.*}_mapping.txt"
    > "$mapping"
    
    # Find and process images
    find "$src_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0 | \
        sort -z | while IFS= read -r -d $'\0' file; do
            counter=$((counter+1))
            # Use relative path to avoid issues
            rel_path=$(realpath --relative-to="$(dirname "$output_file")" "$file")
            # Escape single quotes by doubling them
            safe_path=$(echo "$rel_path" | sed "s/'/''/g")
            printf "file '%s'\n" "$safe_path" >> "$filelist"
            # Store mapping with original size
            filesize=$(stat -c%s "$file")
            echo "$counter|$rel_path|$filesize" >> "$mapping"
        done
    
    echo "$filelist"
}

# Function to convert images to video with quality preservation
images_to_video() {
    local src_dir output_file

    LOGFILE="${HOME}/imtovid_error.log"

    log_error() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
    }

    src_dir=$(yad --file --directory --title="Select Image Source Directory" \
        --width=600 --height=400)
    [ -z "$src_dir" ] && exit 1

    output_file=$(yad --file --save --confirm-overwrite \
        --title="Select Output Video File" \
        --filename="data_transfer.mp4" \
        --file-filter="MP4 files | *.mp4" \
        --width=600 --height=400)
    [ -z "$output_file" ] && exit 1
    [[ "$output_file" != *.mp4 ]] && output_file="$output_file.mp4"

    # Prepare a temp directory for renaming
    temp_dir="$(dirname "$output_file")/temp_images_$(date +%s)"
    mkdir -p "$temp_dir"

    # Copy and rename images to sequential numbers
    count=0
    mapping="${output_file%.*}_mapping.txt"
    > "$mapping"
    find "$src_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0 | \
        sort -z | while IFS= read -r -d $'\0' file; do
            count=$((count+1))
            ext="${file##*.}"
            newname=$(printf "%08d.%s" "$count" "$ext")
            # Preserve original file modification time
            cp -p "$file" "$temp_dir/$newname"
            # Store mapping with original size
            filesize=$(stat -c%s "$file")
            echo "$count|$file|$filesize" >> "$mapping"
        done

    # Checkpoint: verify all images copied
    total=$(ls "$temp_dir" | wc -l)
    if [ "$total" -eq 0 ]; then
        yad --error --title="Error" --text="No images found in the selected directory." \
            --button=gtk-ok:0
        log_error "No images found in $src_dir"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Create filelist for ffmpeg
    filelist="${output_file%.*}_filelist.txt"
    > "$filelist"
    for img in "$temp_dir"/*; do
        # Escape single quotes for ffmpeg file list
        safe_path=$(echo "$(realpath --relative-to="$(dirname "$output_file")" "$img")" | sed "s/'/''/g")
        printf "file '%s'\n" "$safe_path" >> "$filelist"
    done

    # Get total frames (same as total images)
    total_frames=$total
    # Estimate duration (assuming 25fps)
    duration=$(echo "scale=2; $total_frames / 25" | bc)

    # Run ffmpeg to create video with high quality settings
    (
        # Use lossless settings for maximum quality preservation
        ffmpeg -y -f concat -safe 1 -i "$filelist" \
            -c:v libx264 -preset veryslow -crf 18 \
            -vf "fps=25,format=yuv420p" \
            "$output_file" 2>&1 | \
            parse_ffmpeg_progress "$total_frames" "$duration"
        echo $? > "${filelist}.status"
    ) | yad --progress --title="Creating Video" \
             --text="Encoding images to video with high quality settings..." \
             --percentage=0 --auto-close --no-cancel \
             --width=400 --height=100

    # Check result
    local ffmpeg_exit=$(cat "${filelist}.status" 2>/dev/null)

    if [ "$ffmpeg_exit" -eq 0 ] && [ -f "$output_file" ]; then
        yad --info --title="Success" \
            --text="Video created successfully with high quality settings:\n$output_file" \
            --button=gtk-ok:0
        # Clean up
        rm -rf "$temp_dir" "$filelist" "${filelist}.status"
    else
        yad --error --title="Error" \
            --text="Video creation failed (code $ffmpeg_exit)\nCheck $LOGFILE for details." \
            --button=gtk-ok:0
        # Preserve filelist and temp_dir for debugging
        yad --info --title="Debug" \
            --text="File list and temp images preserved at:\n$filelist\n$temp_dir" \
            --button=gtk-ok:0
        log_error "Video creation failed (code $ffmpeg_exit)"
    fi
}

# Function to verify extracted images
verify_extracted_images() {
    local mapping_file="$1"
    local extract_dir="$2"
    local total_expected=$(wc -l < "$mapping_file")
    local restored_count=0
    local mismatch_count=0
    local missing_count=0

    while IFS='|' read -r num original_path original_size; do
        filename=$(basename "$original_path")
        extracted_file="$extract_dir/$filename"
        
        if [ -f "$extracted_file" ]; then
            restored_count=$((restored_count + 1))
            # Verify file size
            extracted_size=$(stat -c%s "$extracted_file")
            if [ "$extracted_size" -ne "$original_size" ]; then
                mismatch_count=$((mismatch_count + 1))
                echo "Size mismatch: $filename (Original: $original_size, Extracted: $extracted_size)" >> "$extract_dir/verification.log"
            fi
        else
            missing_count=$((missing_count + 1))
            echo "Missing file: $filename" >> "$extract_dir/verification.log"
        fi
    done < "$mapping_file"

    # Create verification report
    {
        echo "Verification Report"
        echo "==================="
        echo "Total expected images: $total_expected"
        echo "Successfully restored: $restored_count"
        echo "Size mismatches: $mismatch_count"
        echo "Missing files: $missing_count"
        echo ""
        echo "Details in verification.log"
    } > "$extract_dir/verification_report.txt"
    
    # Show detailed results in popup
    if [ "$restored_count" -eq "$total_expected" ] && [ "$mismatch_count" -eq 0 ]; then
        yad --info --title="Complete Success" \
            --text="Successfully restored all $total_expected images with matching file sizes!\n\nOutput directory: $extract_dir" \
            --button=gtk-ok:0
    else
        yad --info --title="Restoration Summary" \
            --text="Restored $restored_count out of $total_expected images.\n\n• $mismatch_count files have size differences\n• $missing_count files missing\n\nSee verification_report.txt for details." \
            --button=gtk-ok:0
    fi
}

# Function to convert video back to images
video_to_images() {
    local input_file output_dir
    
    input_file=$(yad --file --title="Select Video File" \
        --file-filter="MP4 files | *.mp4" \
        --width=600 --height=400)
    [ -z "$input_file" ] && exit 1
    
    output_dir=$(yad --file --directory --title="Select Output Directory" \
        --width=600 --height=400)
    [ -z "$output_dir" ] && exit 1
    
    # Look for mapping file
    local mapping_file=$(yad --file --title="Select Mapping File (if available)" \
        --file-filter="Text files | *.txt" \
        --width=600 --height=400)
    
    if [ -n "$mapping_file" ]; then
        # Extract with original filenames
        local extract_dir="$output_dir/restored_images_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$extract_dir"
        
        # First extract to temp numbered files
        local temp_dir="$extract_dir/temp"
        mkdir -p "$temp_dir"
        
        # Get frame count from mapping
        local total=$(wc -l < "$mapping_file")
        
        # Get video duration for progress estimation
        local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null || echo "0")
        
        (
            # Extract numbered frames with high quality settings
            ffmpeg -i "$input_file" -vsync 0 -start_number 1 \
                   -q:v 1 -f image2 "$temp_dir/%08d.jpg" 2>&1 | \
                parse_ffmpeg_progress "$total" "$duration"
            
            # Restore original filenames
            while IFS='|' read -r num original_path original_size; do
                padded_num=$(printf "%08d" "$num")
                if [ -f "$temp_dir/${padded_num}.jpg" ]; then
                    filename=$(basename "$original_path")
                    cp "$temp_dir/${padded_num}.jpg" "$extract_dir/$filename"
                fi
            done < "$mapping_file"
            
            # Clean up temp files
            rm -rf "$temp_dir"
            
            echo $? > "$extract_dir/status.txt"
        ) | yad --progress --title="Extracting Images" \
               --text="Restoring $total images from video with high quality..." \
               --percentage=0 --auto-close --no-cancel \
               --width=400 --height=100
        
        # Check result and verify
        local extracted=$(find "$extract_dir" -type f -name "*.*" | wc -l)
        if [ "$extracted" -gt 0 ]; then
            # Verify all images were restored correctly
            verify_extracted_images "$mapping_file" "$extract_dir"
        else
            yad --error --title="Error" --text="Failed to restore any images" \
                --button=gtk-ok:0
        fi
    else
        # Extract with default numbered names
        local extract_dir="$output_dir/extracted_images_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$extract_dir"
        
        # Get frame count
        local total=$(ffprobe -v error -select_streams v:0 -count_frames \
            -show_entries stream=nb_read_frames -print_format csv "$input_file" 2>/dev/null | \
            cut -d',' -f2)
        [ -z "$total" ] && total=0
        
        # Get video duration for progress estimation
        local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null || echo "0")
        
        (
            # Extract with high quality settings
            ffmpeg -i "$input_file" -vsync 0 -start_number 0 \
                   -q:v 1 -f image2 "$extract_dir/frame_%08d.jpg" 2>&1 | \
                parse_ffmpeg_progress "$total" "$duration"
            echo $? > "$extract_dir/status.txt"
        ) | yad --progress --title="Extracting Images" \
               --text="Extracting $total frames from video with high quality..." \
               --percentage=0 --auto-close --no-cancel \
               --width=400 --height=100
        
        # Check result
        local extracted=$(find "$extract_dir" -type f -name "*.jpg" | wc -l)
        if [ "$extracted" -gt 0 ]; then
            yad --info --title="Success" \
                --text="Successfully extracted $extracted images:\n$extract_dir" \
                --button=gtk-ok:0
        else
            yad --error --title="Error" --text="Failed to extract images" \
                --button=gtk-ok:0
        fi
    fi
}

# Main function
main() {
    check_dependencies
    
    local mode=$(yad --list --title="Data Transfer Converter" \
        --text="Select operation mode:" \
        --column="Mode" "Images to Video" "Video to Images" \
        --height=200 --width=300 --no-headers \
        --button=gtk-ok:0 --button=gtk-cancel:1)
    
    # Check if user cancelled
    if [ $? -ne 0 ]; then
        exit 0
    fi
    
    case "$mode" in
        "Images to Video"*) images_to_video ;;
        "Video to Images"*) video_to_images ;;
        *) exit 0 ;;
    esac
}

main
# End of script
# additional comments
# request to create terminal prompt for missing dependencies and provide options to copy install command or open terminal
# to automate script, need terminal prompts
# to be user-friendly, use yad for GUI prompts and zenity as fallback
# version control changes
# 2.2 - Added support for lossless image processing, improved file handling
# 2.1 - Added error logging, improved progress estimation, and enhanced GUI interactions
# 2.0 - Major refactor, added GUI with yad, improved error handling
# 1.3 - Added support for extracting images from video files, image file name preservation, and error log creation
# 1.2 - pathing issues fixed, caused due to special characters in file names ( like spaces, quotes, etc. )
# 1.1 - pathing issues fixed, caused due to zenity not handling relative paths correctly
# 1.0 - Initial version with basic functionality