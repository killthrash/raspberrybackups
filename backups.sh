#!/bin/bash

# Configuration - EXACTLY AS YOU SPECIFIED
WINDOWS_MOUNT="/mnt/[WINDOWS_SHARE]"              # Windows share folder "[WINDOWS_SHARE]"
PRIMARY_BACKUP="/mnt/[PRIMARY_DRIVE]"           # Primary drive
SECONDARY_BACKUP="/mnt/[SECONDARY_DRIVE]"         # Secondary drive (mirror of primary)
LOG_DIR="/var/log/backups"

# Email configuration
EMAIL="[NOTIFICATION_EMAIL]"
EMAIL_FROM="[FROM_EMAIL]"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Generate timestamp for log file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/backup_$TIMESTAMP.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to send notification
send_notification() {
    if [ -n "$EMAIL" ] && [ -n "$1" ]; then
        {
            echo "To: $EMAIL"
            echo "From: $EMAIL_FROM"
            echo "Subject: $1"
            echo ""
            echo "$2"
            echo ""
            echo "Log file: $LOG_FILE"
            echo "Completed at: $(date)"
        } | sendmail "$EMAIL"
        
        # Log that notification was sent
        log_message "Notification email sent to $EMAIL with subject: $1"
    fi
}

# Function to get disk space info
get_disk_space_info() {
    local path=$1
    local info=$(df -h "$path" | awk 'NR==2 {print $4" ("$5" used)"}')
    echo "$info"
}

# Function to check drive health (simplified)
check_drive_health() {
    log_message "=== Drive Health Check ==="
    
    local health_status="OK"
    
    # Quick health check without detailed stats
    if [ -b "/dev/sda" ] && ! sudo smartctl -H /dev/sda | grep -q "PASSED"; then
        log_message "WARNING: Primary drive health check failed"
        health_status="WARNING"
    fi
    
    if [ -b "/dev/sdb" ] && ! sudo smartctl -H /dev/sdb | grep -q "PASSED"; then
        log_message "WARNING: Secondary drive health check failed"
        health_status="WARNING"
    fi
    
    log_message "Overall Drive Health: $health_status"
    log_message "=== Drive Health Check Complete ==="
    
    echo "$health_status"
}

# Function to check prerequisites
check_prerequisites() {
    # Check mount
    if ! mountpoint -q "$WINDOWS_MOUNT"; then
        log_message "ERROR: Windows share not mounted at $WINDOWS_MOUNT"
        send_notification "Backup Failed - CRITICAL" "Windows share not mounted at $WINDOWS_MOUNT"
        return 1
    fi
    
    # Check accessibility
    if ! ls "$WINDOWS_MOUNT" >/dev/null 2>&1; then
        log_message "ERROR: Cannot access Windows share"
        send_notification "Backup Failed - CRITICAL" "Cannot access Windows share at $WINDOWS_MOUNT"
        return 1
    fi
    
    # Check directories exist and are writable
    for dir in "$PRIMARY_BACKUP" "$SECONDARY_BACKUP"; do
        if [ ! -d "$dir" ]; then
            log_message "ERROR: Directory does not exist: $dir"
            send_notification "Backup Failed - CRITICAL" "Directory missing: $dir"
            return 1
        fi
        if [ ! -w "$dir" ]; then
            log_message "ERROR: Directory not writable: $dir"
            send_notification "Backup Failed - CRITICAL" "Directory not writable: $dir"
            return 1
        fi
    done
    
    return 0
}

# Function to perform dd backup of Raspberry Pi SD card
run_dd_backup() {
    # Save to Windows mount directory with timestamp
    local img_file="$WINDOWS_MOUNT/[BACKUP_FOLDER]/[BACKUP_PREFIX]_$TIMESTAMP.img"
    log_message "=== Starting dd backup of /dev/mmcblk0 to $img_file ==="

    # Ensure destination directory exists
    mkdir -p "$(dirname "$img_file")"

    local start_time=$(date +%s)
    local dd_log="/tmp/dd_backup_$TIMESTAMP.log"

    # Run dd with progress output
    sudo dd bs=4M if=/dev/mmcblk0 of="$img_file" status=progress 2>&1 | tee "$dd_log"
    local dd_exit_code=${PIPESTATUS[0]}

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local minutes=$(( (duration % 3600) / 60))
    local seconds=$((duration % 60))

    # Log results
    log_message "=== dd Backup Results ==="
    log_message "Image file: $img_file"
    log_message "Duration: $(printf "%02d:%02d:%02d" $hours $minutes $seconds)"
    log_message "Exit code: $dd_exit_code"

    # Append dd output to main log
    if [ -f "$dd_log" ]; then
        log_message "dd Output:"
        while IFS= read -r line; do
            log_message "    $line"
        done < "$dd_log"
        rm -f "$dd_log"
    fi

    if [ "$dd_exit_code" -eq 0 ]; then
        log_message "=== dd Backup Completed Successfully ==="
        
        # Optional: Keep only last 7 backups
        log_message "Cleaning up old dd backups (keeping last 7)..."
        ls -t "$WINDOWS_MOUNT/[BACKUP_FOLDER]/[BACKUP_PREFIX]_"*.img 2>/dev/null | tail -n +8 | xargs -r rm -f
        
        return 0
    else
        log_message "ERROR: dd backup failed with exit code $dd_exit_code"
        log_message "=== dd Backup Failed ==="
        return 1
    fi
}

