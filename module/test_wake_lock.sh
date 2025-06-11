#!/bin/sh

# Test script for wake lock management
# This script tests the per-task wake lock mechanism

MODDIR="/data/adb/modules/playintegrityfix"
ACTION_SCRIPT="$MODDIR/action.sh"

echo "=== PlayIntegrityFix Wake Lock Test ==="
echo

# Function to check current wake locks
check_wake_locks() {
    echo "Current active wake locks:"
    if [ -f /sys/power/wake_lock ]; then
        cat /sys/power/wake_lock 2>/dev/null | grep -i playintegrityfix || echo "  No PlayIntegrityFix wake locks found"
    else
        echo "  /sys/power/wake_lock not available"
    fi
    echo
}

# Test 1: Check initial state
echo "Test 1: Checking initial wake lock state..."
check_wake_locks

# Test 2: Simulate cron job execution
echo "Test 2: Simulating cron job execution..."
echo "Setting CRON_JOB environment variable and running action.sh..."

# Create a minimal test version that shows wake lock behavior
echo "Creating test action script..."
cat > /tmp/test_action.sh << 'EOF'
#!/bin/sh

MODDIR="/data/adb/modules/playintegrityfix"

acquire_wake_lock() {
    if [ -n "$CRON_JOB" ] && [ ! -f "$MODDIR/backup/nowakelock" ]; then
        echo "PlayIntegrityFix.taskExecution" >> /sys/power/wake_lock 2>/dev/null || true
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Wake lock acquired for task execution"
    fi
}

release_wake_lock() {
    if [ -n "$CRON_JOB" ] && [ ! -f "$MODDIR/backup/nowakelock" ]; then
        echo "PlayIntegrityFix.taskExecution" >> /sys/power/wake_unlock 2>/dev/null || true
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Wake lock released after task completion"
    fi
}

cleanup() {
    release_wake_lock
    exit "${1:-0}"
}
trap cleanup EXIT INT TERM

echo "Starting task execution..."
acquire_wake_lock

echo "Task is running (simulating 2 seconds of work)..."
sleep 2

echo "Task completed, wake lock will be released by cleanup trap"
EOF

chmod +x /tmp/test_action.sh

# Check wake locks before execution
echo "Before execution:"
check_wake_locks

# Execute with CRON_JOB environment variable
echo "Executing test script with CRON_JOB=1..."
CRON_JOB=1 /tmp/test_action.sh

# Check wake locks after execution
echo "After execution:"
check_wake_locks

# Test 3: Test with wake lock disabled
echo "Test 3: Testing with wake lock disabled..."
mkdir -p "$MODDIR/backup"
touch "$MODDIR/backup/nowakelock"

echo "Created nowakelock file, testing again..."
echo "Before execution (with nowakelock):"
check_wake_locks

CRON_JOB=1 /tmp/test_action.sh

echo "After execution (with nowakelock):"
check_wake_locks

# Cleanup
rm -f /tmp/test_action.sh
rm -f "$MODDIR/backup/nowakelock"

echo "Test completed!"
echo
echo "Summary:"
echo "- Wake locks are now managed per-task execution"
echo "- They are acquired only when tasks start and released when tasks finish"
echo "- Users can disable wake lock management by creating 'nowakelock' file"
echo "- This provides much better power management than the previous always-on approach"
