#!/bin/bash

# Function to check and prompt to install missing dependencies
check_dependencies() {
    local deps=("zenity" "rsync" "bc" "lsblk" "mkfs.vfat" "udisksctl" "xclip" "stdbuf")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        local install_cmd="sudo apt install -y ${missing[*]}"
        echo "Missing dependencies: ${missing[*]}"
        echo -e "\nTo install them, run:\n$install_cmd\n"
        read -p "Press Enter to copy the command to clipboard, or Ctrl+C to abort..."
        echo "$install_cmd" | xclip -selection clipboard
        zenity --info --width=400 --height=250 --title="Missing Dependencies" --text="The installation command has been copied to your clipboard."
        exit 1
    fi
}

# Function to check filesystem type of a device
check_filesystem_type() {
    local device_path="$1"
    
    # Get the actual block device (remove partition number if present)
    local base_device=$(echo "$device_path" | sed 's/[0-9]*$//')
    
    # Check if device exists
    if [ ! -b "$base_device" ]; then
        echo "unknown"
        return 1
    fi
    
    # Use lsblk to get filesystem information
    local fs_type=$(lsblk -no FSTYPE "$device_path" 2>/dev/null)
    
    if [ -z "$fs_type" ]; then
        # If lsblk fails, try blkid
        fs_type=$(blkid -o value -s TYPE "$device_path" 2>/dev/null)
    fi
    
    echo "${fs_type:-unknown}"
}

