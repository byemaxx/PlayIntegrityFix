#!/bin/sh

# Test script for PlayIntegrityFix Auto Update functionality
# This script can be used to test the cron functionality

MODDIR="/data/adb/modules/playintegrityfix"
CRON_MANAGER="$MODDIR/cron_manager.sh"

echo "=== PlayIntegrityFix Auto Update Test ==="
echo

# Test 1: Check if cron_manager.sh exists and is executable
echo "Test 1: Checking cron_manager.sh..."
if [ -f "$CRON_MANAGER" ]; then
    echo "✓ cron_manager.sh exists"
    chmod +x "$CRON_MANAGER"
    echo "✓ Made cron_manager.sh executable"
else
    echo "✗ cron_manager.sh not found"
    exit 1
fi
echo

# Test 2: Check cron daemon availability and smart startup
echo "Test 2: Checking cron daemon availability and smart startup..."
# Test the smart startup logic - should not start daemon if no config exists
"$CRON_MANAGER" start 2>/dev/null
START_STATUS=$?
if [ $START_STATUS -eq 0 ]; then
    echo "✓ Cron manager start command works"
    # Check if daemon actually started (should not start without config)
    if pgrep -f "crond" >/dev/null 2>&1; then
        echo "⚠ Cron daemon started without configuration (this may be expected if config exists)"
    else
        echo "✓ Smart startup: daemon not started without configuration"
    fi
else
    echo "⚠ Cron manager may not be available on this system"
fi
echo

# Test 3: Check current status
echo "Test 3: Checking current cron status..."
STATUS=$("$CRON_MANAGER" status)
echo "Current status: $STATUS"
echo

# Test 4: Test adding a cron job
echo "Test 4: Testing cron job management..."
echo "Adding test cron job (24 hours)..."
if "$CRON_MANAGER" add 24; then
    echo "✓ Successfully added cron job"
    
    # Check if it was added
    NEW_STATUS=$("$CRON_MANAGER" status)
    echo "New status: $NEW_STATUS"
    
    if echo "$NEW_STATUS" | grep -q "enabled:"; then
        echo "✓ Cron job is active"
    else
        echo "✗ Cron job not found after adding"
    fi
else
    echo "✗ Failed to add cron job"
fi
echo

# Test 5: Test different intervals
echo "Test 5: Testing different intervals..."
for INTERVAL in 6 12 48; do
    echo "Testing $INTERVAL hour interval..."
    "$CRON_MANAGER" add "$INTERVAL"
    sleep 1
    STATUS=$("$CRON_MANAGER" status)
    if echo "$STATUS" | grep -q "enabled:"; then
        echo "✓ $INTERVAL hour interval works"
    else
        echo "✗ $INTERVAL hour interval failed"
    fi
done
echo

# Test 6: Test removal
echo "Test 6: Testing cron job removal..."
if "$CRON_MANAGER" remove; then
    echo "✓ Successfully removed cron job"
    
    # Check if it was removed
    FINAL_STATUS=$("$CRON_MANAGER" status)
    echo "Final status: $FINAL_STATUS"
    
    if echo "$FINAL_STATUS" | grep -q "disabled"; then
        echo "✓ Cron job successfully disabled"
    else
        echo "✗ Cron job still active after removal"
    fi
else
    echo "✗ Failed to remove cron job"
fi
echo

# Test 7: Test power-saving behavior
echo "Test 7: Testing power-saving behavior..."
echo "Testing that cron daemon stops when auto-update is disabled..."

# Add a job first
"$CRON_MANAGER" add 24 >/dev/null 2>&1

# Check if daemon is running
DAEMON_RUNNING_BEFORE=""
if pgrep -f "crond" >/dev/null 2>&1; then
    DAEMON_RUNNING_BEFORE="yes"
    echo "✓ Cron daemon running when job is active"
else
    echo "⚠ Cron daemon not detected (may use different process name)"
fi

# Remove the job
"$CRON_MANAGER" remove >/dev/null 2>&1

# Check if daemon stopped
sleep 2  # Give it a moment to stop
DAEMON_RUNNING_AFTER=""
if pgrep -f "crond" >/dev/null 2>&1; then
    DAEMON_RUNNING_AFTER="yes"
    echo "⚠ Cron daemon still running after job removal"
else
    echo "✓ Power-saving: cron daemon stopped when no jobs active"
fi

# Test 8: Test webUI compatibility
echo "Test 8: Testing webUI command compatibility..."
echo "Simulating webUI commands..."

# Test status check command
echo "Testing status check..."
if sh "$CRON_MANAGER" status >/dev/null 2>&1; then
    echo "✓ Status check command works"
else
    echo "✗ Status check command failed"
fi

# Test add command
echo "Testing add command..."
if sh "$CRON_MANAGER" add 24 >/dev/null 2>&1; then
    echo "✓ Add command works"
else
    echo "✗ Add command failed"
fi

# Test remove command
echo "Testing remove command..."
if sh "$CRON_MANAGER" remove >/dev/null 2>&1; then
    echo "✓ Remove command works"
else
    echo "✗ Remove command failed"
fi

echo
echo "=== Test Complete ==="
echo
echo "If all tests passed, the auto update functionality should work correctly."
echo "You can now use the webUI to enable/disable automatic updates."