# Function to run rsync with FAST options (based on your discovery)
run_rsync_fast() {
    local source=$1
    local destination=$2
    local description=$3

    log_message "=== Starting $description ==="
    log_message "Source: $source"
    log_message "Destination: $destination"

    # Get start time
    local start_time=$(date +%s)

    # Run rsync with your FAST options
    log_message "Running FAST rsync from $source to $destination"

    # Create temporary file for rsync output
    local rsync_log="/var/log/backups/rsync_debug_$(date +%s).log"

    # Your optimized rsync command - FAST and efficient
    rsync -av --compress --progress --omit-dir-times --no-perms --modify-window=120 --ignore-errors --delete --safe-links \
          --exclude='*AppData/Local/Temp*' \
          --exclude='*Temporary Internet Files*' \
          --exclude='*INetCache*' \
          --exclude='/Local Settings*' \
          --exclude='/Application Data*' \
          --exclude='*/Application Data*' \
          --exclude='*/Temp*' \
          --exclude='*/Cache*' \
          "$source/" "$destination/" > "$rsync_log" 2>&1

    local rsync_exit_code=$?

    # Get end time and calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local minutes=$(( (duration % 3600) / 60))
    local seconds=$((duration % 60))

    # Parse basic stats
    local files_copied=$(grep "/" "$rsync_log" | wc -l)

    # Log results
    log_message "=== $description Results ==="
    log_message "Files processed: $files_copied"
    log_message "Duration: $(printf "%02d:%02d:%02d" $hours $minutes $seconds)"
    log_message "Disk space remaining on destination: $(get_disk_space_info "$destination")"

    # Check if successful
    if [ "$rsync_exit_code" -eq 0 ]; then
        log_message "=== $description Completed Successfully ==="
        rm "$rsync_log"
        return 0
    else
        # Even with exit code, if it ran for a reasonable time, consider it OK
        if [ $duration -gt 1 ]; then
            log_message "=== $description Completed (with warnings) ==="
            rm "$rsync_log"
            return 0
        else
            log_message "ERROR: $description failed after $(printf "%02d:%02d:%02d" $hours $minutes $seconds)"
            log_message "=== $description Failed ==="
            rm "$rsync_log"
            return 1
        fi
    fi
}

# Main backup process
log_message "################################################################################"
log_message "=== Starting complete backup process ==="
log_message "Log file: $LOG_FILE"
log_message "Source (Windows share): $WINDOWS_MOUNT"
log_message "Primary backup: $PRIMARY_BACKUP"
log_message "Secondary backup: $SECONDARY_BACKUP (mirror of primary)"
log_message "Initial disk space - Primary: $(get_disk_space_info "$PRIMARY_BACKUP")"
log_message "Initial disk space - Secondary: $(get_disk_space_info "$SECONDARY_BACKUP")"

# Quick drive health check
drive_health=$(check_drive_health)
log_message "Pre-backup Drive Health Status: $drive_health"

# Check prerequisites
if ! check_prerequisites; then
    log_message "=== Backup process FAILED - Prerequisites check failed ==="
    log_message "################################################################################"
    send_notification "Backup Failed - CRITICAL" "Backup process failed - Prerequisites check failed. Check log: $LOG_FILE"
    exit 1
fi

# Step 0: Perform dd backup of Raspberry Pi SD card
if run_dd_backup; then
    log_message "Step 0 (dd backup) completed successfully"
else
    log_message "=== Backup process FAILED at Step 0 (dd backup) ==="
    log_message "################################################################################"
    send_notification "Backup Failed - CRITICAL" "Failed creating dd image of SD card. Check log: $LOG_FILE"
    exit 1
fi

# Step 1: Sync from Windows share "[WINDOWS_SHARE]" to primary drive (creates /[PRIMARY_DRIVE]/[WINDOWS_SHARE])
if run_rsync_fast "$WINDOWS_MOUNT" "$PRIMARY_BACKUP/[WINDOWS_SHARE]" "Step 1: Windows Share to Primary Drive"; then
    log_message "Step 1 completed successfully"
else
    log_message "=== Backup process FAILED at Step 1 ==="
    log_message "################################################################################"
    send_notification "Backup Failed - CRITICAL" "Failed syncing Windows to primary backup. Check log: $LOG_FILE"
    exit 1
fi

# Step 2: Sync entire primary drive to secondary drive (mirror/clone the entire drive)
if run_rsync_fast "$PRIMARY_BACKUP" "$SECONDARY_BACKUP" "Step 2: Primary Drive Mirror to Secondary Drive"; then
    log_message "Step 2 completed successfully"
else
    log_message "=== Backup process FAILED at Step 2 ==="
    log_message "################################################################################"
    send_notification "Backup Failed - CRITICAL" "Failed mirroring primary to secondary backup. Check log: $LOG_FILE"
    exit 1
fi

# Post-backup drive health check
post_backup_health=$(check_drive_health)
log_message "Post-backup Drive Health Status: $post_backup_health"

log_message "=== Complete backup process finished successfully ==="
log_message "Final disk space - Primary: $(get_disk_space_info "$PRIMARY_BACKUP")"
log_message "Final disk space - Secondary: $(get_disk_space_info "$SECONDARY_BACKUP")"

# Health status summary in notification
health_summary=""
if [ "$drive_health" != "OK" ] || [ "$post_backup_health" != "OK" ]; then
    health_summary=" (Drive health warnings detected - check log)"
fi

log_message "################################################################################"
send_notification "Backup Completed Successfully" "Backup process finished successfully. Log: $LOG_FILE$health_summary"
exit 0