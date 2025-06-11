#!/bin/sh

# PlayIntegrityFix Cron Management Script
# This script manages the cron job for automatic pif.json updates
# Optimized based on crond_start_jobs implementation

MODPATH="${0%/*}"
MODDIR="/data/adb/modules/playintegrityfix"
ACTION_SCRIPT="$MODDIR/action.sh"
CRON_MARKER="# PlayIntegrityFix Auto Update"
BACKUP_DIR="$MODDIR/backup"
LOG_FILE="$MODDIR/cron.log"

# Ensure PATH includes common binary locations
if ! command -v busybox >/dev/null 2>&1; then
    export PATH="/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH:/system/bin:/system/xbin"
fi

# Create necessary directories
mkdir -p "$BACKUP_DIR"

# Logging function
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Function to check if busybox cron is available
check_busybox_cron() {
    if command -v busybox >/dev/null 2>&1 && busybox crond --help >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to check if system cron daemon is available
check_system_cron() {
    if command -v crond >/dev/null 2>&1; then
        return 0
    elif [ -x /system/bin/crond ] || [ -x /system/xbin/crond ]; then
        return 0
    else
        return 1
    fi
}

# Function to check if any cron daemon is available
check_cron_daemon() {
    check_busybox_cron || check_system_cron
}

# Function to start busybox cron daemon
start_busybox_cron() {
    local cron_pid
    
    # Check if busybox crond is already running
    cron_pid=$(pgrep -f "busybox crond" | head -n1)
    if [ -n "$cron_pid" ]; then
        log_info "Busybox cron daemon already running (PID: $cron_pid)"
        echo "$cron_pid" > "$BACKUP_DIR/cron_pid"
        return 0
    fi
    
    # Try to start with nice priority if available
    if command -v nice >/dev/null 2>&1; then
        nice -n -10 busybox crond -c "$BACKUP_DIR" >/dev/null 2>&1
    else
        busybox crond -c "$BACKUP_DIR" >/dev/null 2>&1
    fi
    
    sleep 2
    
    # Check if daemon started successfully
    cron_pid=$(pgrep -f "crond -c ${BACKUP_DIR}" | head -n1)
    if [ -n "$cron_pid" ]; then
        echo "$cron_pid" > "$BACKUP_DIR/cron_pid"
        log_info "Busybox cron daemon started successfully (PID: $cron_pid)"
        return 0
    else
        log_info "Failed to start busybox cron daemon"
        return 1
    fi
}

# Function to start system cron daemon
start_system_cron() {
    if ! pgrep crond >/dev/null 2>&1; then
        if command -v crond >/dev/null 2>&1; then
            crond >/dev/null 2>&1
        elif [ -x /system/bin/crond ]; then
            /system/bin/crond >/dev/null 2>&1
        elif [ -x /system/xbin/crond ]; then
            /system/xbin/crond >/dev/null 2>&1
        fi
        
        sleep 2
        
        if pgrep crond >/dev/null 2>&1; then
            log_info "System cron daemon started successfully"
            return 0
        else
            log_info "Failed to start system cron daemon"
            return 1
        fi
    else
        log_info "System cron daemon already running"
        return 0
    fi
}

# Function to start cron daemon (prefer busybox)
start_cron_daemon() {
    if check_busybox_cron; then
        start_busybox_cron
    elif check_system_cron; then
        start_system_cron
    else
        log_info "No cron daemon available on this system"
        return 1
    fi
}

# Function to stop cron daemon
stop_cron_daemon() {
    local cron_pid
    
    # Read saved PID first
    if [ -f "$BACKUP_DIR/cron_pid" ]; then
        cron_pid=$(cat "$BACKUP_DIR/cron_pid")
        if [ -n "$cron_pid" ] && kill -0 "$cron_pid" 2>/dev/null; then
            kill -15 "$cron_pid" 2>/dev/null
            log_info "Stopped cron daemon (PID: $cron_pid)"
        fi
        rm -f "$BACKUP_DIR/cron_pid"
    fi
    
    # Also try to find and stop any running crond with our backup directory
    cron_pid=$(pgrep -f "crond -c ${BACKUP_DIR}" | head -n1)
    if [ -n "$cron_pid" ]; then
        kill -15 "$cron_pid" 2>/dev/null
        log_info "Stopped busybox cron daemon (PID: $cron_pid)"
    fi
}

# Function to create busybox cron job
create_busybox_cron_job() {
    local interval="$1"
    local cron_expression
    
    # Generate cron expression
    if [ "$interval" = "24" ]; then
        cron_expression="0 0 * * *"  # Daily at midnight
    else
        cron_expression="0 */$interval * * *"  # Every X hours
    fi
    
    # Create cron file
    echo "$cron_expression CRON_JOB=1 sh $ACTION_SCRIPT > /dev/null 2>&1" > "$BACKUP_DIR/root"
    chmod 755 "$BACKUP_DIR/root"
    
    # Save configuration
    save_cron_config "$cron_expression"
    
    log_info "Created busybox cron job: Every $interval hour(s) [$cron_expression]"
    return 0
}

# Function to create system cron job
create_system_cron_job() {
    local interval="$1"
    local cron_expression
    
    # Generate cron expression
    if [ "$interval" = "24" ]; then
        cron_expression="0 0 * * *"  # Daily at midnight
    else
        cron_expression="0 */$interval * * *"  # Every X hours
    fi
    
    # Remove existing entries and add new one
    (crontab -l 2>/dev/null | grep -v "$ACTION_SCRIPT"; echo "$cron_expression CRON_JOB=1 sh $ACTION_SCRIPT > /dev/null 2>&1 $CRON_MARKER") | crontab -
    
    # Save configuration
    save_cron_config "$cron_expression"
    
    log_info "Created system cron job: Every $interval hour(s) [$cron_expression]"
    return 0
}

# Function to restore cron job after reboot
restore_cron_job() {
    # Check if we have a saved cron config
    if [ -f "$MODDIR/cron_config" ]; then
        local cron_expression
        cron_expression=$(cat "$MODDIR/cron_config")
        if [ -n "$cron_expression" ]; then
            # Extract interval from cron expression
            local interval
            if echo "$cron_expression" | grep -q "0 0 \* \* \*"; then
                interval="24"
            else
                interval=$(echo "$cron_expression" | sed -n 's/^0 \*\/\([0-9]\+\) \* \* \*$/\1/p')
                [ -z "$interval" ] && interval="24"
            fi
            
            if check_busybox_cron; then
                create_busybox_cron_job "$interval"
            elif check_system_cron; then
                create_system_cron_job "$interval"
            fi
            
            log_info "Restored cron job: $cron_expression"
        fi
    fi
}

# Function to save cron configuration
save_cron_config() {
    if [ -n "$1" ]; then
        echo "$1" > "$MODDIR/cron_config"
    else
        rm -f "$MODDIR/cron_config"
    fi
}

# Function to add cron job
add_cron_job() {
    local interval="$1"
    if [ -z "$interval" ]; then
        interval="24"
    fi
    
    # Remove any existing cron job first
    remove_cron_job_silent
    
    # Start daemon if not running
    if ! start_cron_daemon; then
        log_info "Failed to start cron daemon"
        return 1
    fi
    
    # Create appropriate cron job
    if check_busybox_cron && [ -f "$BACKUP_DIR/cron_pid" ]; then
        create_busybox_cron_job "$interval"
    elif check_system_cron; then
        create_system_cron_job "$interval"
    else
        log_info "No suitable cron daemon available"
        return 1
    fi
    
    log_info "Auto-update enabled: Every $interval hour(s)"
    return 0
}

# Function to remove cron job (silent version)
remove_cron_job_silent() {
    # Remove busybox cron file
    rm -f "$BACKUP_DIR/root"
    
    # Remove system cron entries
    if command -v crontab >/dev/null 2>&1; then
        crontab -l 2>/dev/null | grep -v "$ACTION_SCRIPT" | crontab - 2>/dev/null
    fi
    
    save_cron_config ""
}

# Function to remove cron job
remove_cron_job() {
    remove_cron_job_silent
    log_info "Auto-update disabled"
}

# Function to check cron job status
check_cron_status() {
    local status="disabled"
    local cron_line=""
    
    # Check busybox cron first
    if [ -f "$BACKUP_DIR/root" ]; then
        cron_line=$(cat "$BACKUP_DIR/root" | grep "$ACTION_SCRIPT" | head -n1)
        if [ -n "$cron_line" ]; then
            # Extract just the cron expression part
            cron_expression=$(echo "$cron_line" | sed 's/ CRON_JOB=1.*//')
            status="enabled:$cron_expression"
        fi
    fi
    
    # Fallback to system cron
    if [ "$status" = "disabled" ] && command -v crontab >/dev/null 2>&1; then
        cron_line=$(crontab -l 2>/dev/null | grep "$ACTION_SCRIPT" | head -n1)
        if [ -n "$cron_line" ]; then
            # Extract just the cron expression part
            cron_expression=$(echo "$cron_line" | sed 's/ CRON_JOB=1.*//')
            status="enabled:$cron_expression"
        fi
    fi
    
    echo "$status"
}

# Function to get basic system information for logging
log_system_info() {
    log_info "=== PlayIntegrityFix Cron Manager ==="
    log_info "Android: $(getprop ro.build.version.release 2>/dev/null || echo 'Unknown')"
    log_info "Device: $(getprop ro.product.model 2>/dev/null || echo 'Unknown')"
    log_info "Brand: $(getprop ro.product.brand 2>/dev/null || echo 'Unknown')"
    
    if command -v busybox >/dev/null 2>&1; then
        log_info "Busybox: Available ($(busybox | head -n1 | awk '{print $2}'))"
    else
        log_info "Busybox: Not available"
    fi
    
    local cron_daemon="None"
    if check_busybox_cron; then
        cron_daemon="Busybox crond"
    elif check_system_cron; then
        cron_daemon="System crond"
    fi
    log_info "Cron daemon: $cron_daemon"
    log_info "===================================="
}

# Function to initialize wake lock (prevent system sleep during cron execution)
setup_wake_lock() {
    # Only set wake lock if file doesn't exist to disable it
    if [ ! -f "$BACKUP_DIR/nowakelock" ]; then
        echo "PlayIntegrityFix.noSuspend" >> /sys/power/wake_lock 2>/dev/null || true
        log_info "Wake lock enabled (prevents sleep during cron execution)"
        log_info "To disable: touch $BACKUP_DIR/nowakelock && reboot"
    fi
}

# Main logic
case "$1" in
    "start")
        log_system_info
        if check_cron_daemon; then
            setup_wake_lock
            if start_cron_daemon; then
                restore_cron_job
            else
                log_info "Failed to start cron daemon"
                exit 1
            fi
        else
            log_info "No cron daemon available on this system"
            exit 1
        fi
        ;;
    "add")
        if check_cron_daemon; then
            if add_cron_job "$2"; then
                setup_wake_lock
            else
                exit 1
            fi
        else
            log_info "No cron daemon available on this system"
            exit 1
        fi
        ;;
    "remove")
        remove_cron_job
        ;;
    "stop")
        stop_cron_daemon
        remove_cron_job
        ;;
    "restart")
        log_info "Restarting cron service..."
        stop_cron_daemon
        sleep 2
        if check_cron_daemon; then
            if start_cron_daemon; then
                restore_cron_job
                setup_wake_lock
            else
                log_info "Failed to restart cron daemon"
                exit 1
            fi
        else
            log_info "No cron daemon available on this system"
            exit 1
        fi
        ;;
    "status")
        check_cron_status
        ;;
    "logs")
        if [ -f "$LOG_FILE" ]; then
            cat "$LOG_FILE"
        else
            echo "No log file found"
        fi
        ;;
    *)
        echo "PlayIntegrityFix Cron Manager"
        echo "Usage: $0 {start|add [interval]|remove|stop|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  start           - Start cron daemon and restore saved job"
        echo "  add [interval]  - Add cron job with specified interval (default: 24 hours)"
        echo "  remove          - Remove cron job"
        echo "  stop            - Stop cron daemon and remove job"
        echo "  restart         - Restart cron daemon and restore job"
        echo "  status          - Check cron job status"
        echo "  logs            - Show cron manager logs"
        echo ""
        echo "Examples:"
        echo "  $0 add 12      # Update every 12 hours"
        echo "  $0 add 24      # Update daily"
        echo "  $0 status      # Check current status"
        exit 1
        ;;
esac
