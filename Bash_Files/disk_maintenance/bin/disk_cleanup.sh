#!/bin/bash

DEBUG_SCRIPT=false
if [ "$DEBUG_SCRIPT" == "true" ]
then 
    set -x
fi 

function usage() {

    echo -e "Disk Cleanup Script"
    echo -e "This script is used to clean up disk space by removing old files and directories."
    echo -e ""
    echo -e "Usage: `basename $0` [OPTIONS]"
    echo -e "\t-h,      --help              \tDisplays this help message"
    echo -e "\t-c,      --check             \tChecks for storage usage"
    echo -e "\t-s,      --ssd               \tSSD only disk cleanup"
    echo -e ""
    echo -e "Example: "
    echo -e "`basename $0` "
}    

if [[ "$1" == "-h" || "$1" == "--help" ]]
then 
    usage
    exit 1
fi 

while [[ $# -gt 0 ]]; do
    key="$1"
    case "$key" in
        -c|--check)
        DISK_CHECK=true
        ;;
        -s|--ssd)
        SSD_ONLY=true
        ;;
        *)
        echo "`basename $0`: Unknown option '$key'"
        echo "" 
        usage
        exit 1
        ;;
    esac
    shift
done

DRY_RUN=false
RUN_JIDOKA_DISK_CLEANUP=false

# Script is located in ${DEPLOY_DIR}/bin
SCRIPT_DIR=`dirname "$0"`
cd $SCRIPT_DIR
cd ..
DEPLOY_DIR=`pwd`

if [ "$DISK_CHECK" == "true" ]
then
    THRESHOLD=50

    FULL=$(df -h --output=pcent,target | tail -n +2 | while read percent mount; do 
        usage=${percent%\%}
        if [ $mount == "/home" ]
        then
            echo "SSD is $percent percent full"
        elif [ $mount == "/mnt/hdd" ]
        then
            echo "HDD is $percent percent full"
        fi
    done)

    if [ -n "$FULL" ]; then
        zenity --question \
            --title="Disk Usage Warning" \
            --text="$FULL\n\nPlease run HDD disk cleanup." \
            --ok-label="OK" \
            --cancel-label="Cancel" \
            --width 250 \
            --height 100
    fi

