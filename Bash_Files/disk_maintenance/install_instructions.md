# Installation instruction for newly formatted computer

- Step 1 Copy jt.devops/utils/disk_maintenance folder to /jidoka/disk_maintenance 
- Step 2 Update /jidoka/disk_maintenance/config/disk_cleanup_config.json with relevant details
- Step 3 Run /jidoka/disk_maintenance/bin/install.sh

# Configuration options in disk_cleanup_config.json

- daily_run_time - Setup when to trigger disk cleanup.
- min_disk_free_space - Setup to trigger when free space went below mentioned disk space.
- min_days_to_keep - Number of days to keep
- throttle_folder_delete - Setup true or false
	- When its set to true - files & folders will be deleted in controlled speed.
	- When its set to false - files & folders will be deleted in full speed.
- folder_delete_list:
	- path - "/jidoka/v*/images" this will check all the version folders in /jidoka directory (Dont change this path)
	- delete_older_than_days - Keep data for the given number of days
	- folder_delete_at_depth - Deletes folders only at the given depth
	- retain_folder_list - Ignores the given directory for deletion
- file_delete_list:
	- path - "/jidoka/v*/logs" this will check all the version folders in /jidoka directory (Dont change this path)
	- delete_older_than_days - Keep data for the given number of days


# Testing disk clean up scripts
- Step 1 - create folders with different time stamps
	- > touch -t 202303151200 [folder_name]
	- here 202303151200 is timestamp in yyyymmddhhmm format
- Step 2 - check executing a script 
	- set a crontab task immediately and check the log
	- /jidoka/disk_maintenance/logs/disk_clean_up.log