#!/bin/sh

# Stop and clean up cron service
MODDIR="/data/adb/modules/playintegrityfix"
if [ -f "$MODDIR/cron_manager.sh" ]; then
    sh "$MODDIR/cron_manager.sh" stop 2>/dev/null || true
    # Clean up any remaining config files
    rm -f "$MODDIR/cron_config" "$MODDIR/cron_interval" 2>/dev/null || true
fi

# LeafOS "gmscompat: Dynamically spoof props for GMS"
# https://review.leafos.org/c/LeafOS-Project/android_frameworks_base/+/4416
# https://review.leafos.org/c/LeafOS-Project/android_frameworks_base/+/4417/5
if [ -f /data/system/gms_certified_props.json ]; then
	resetprop -p --delete persist.sys.spoof.gms
fi

# EOF