else
    mkdir -p $DEPLOY_DIR/logs
    LOG_FILE=$DEPLOY_DIR/logs/disk_cleanup.log
    CONFIG_FILE=$DEPLOY_DIR/config/disk_cleanup_config.json

    echo "# =============================================================" | tee -a $LOG_FILE
    echo "# Disk Cleanup Starting" | tee -a $LOG_FILE
    echo "# =============================================================" | tee -a $LOG_FILE

    # Get minimum free space from config file
    MIN_FREE_SPACE=$(jq -r '.min_disk_free_space' $CONFIG_FILE)
    if [ "$MIN_FREE_SPACE" == "null" ]
    then
        echo "Error: min_disk_free_space not found in config file" | ts | tee -a $LOG_FILE
        exit 1
    else 
        echo "Minimum free space is set to $MIN_FREE_SPACE GB" | ts | tee -a $LOG_FILE
    fi

    # Create a list of disk partitions starting with /dev/sd
    if [ "$SSD_ONLY" == "true" ]
    then
        DISK_PARTITIONS=$(df -h --output=source | grep "/dev/nvme")
        HOME_DISK_PARITION=$(df -h --output=source /home | grep "/dev/nvme")
        JIDOKA_DISK_PARTITION=$(df -h --output=source /jidoka | grep "/dev/nvme")
        OTHER_DISK_PARTITION=$(df -h --output=source | grep "/dev/nvme" | grep -v "$HOME_DISK_PARITION" | grep -v "$JIDOKA_DISK_PARTITION")
        THROTTLE_FOLDER_DELETE=$(jq -r '.throttle_folder_delete' $CONFIG_FILE)
    else
        DISK_PARTITIONS=$(df -h --output=source | grep "/dev/sd")
        HOME_DISK_PARITION=$(df -h --output=source /home | grep "/dev/sd")
        JIDOKA_DISK_PARTITION=$(df -h --output=source /jidoka | grep "/dev/sd")
        OTHER_DISK_PARTITION=$(df -h --output=source | grep "/dev/sd" | grep -v "$HOME_DISK_PARITION" | grep -v "$JIDOKA_DISK_PARTITION")
        THROTTLE_FOLDER_DELETE="false"
    fi

    # Check space used on each partition and give warning if greater than 90%
    for PARTITION in $DISK_PARTITIONS; do
        USED_SPACE=$(df -h --output=pcent $PARTITION | tail -n 1 | tr -d '%')
        FREE_SPACE_GB=$(df --output=avail $PARTITION | tail -n 1 | awk '{print $1/1024/1024}')
        if [[ "$PARTITION" == "$HOME_DISK_PARITION" && "$USED_SPACE" -gt 70 ]]
        then
            echo "WARN: More than 70% used on $PARTITION. Please clean up your home directory. " | ts | tee -a $LOG_FILE
        elif [[ "$PARTITION" == "$OTHER_DISK_PARTITION" && "$USED_SPACE" -gt 80 ]]
        then
            MOUNT_POINT=$(df -h --output=target $PARTITION | tail -n 1)
            echo "WARN: More than 90% used on $PARTITION at mountpoint $MOUNT_POINT" | ts | tee -a $LOG_FILE
        elif [[ "$PARTITION" == "$JIDOKA_DISK_PARTITION" && $(echo "$FREE_SPACE_GB < $MIN_FREE_SPACE" | bc -l) -eq 1 ]]
        then
            RUN_JIDOKA_DISK_CLEANUP=true
            echo "WARN: Free space of $FREE_SPACE_GB GB less than min $MIN_FREE_SPACE GB at /jidoka parition. Running disk cleanup" | ts | tee -a $LOG_FILE
        fi
    done

    if [ "$RUN_JIDOKA_DISK_CLEANUP" == "true" ]
    then

        # Start monitoring disk utilization
        iostat -dxsh ${JIDOKA_DISK_PARTITION} 1 | head -n 4 | tail -n 2 | ts | tee -a ./logs/disk_cleanup.log & 

        echo "# =============================================================" | tee -a $LOG_FILE
        echo "# Folder Cleanup" | tee -a $LOG_FILE
        echo "# =============================================================" | tee -a $LOG_FILE

        jq -c '.folder_delete_list[]' "$CONFIG_FILE" | while read -r obj
        do
            FOLDER_PATH=$(echo "$obj" | jq -r '.path' )
            DELETE_OLDER_THAN_DAYS=$(echo "$obj" | jq -r '.delete_older_than_days' )
            if [ "$DELETE_OLDER_THAN_DAYS" -gt 0 ]
            then
                DELETE_OLDER_THAN_DAYS=+${DELETE_OLDER_THAN_DAYS}
            else
                DELETE_OLDER_THAN_DAYS=0
            fi
            RETAIN_FOLDER_LIST=$(echo "$obj" | jq -r '.retain_folder_list' )
            FOLDER_DELETE_AT_DEPTH=$(echo "$obj" | jq -r '.folder_delete_at_depth' )

            echo "Deleting folders older than $DELETE_OLDER_THAN_DAYS days in $FOLDER_PATH at depth $FOLDER_DELETE_AT_DEPTH" | ts | tee -a $LOG_FILE

            # If there is a * in the folder path,
            for FOLDER in $FOLDER_PATH
            do
                
                if [ ! -d "$FOLDER" ]
                then
                    echo "Folder $FOLDER does not exist. Skipping." | ts | tee -a $LOG_FILE
                    continue
                fi
                cd $FOLDER
                echo "Deleting folders in folder $FOLDER" | ts | tee -a $LOG_FILE

                # Find folders with depth FOLDER_DELETE_AT_DEPTH
                # FOLDER_DELETE_AT_DEPTH=3 is for images that are stored in <line_id>/<batch_id>/* format
                # This will prevent /jidoka/<ver>/images/<line_id>/<component_id> from being deleted causing more than required deletion
                find . -mindepth ${FOLDER_DELETE_AT_DEPTH} -maxdepth ${FOLDER_DELETE_AT_DEPTH} -type d -mtime ${DELETE_OLDER_THAN_DAYS} -print0 | while IFS= read -r -d '' FOLDER_TO_DELETE
                do
                    # Loop through RETAIN_FOLDER_LIST and check if the FOLDER_TO_DELETE is present. Set bool SKIP_DELETE to true if present
                    SKIP_DELETE=false
                    while read -r RETAIN_FOLDER
                    do
                        CLEAN_PATH=${FOLDER_TO_DELETE#./}
                        if [[ "$CLEAN_PATH" == *"$RETAIN_FOLDER"* ]]
                        then
                            echo "Folder $FOLDER_TO_DELETE is present in retain_folder_list as $RETAIN_FOLDER. Skipping deletion." | ts | tee -a $LOG_FILE
                            SKIP_DELETE=true
                            break
                        fi
                    done < <(echo "$RETAIN_FOLDER_LIST" | jq -c '.[]' | tr -d '"')

                    # If the folder is not present in retain_folder_list, delete it
                    if [ "$SKIP_DELETE" == "false" ]
                    then
                        FREE_SPACE_GB=$(df --output=avail $JIDOKA_DISK_PARTITION | tail -n 1 | awk '{print $1/1024/1024}')
                        START_TIME=$(date +%s)
                        echo "Deleting folder $FOLDER_TO_DELETE when free space is $FREE_SPACE_GB" | ts | tee -a $LOG_FILE
                        
                        if [ "$DRY_RUN" == "true" ]
                        then
                            rsync -a -n --delete /tmp/emptydir/ "${FOLDER_TO_DELETE}"
                        else
                            if [ "$THROTTLE_FOLDER_DELETE" == "true" ]
                            then
                                while find "${FOLDER_TO_DELETE}" -type f -print0 | grep -qz .; do
                                    find "${FOLDER_TO_DELETE}" -type f -print0 | head -z -n 100 | xargs -0 rm
                                done
                                rm -r "${FOLDER_TO_DELETE}"
                            else
                                mkdir -p /tmp/emptydir
                                rsync -a --delete /tmp/emptydir/ "${FOLDER_TO_DELETE}"
                                rm -r "${FOLDER_TO_DELETE}"
                                rmdir /tmp/emptydir
                            fi
                        fi
                        
                        FREE_SPACE_GB=$(df --output=avail $JIDOKA_DISK_PARTITION | tail -n 1 | awk '{print $1/1024/1024}')
                        END_TIME=$(date +%s)
                        ELAPSED_TIME=$((END_TIME - START_TIME))
                        echo "Finished deleting folder $FOLDER_TO_DELETE, time taken is $ELAPSED_TIME seconds, free space is $FREE_SPACE_GB" | ts | tee -a $LOG_FILE

                    fi
                done
            done
        done

        echo "# =============================================================" | tee -a $LOG_FILE
        echo "# File Cleanup" | tee -a $LOG_FILE
        echo "# =============================================================" | tee -a $LOG_FILE

        jq -c '.file_delete_list[]' "$CONFIG_FILE" | while read -r obj
        do
            FOLDER_PATH=$(echo "$obj" | jq -r '.path' )
            DELETE_OLDER_THAN_DAYS=$(echo "$obj" | jq -r '.delete_older_than_days' )

            echo "Deleting files in folder older than $DELETE_OLDER_THAN_DAYS days in $FOLDER_PATH" | ts | tee -a $LOG_FILE

            # If there is a * in the folder path,
            for FOLDER in $FOLDER_PATH
            do
                
                if [ ! -d "$FOLDER" ]
                then
                    echo "Folder $FOLDER does not exist. Skipping." | ts | tee -a $LOG_FILE
                    continue
                fi
                echo "Deleting files in folder $FOLDER" | ts | tee -a $LOG_FILE
                cd $FOLDER
                
                if [ "$DRY_RUN" == "true" ]
                then
                    # find "$FOLDER" -type f -mtime +${DELETE_OLDER_THAN_DAYS} ! -name *settings.dat -exec echo {} \; 
                    find "$FOLDER" -type f -mtime +${DELETE_OLDER_THAN_DAYS} -exec echo {} \; 
                else
                    find "$FOLDER" -type f -mtime +${DELETE_OLDER_THAN_DAYS} -delete
                fi 
            done
        done

        # stop monitoring disk utilization
        pkill iostat

    fi 

    echo "# =============================================================" | tee -a $LOG_FILE
    echo "# Disk Cleanup Finished" | tee -a $LOG_FILE
    echo "# =============================================================" | tee -a $LOG_FILE
fi