# Function to check USB ports and display information
check_usb_port() {
    # Get USB tree information
    local usb_tree=$(lsusb -t)
    local found_usb=0
    local usb2_detected=0
    local usb3_detected=0
    local usb_info=""
    local fs_info=""

    # Get all USB storage devices from lsblk
    local usb_devices=$(lsblk -f -o NAME,MOUNTPOINT,FSTYPE,TRAN | grep -w usb | awk '{print $1}')

    while IFS= read -r line; do
        if echo "$line" | grep -q "Class=Mass Storage"; then
            found_usb=1
            speed=$(echo "$line" | grep -oE '[0-9]+M')

            case "$speed" in
                10000M|5000M)
                    usb_speed="USB 3.0"
                    usb3_detected=1
                    ;;
                480M)
                    usb_speed="USB 2.0"
                    usb2_detected=1
                    ;;
                *)
                    usb_speed="Unknown"
                    ;;
            esac

            # Extract device info
            dev_num=$(echo "$line" | grep -oE 'Dev [0-9]+' | awk '{print $2}')
            bus_num=$(echo "$prev_line" | grep -oE 'Bus [0-9]+' | awk '{print $2}')
            bus_num=$(printf "%03d" $((10#$bus_num)))
            dev_num=$(printf "%03d" $((10#$dev_num)))
            device_path="/dev/bus/usb/$bus_num/$dev_num"

            model=$(lsusb | grep -E "^Bus $bus_num Device $dev_num" | cut -d' ' -f7-)
            [ -z "$model" ] && model="Unknown Model"
            
            # Get filesystem type using lsblk -f
            fs_info=""
            for dev in $usb_devices; do
                if lsblk -f -o PATH | grep -q "/dev/$dev"; then
                    fs_type=$(lsblk -f -o FSTYPE /dev/$dev | tail -1)
                    if [ -n "$fs_type" ]; then
                        if [ -n "$fs_info" ]; then
                            fs_info+=", $fs_type"
                        else
                            fs_info="$fs_type"
                        fi
                    fi
                fi
            done
            
            if [ -z "$fs_info" ]; then
                mounted_point=$(lsblk -f -o MOUNTPOINT /dev/$dev 2>/dev/null | tail -1)
                [ -n "$mounted_point" ] && fs_info="Mounted but unknown FS"
            fi
            
            usb_info+="Device: $device_path\nSpeed: $usb_speed\nModel: $model\nFilesystem: ${fs_info:-Not detected}\n\n"
        fi
        prev_line="$line"
    done <<< "$usb_tree"

    if [[ "$found_usb" -eq 0 ]]; then
        zenity --error --width=400 --height=200 --title="USB Info" --text="No USB storage devices detected."
        exit 1
    fi

    # Show USB info with filesystem details
    zenity --info --title="USB Storage Devices" --text="$usb_info" --width=600 --height=300
    
    # Check for FAT filesystems
    if [[ "$fs_info" == *"vfat"* || "$fs_info" == *"msdos"* || "$fs_info" == *"fat"* ]]; then
        zenity --error --width=600 --height=300 --title="FAT Filesystem Warning" \
            --text="The USB device uses a FAT filesystem.\n\nFAT filesystems have limitations:\n- Maximum file size of 4GB\n- No file permissions\n- No journaling (higher risk of corruption)\n\nConsider reformatting to exFAT or NTFS if you need to transfer large files."
        return 1
        exit 1
    fi

    # Show summary popup based on speeds
    if [[ "$usb2_detected" -eq 1 ]]; then
        zenity --error --width=600 --height=300 --title="USB 2.0 Warning" \
            --text="At least one USB device is connected via USB 2.0.\n\nFor faster transfer speeds, consider moving it to a USB 3.0 port or using a USB 3.0 device."
    else
        zenity --info --width=600 --height=300 --title="USB 3.0 Confirmation" \
            --text="All connected USB storage devices are using USB 3.0 ports.\n\nFilesystems detected: ${fs_info:-None}\n\nYou're good to go!"
    fi
    echo "/dev/sdX"  # Replace with actual detected device
    return 0

}

# Function to find common parent directory
find_common_parent() {
    local items=("$@")
    local common_parent=""
    local first_item="${items[0]}"
    
    # If only one item, return its parent directory
    if [ ${#items[@]} -eq 1 ]; then
        if [ -f "${items[0]}" ]; then
            dirname "${items[0]}"
        else
            echo "${items[0]}"
        fi
        return
    fi
    
    # Get the first path component
    common_parent=$(dirname "$first_item")
    
    # Compare with other paths
    for item in "${items[@]}"; do
        item_dir=$(dirname "$item")
        while [[ "$item_dir" != "$common_parent" && "$item_dir" != "/" ]]; do
            item_dir=$(dirname "$item_dir")
        done
        
        if [[ "$item_dir" == "/" ]]; then
            echo ""
            return
        fi
        
        common_parent="$item_dir"
    done
    
    echo "$common_parent"
}

# Function to format size in human-readable format
format_size() {
    local size=$1
    local unit="B"
    if (( size >= 1000 )); then
        size=$(bc -l <<< "$size/1000")
        unit="KB"
    fi
    if (( $(echo "$size >= 1000" | bc -l) )); then
        size=$(bc -l <<< "$size/1000")
        unit="MB"
    fi
    if (( $(echo "$size >= 1000" | bc -l) )); then
        size=$(bc -l <<< "$size/1000")
        unit="GB"
    fi
    printf "%.2f %s" "$size" "$unit"
}

# Function to validate resume paths
validate_resume_paths() {
    local marker_file="$1"
    zenity --question --title="Confirm Resume" \
        --text="Resuming transfer from:\n$(cat "$marker_file" | tr '\n' ' ')\n\nIs this correct?" \
        --width=400
    return $?
}

# Function to get existing transferred size
get_existing_size() {
    local dest="$1"
    local marker_file="$2"
    local total=0
    
    while IFS= read -r item; do
        item_name=$(basename "$item")
        dest_item="$dest/$item_name"
        
        if [ -e "$dest_item" ]; then
            if [ -d "$dest_item" ]; then
                size=$(du -sb "$dest_item" 2>/dev/null | cut -f1)
            else
                size=$(stat -c %s "$dest_item" 2>/dev/null)
            fi
            
            if [[ $size =~ ^[0-9]+$ ]]; then
                total=$((total + size))
            fi
        fi
    done < "$marker_file"
    
    echo $total
}

# Function to get common parent directory
get_common_parent() {
    local paths=("$@")
    local common_parent=$(printf "%s\n" "${paths[@]}" | sed 's/ /\\ /g' | xargs dirname | sort | uniq -c | sort -nr | head -1 | awk '{print $2}')
    echo "$common_parent"
}

# Function to validate resume paths
validate_resume_paths() {
    local marker_file=$1
    local missing_paths=()
    local hostname=$(hostname)
    local all_paths=()
    
    # Read paths from marker file
    while IFS= read -r path; do
        all_paths+=("$path")
        if [ ! -e "$path" ]; then
            missing_paths+=("$path")
        fi
    done < "$marker_file"

    if [ ${#missing_paths[@]} -gt 0 ]; then
        # Get common parent for all paths
        local common_parent=$(get_common_parent "${all_paths[@]}")
        local missing_common_parent=$(get_common_parent "${missing_paths[@]}")
        
        # Show summary instead of full list
        zenity --info --title="Missing Source Paths" \
            --text="Some source paths are missing on $hostname.\n\nCommon path: $common_parent\n\nMissing items in: $missing_common_parent\n\nTotal missing: ${#missing_paths[@]} items" \
            --width=500
        
        if zenity --question --title="Resume Transfer" \
                --text="Do you want to skip missing items and continue?"; then
            # Filter out missing paths
            local valid_paths=()
            while IFS= read -r path; do
                if [ -e "$path" ]; then
                    valid_paths+=("$path")
                fi
            done < "$marker_file"
            
            # Update marker file with valid paths
            printf "%s\n" "${valid_paths[@]}" > "$marker_file"
            return 0
        else
            return 1
        fi
    fi
    return 0
}

# Function to calculate existing destination size
get_existing_size() {
    local dest="$1"
    local marker_file="$2"
    local total_existing=0
    
    while IFS= read -r item; do
        dest_item="$dest/$(basename "$item")"
        if [ -e "$dest_item" ]; then
            if [ -d "$dest_item" ]; then
                size=$(du -sb "$dest_item" 2>/dev/null | cut -f1)
            else
                size=$(stat -c %s "$dest_item" 2>/dev/null)
            fi
            [[ $size =~ ^[0-9]+$ ]] && total_existing=$((total_existing + size))
        fi
    done < "$marker_file"
    
    echo $total_existing
}

# Function to transfer files and folders
transfer_images() {
    if [[ $EUID -eq 0 ]]; then
        zenity --error --text="Please run this script as a regular user, not root."
        exit 1
    fi

    # Ask for destination folder first
    local dest_mount
    dest_mount=$(zenity --file-selection --directory --title="Select Destination Folder")

    if [ -z "$dest_mount" ]; then
        zenity --info --text="No destination folder selected. Exiting."
        exit 1
    fi

    if [ ! -w "$dest_mount" ]; then
        zenity --error --text="Error: You do not have write permissions to the selected destination folder."
        exit 1
    fi

    mkdir -p "$dest_mount"

    # Check for existing transfers and ask about resume
    local resume_option=""
    local resume_state=0
    local existing_marker=$(find "$dest_mount" -maxdepth 1 -name '.transfer_marker_*' -print -quit)
    local marker_log_file
    
    if [ -n "$existing_marker" ]; then
        zenity_response=$(zenity --question --title="Resume Transfer" \
            --text="Found an incomplete transfer in:\n$dest_mount\n\nWhat would you like to do?" \
            --ok-label="Resume Existing Transfer" \
            --cancel-label="Start New Transfer")

        case $? in
            0)  # Resume existing transfer
                if ! validate_resume_paths "$existing_marker"; then
                    zenity --info --text="Resume cancelled by user."
                    exit 0
                fi
                resume_state=1
                marker_log_file="$existing_marker"
                resume_option="--partial --inplace --size-only"
                ;;
            1)  # Start new transfer
                rm -f "$existing_marker"
                ;;
            *)  # Run new transfer alongside
                ;;
        esac
    fi

    # Ask about resume capability for new transfers
    if [ $resume_state -eq 0 ]; then
        if zenity --question --title="Resume Option" \
                --text="Enable resume support for this transfer?\n\nAllows resuming interrupted transfers but uses more disk space."; then
            resume_option="--partial --inplace --size-only"
        else
            resume_option="--whole-file --inplace --size-only"
        fi
    fi

    # Transfer type selection
    local transfer_type=$(zenity --list \
        --title="Select Transfer Type" \
        --text="Choose what you want to transfer:" \
        --column="Option" \
        "Transfer Files Only" \
        "Transfer Folders Only" \
        --width=400 --height=350)

    if [ -z "$transfer_type" ]; then
        zenity --info --text="No transfer type selected. Exiting."
        exit 1
    fi

    local temp_dir_file
    temp_dir_file=$(mktemp)
    local selected_items=()

    case "$transfer_type" in
        "Transfer Files Only")
            # Select files only
            local files
            files=$(zenity --file-selection --multiple --title="Select Files to Transfer" \
                    --width=800 --height=600 2>/dev/null || echo "")

            if [ -n "$files" ]; then
                echo "$files" | tr '|' '\n' >> "$temp_dir_file"
            fi
            ;;
        "Transfer Folders Only")
            # Select folders only
            local directories
            directories=$(zenity --file-selection --directory --multiple \
                    --title="Select Folders to Transfer" --width=800 --height=600 2>/dev/null || echo "")

            if [ -n "$directories" ]; then
                echo "$directories" | tr '|' '\n' >> "$temp_dir_file"
            fi
            ;;
    esac

    if [ ! -s "$temp_dir_file" ]; then
        rm -f "$temp_dir_file"
        zenity --info --text="No items selected. Exiting."
        exit 1
    fi

    # Create unique marker for this transfer
    if [ $resume_state -eq 0 ]; then
        marker_log_file="${dest_mount}/.transfer_marker_$(date +%s)"
        cp "$temp_dir_file" "$marker_log_file"
    else
        cp "$marker_log_file" "$temp_dir_file"
    fi

    selected_items=$(cat "$temp_dir_file")
    rm -f "$temp_dir_file"

    # Get common parent for progress display
    local common_parent=$(find_common_parent $selected_items)
    [ -z "$common_parent" ] && common_parent="Various Locations"

    local progress_file
    progress_file=$(mktemp)
    start_time=$(date +%s)

    # Calculate total size more accurately
    total_size=0
    total_files=0
    while IFS= read -r item; do
        if [ -d "$item" ]; then
            # Use rsync dry run to get accurate directory transfer size
            size=$(rsync -a --dry-run --stats "$item" "$dest_mount/" 2>/dev/null | grep "Total transferred file size:" | awk '{print $5}' | tr -d ',')
            [[ -z "$size" ]] && size=$(du -sb "$item" 2>/dev/null | cut -f1)
            total_files=$((total_files + 1))
        else
            size=$(stat -c %s "$item" 2>/dev/null)
            total_files=$((total_files + 1))
        fi

        if [[ $size =~ ^[0-9]+$ ]]; then
            total_size=$((total_size + size))
        else
            zenity --error --text="Error: Unable to determine size of $item"
            exit 1
        fi
    done < "$marker_log_file"

    if [ $total_size -eq 0 ]; then
        zenity --error --text="Total size of selected items is zero or cannot be determined."
        exit 1
    fi

    total_size_human=$(format_size "$total_size")
    echo "Total size to transfer: $total_size"
    echo "Total size to transfer: $total_size_human"

    # Disk space check with 20% buffer
    dest_space_available=$(df -B1 --output=avail "$dest_mount" | tail -1)
    buffer=$((total_size / 5))  # 20% buffer
    required_space=$((total_size + buffer))

    if [ $required_space -gt $dest_space_available ]; then
        dest_space_available_human=$(format_size "$dest_space_available")
        required_space_human=$(format_size "$required_space")
        zenity --error --title="Insufficient Disk Space" \
            --text="Destination does not have enough free space.\n\nRequired: $required_space_human (including 20% buffer)\nAvailable: $dest_space_available_human\n\nTransfer cannot proceed."
        exit 1
    fi

    # Create progress pipe for Zenity
    local progress_pipe=$(mktemp -u)
    mkfifo "$progress_pipe"

    # Start Zenity progress dialog
    zenity --progress \
        --title="File Transfer" \
        --text="Preparing to transfer $total_files items ($total_size_human) from:\n$common_parent" \
        --percentage=0 \
        --auto-close \
        --width=600 \
        < "$progress_pipe" &
    zenity_pid=$!

    # Open progress pipe for writing
    exec 3>"$progress_pipe"

    transferred_bytes=0
    cancel_transfer=0
    file_count=0

    # For resume: calculate existing transferred size
    if [ $resume_state -eq 1 ]; then
        transferred_bytes=$(get_existing_size "$dest_mount" "$marker_log_file")
    fi

    # Trap SIGPIPE to handle dialog close
    trap 'cancel_transfer=1' SIGPIPE

    # Function to write to progress pipe with error handling
    write_progress() {
        if [ $cancel_transfer -eq 0 ]; then
            echo "$1" >&3 2>/dev/null || cancel_transfer=1
        fi
    }

    # Function to write progress message
    write_progress_msg() {
        if [ $cancel_transfer -eq 0 ]; then
            echo "# $1" >&3 2>/dev/null || cancel_transfer=1
        fi
    }

    # Function to write progress percentage
    write_progress_percent() {
        if [ $cancel_transfer -eq 0 ]; then
            echo "$1" >&3 2>/dev/null || cancel_transfer=1
        fi
    }

    error_file=$(mktemp)

    # Transfer each item
    while IFS= read -r item; do
        # Skip items that don't exist
        if [ ! -e "$item" ]; then
            continue
        fi

        item_name=$(basename "$item")
        file_count=$((file_count + 1))
        write_progress_msg "Transferring ($file_count/$total_files): $item_name"
        write_progress_percent "$((transferred_bytes * 100 / total_size))"

        # Calculate size of current item more accurately
        if [ -d "$item" ]; then
            # For directories, get the exact size that will be transferred
            item_size=$(rsync -a --dry-run --stats "$item" "$dest_mount/" 2>/dev/null | grep "Total transferred file size:" | awk '{print $5}' | tr -d ',')
            [[ -z "$item_size" ]] && item_size=$(du -sb "$item" 2>/dev/null | cut -f1)
        else
            item_size=$(stat -c %s "$item" 2>/dev/null)
        fi

        # Ensure item_size is numeric
        if ! [[ $item_size =~ ^[0-9]+$ ]]; then
            item_size=0
        fi

        # Start rsync with progress indication
        rsync -rt --no-owner --no-group --size-only $resume_option --info=progress2 "$item" "$dest_mount/" 2>"$error_file" | \
        stdbuf -oL tr '\r' '\n' | \
        while read -r line; do
            if [[ "$line" =~ ([0-9,]+)\ +([0-9]+)% ]]; then
                current_bytes=$(echo "${BASH_REMATCH[1]}" | tr -d ',')
                
                # Calculate the actual transferred bytes based on the item's starting point
                actual_transferred=$((transferred_bytes + current_bytes))
                overall_percent=$((actual_transferred * 100 / total_size))
                (( overall_percent > 100 )) && overall_percent=100
                
                # Calculate progress information
                elapsed=$(( $(date +%s) - start_time ))
                speed=$(( actual_transferred / (elapsed > 0 ? elapsed : 1) ))
                remaining_bytes=$(( total_size - actual_transferred ))
                remaining_sec=$(( remaining_bytes / (speed > 0 ? speed : 1) ))
                
                elapsed_formatted=$(printf "%02d:%02d:%02d" $((elapsed/3600)) $((elapsed%3600/60)) $((elapsed%60)))
                remaining_formatted=$(printf "%02d:%02d:%02d" $((remaining_sec/3600)) $((remaining_sec%3600/60)) $((remaining_sec%60)))
                overall_human=$(format_size "$actual_transferred")
                speed_human=$(format_size $speed)
                
                progress_msg="File $file_count of $total_files: $item_name\nTransferred: $overall_human of $total_size_human ($overall_percent%)\nElapsed: $elapsed_formatted | Remaining: $remaining_formatted\nSpeed: $speed_human/s"
                
                write_progress_msg "$progress_msg"
                write_progress_percent "$overall_percent"
            fi
        done
        
        # Get rsync exit status
        rsync_exit=${PIPESTATUS[0]}
        
        # Check for rsync errors
        if [ $rsync_exit -ne 0 ]; then
            error_msg=$(tr -d '\0' < "$error_file")
            write_progress_msg "Error transferring $item_name: rsync exit code $rsync_exit. Error: $error_msg"
        fi

        # Update transferred bytes after rsync completes
        transferred_bytes=$((transferred_bytes + item_size))

        # Check for cancellation
        if [ $cancel_transfer -eq 1 ]; then
            break
        fi

    done < "$marker_log_file"

    ## Clean up
    exec 3>&-
    rm -f "$progress_pipe" "$error_file"
    wait $zenity_pid 2>/dev/null

    if [ $cancel_transfer -eq 1 ]; then
        zenity --warning --title="Transfer Interrupted" \
            --text="The transfer was interrupted or canceled.\n\nYou can resume it next time." \
            --width=400
        exit 1
    fi

    # Success path
    if [ -f "$marker_log_file" ]; then
        rm -f "$marker_log_file"
    fi

    end_time=$(date +%s)
    total_elapsed=$((end_time - start_time))
    elapsed_formatted=$(printf "%02d:%02d:%02d" $((total_elapsed/3600)) $((total_elapsed%3600/60)) $((total_elapsed%60)))
    avg_speed=$((total_size / (total_elapsed > 0 ? total_elapsed : 1)))
    avg_speed_human=$(format_size $avg_speed)

    zenity --info \
        --title="Transfer Complete" \
        --text="Transfer completed successfully to:\n$dest_mount\n\nTotal size: $total_size_human\nTotal items: $total_files\nTime taken: $elapsed_formatted\nAverage speed: $avg_speed_human/s" \
        --width=400 --height=300
    
    # Remove progress file
    rm -f "$progress_file"
}

# Main program
check_dependencies
selected_device=$(check_usb_port)
status=$?

if [[ $status -ne 0 ]]; then
    echo "No USB selected or an error occurred."
    exit 1
fi

user_choice=$(
    # Start zenity in background
    zenity --list --title="USB Utility" --width=400 --height=250 \
        --column="Option" --text="Choose an operation:" \
        "Transfer Files" "USB Port Check" &
    
    # Get the zenity process ID
    zenity_pid=$!
    
    # Wait for 0.3 seconds
    sleep 0.3
    
    # Check if zenity is still running
    if kill -0 $zenity_pid 2>/dev/null; then
        # Zenity still open - user hasn't selected, so kill it
        kill $zenity_pid
        echo "Transfer Files"  # Default selection
    else
        # User made a selection - wait to get the output
        wait $zenity_pid
    fi
)

case "$user_choice" in
    "Transfer Files") 
        transfer_images ;;
    *) 
        zenity --info --text="Using default selection." ;;
esac