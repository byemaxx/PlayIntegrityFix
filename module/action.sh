#!/bin/sh

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH
MODDIR=/data/adb/modules/playintegrityfix
version=$(grep "^version=" $MODDIR/module.prop | sed 's/version=//g')
FORCE_PREVIEW=1

# Wake lock management for cron execution
acquire_wake_lock() {
    if [ -n "$CRON_JOB" ] && [ ! -f "$MODDIR/backup/nowakelock" ]; then
        echo "PlayIntegrityFix.taskExecution" >> /sys/power/wake_lock 2>/dev/null || true
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Wake lock acquired for task execution" >> "$MODDIR/cron.log"
    fi
}

release_wake_lock() {
    if [ -n "$CRON_JOB" ] && [ ! -f "$MODDIR/backup/nowakelock" ]; then
        echo "PlayIntegrityFix.taskExecution" >> /sys/power/wake_unlock 2>/dev/null || true
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Wake lock released after task completion" >> "$MODDIR/cron.log"
    fi
}

# Cron execution logging
log_cron_execution() {
    if [ -n "$CRON_JOB" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto update started" >> "$MODDIR/cron.log"
    fi
}

log_cron_completion() {
    if [ -n "$CRON_JOB" ]; then
        local exit_code="${1:-0}"
        if [ "$exit_code" -eq 0 ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto update completed successfully" >> "$MODDIR/cron.log"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto update failed (exit code: $exit_code)" >> "$MODDIR/cron.log"
        fi
    fi
}

# Set up cleanup trap to ensure wake lock is always released
cleanup() {
    local exit_code=$?
    release_wake_lock
    log_cron_completion "$exit_code"
    rm -rf "$TEMPDIR" 2>/dev/null || true
    exit "${1:-$exit_code}"
}
trap cleanup EXIT INT TERM

# Log cron execution start
log_cron_execution

# Acquire wake lock at the start of execution
acquire_wake_lock

# lets try to use tmpfs for processing
TEMPDIR="$MODDIR/temp" #fallback
[ -w /sbin ] && TEMPDIR="/sbin/playintegrityfix"
[ -w /debug_ramdisk ] && TEMPDIR="/debug_ramdisk/playintegrityfix"
[ -w /dev ] && TEMPDIR="/dev/playintegrityfix"
mkdir -p "$TEMPDIR"
cd "$TEMPDIR"

echo "[+] PlayIntegrityFix $version"
echo "[+] $(basename "$0")"
printf "\n\n"

sleep_pause() {
	# APatch and KernelSU needs this
	# but not KSU_NEXT, MMRL
	if [ -z "$MMRL" ] && [ -z "$KSU_NEXT" ] && { [ "$KSU" = "true" ] || [ "$APATCH" = "true" ]; }; then
		sleep 5
	fi
}

download_fail() {
	dl_domain=$(echo "$1" | awk -F[/:] '{print $4}')
	echo "$1" | grep -q "\.zip$" && return
	
	# Clean up on download fail
	rm -rf "$TEMPDIR"
	
	ping -c 1 -W 5 "$dl_domain" > /dev/null 2>&1 || {
		echo "[!] Unable to connect to $dl_domain, please check your internet connection and try again"
		sleep_pause
		exit 1
	}
	
	conflict_module=$(ls /data/adb/modules | grep busybox)
	for i in $conflict_module; do 
		echo "[!] Please remove $i and try again." 
	done
	echo "[!] download failed!"
	echo "[x] bailing out!"
	sleep_pause
	exit 1
}

download() { busybox wget -T 10 --no-check-certificate -qO - "$1" > "$2" || download_fail "$1"; }
if command -v curl > /dev/null 2>&1; then
	download() { curl --connect-timeout 10 -s "$1" > "$2" || download_fail "$1"; }
fi

set_random_beta() {
	if [ "$(echo "$MODEL_LIST" | wc -l)" -ne "$(echo "$PRODUCT_LIST" | wc -l)" ]; then
		echo "Warning: MODEL_LIST and PRODUCT_LIST have different lengths, using Pixel 6 fallback"
		MODEL="Pixel 6"
		PRODUCT="oriole_beta"
	else
		count=$(echo "$MODEL_LIST" | wc -l)
		rand_index=$(( $$ % count ))
		MODEL=$(echo "$MODEL_LIST" | sed -n "$((rand_index + 1))p")
		PRODUCT=$(echo "$PRODUCT_LIST" | sed -n "$((rand_index + 1))p")
	fi
}

# Get latest Pixel Beta information
download https://developer.android.com/about/versions PIXEL_VERSIONS_HTML
BETA_URL=$(grep -o 'https://developer.android.com/about/versions/.*[0-9]"' PIXEL_VERSIONS_HTML | sort -ru | cut -d\" -f1 | head -n1)
download "$BETA_URL" PIXEL_LATEST_HTML

# Handle Developer Preview vs Beta
if grep -qE 'Developer Preview|tooltip>.*preview program' PIXEL_LATEST_HTML && [ "$FORCE_PREVIEW" = 0 ]; then
	# Use the second latest version for beta
	BETA_URL=$(grep -o 'https://developer.android.com/about/versions/.*[0-9]"' PIXEL_VERSIONS_HTML | sort -ru | cut -d\" -f1 | head -n2 | tail -n1)
	download "$BETA_URL" PIXEL_BETA_HTML
else
	mv -f PIXEL_LATEST_HTML PIXEL_BETA_HTML
fi

# Get OTA information
OTA_URL="https://developer.android.com$(grep -o 'href=".*download-ota.*"' PIXEL_BETA_HTML | cut -d\" -f2 | head -n1)"
download "$OTA_URL" PIXEL_OTA_HTML

# Extract device information
MODEL_LIST="$(grep -A1 'tr id=' PIXEL_OTA_HTML | grep 'td' | sed 's;.*<td>\(.*\)</td>;\1;')"
PRODUCT_LIST="$(grep -o 'ota/.*_beta' PIXEL_OTA_HTML | cut -d\/ -f2)"
OTA_LIST="$(grep 'ota/.*_beta' PIXEL_OTA_HTML | cut -d\" -f2)"

# Select and configure device
echo "- Selecting Pixel Beta device ..."
[ -z "$PRODUCT" ] && set_random_beta
echo "$MODEL ($PRODUCT)"

# Get device fingerprint and security patch from OTA metadata
(ulimit -f 2; download "$(echo "$OTA_LIST" | grep "$PRODUCT")" PIXEL_ZIP_METADATA) >/dev/null 2>&1
FINGERPRINT="$(strings PIXEL_ZIP_METADATA | grep -am1 'post-build=' | cut -d= -f2)"
SECURITY_PATCH="$(strings PIXEL_ZIP_METADATA | grep -am1 'security-patch-level=' | cut -d= -f2)"

# Validate required field to prevent empty pif.json
if [ -z "$FINGERPRINT" ] || [ -z "$SECURITY_PATCH" ]; then
    echo "[!] Failed to extract required fields from OTA metadata"
    echo "[!] FINGERPRINT: '$FINGERPRINT'"
    echo "[!] SECURITY_PATCH: '$SECURITY_PATCH'"
    # Trigger download failure handling to check connectivity and cleanup
    download_fail "https://dl.google.com"
fi

# Preserve previous setting
spoofConfig="spoofProvider spoofProps spoofSignature DEBUG spoofVendingSdk"
for config in $spoofConfig; do
	if grep -q "\"$config\": true" "$MODDIR/pif.json"; then
		eval "$config=true"
	else
		eval "$config=false"
	fi
done

# calculate expiry date for beta
REL_DATE_RAW=$(grep -m1 -A1 'Release date' PIXEL_OTA_HTML | tail -n1 | sed 's;.*<td>\(.*\)</td>.*;\1;')
REL_DATE_FIXED=$(echo "$REL_DATE_RAW" | sed 's/ \([0-9],\)/ 0\1/')

# Universal date parser
parse_date() {
    local input_date="$1"
    local result=""
    
    # 方法1: 尝试使用busybox date解析
    if command -v busybox > /dev/null 2>&1; then
        result=$(busybox date -D '%B %e, %Y' -d "$input_date" +%Y-%m-%d 2>/dev/null)
        [ -n "$result" ] && echo "$result" && return
        result=$(busybox date -D '%B %d, %Y' -d "$input_date" +%Y-%m-%d 2>/dev/null)
        [ -n "$result" ] && echo "$result" && return
    fi
    
    # 方法2: 尝试GNU date
    result=$(date -d "$input_date" +%Y-%m-%d 2>/dev/null)
    [ -n "$result" ] && echo "$result" && return
    
    # 方法3: 手动解析常见格式 (如 "December 5, 2024")
    local month_name=$(echo "$input_date" | awk '{print $1}')
    local day=$(echo "$input_date" | awk '{print $2}' | sed 's/,//')
    local year=$(echo "$input_date" | awk '{print $3}')
      case "$month_name" in
        "January") local month="01" ;;
        "February") local month="02" ;;
        "March") local month="03" ;;
        "April") local month="04" ;;
        "May") local month="05" ;;
        "June") local month="06" ;;
        "July") local month="07" ;;
        "August") local month="08" ;;
        "September") local month="09" ;;
        "October") local month="10" ;;
        "November") local month="11" ;;
        "December") local month="12" ;;
        *) return 1 ;;
    esac
    
    # 确保日期是两位数
    day=$(printf "%02d" "$day" 2>/dev/null) || return 1
    
    echo "$year-$month-$day"
}

BETA_REL_DATE=$(parse_date "$REL_DATE_RAW")
[ -z "$BETA_REL_DATE" ] && BETA_REL_DATE=$(parse_date "$REL_DATE_FIXED")

# 计算过期日期（6 weeks = 42 days）
if [ -n "$BETA_REL_DATE" ]; then
    # 尝试使用busybox date计算
    if command -v busybox > /dev/null 2>&1; then
        BETA_EXP_DATE=$(busybox date -D '%Y-%m-%d' -d "$BETA_REL_DATE" +%s 2>/dev/null)
        if [ -n "$BETA_EXP_DATE" ]; then
            BETA_EXP_DATE=$((BETA_EXP_DATE + 3628800))
            BETA_EXP_DATE=$(busybox date -D '%s' -d "$BETA_EXP_DATE" +%Y-%m-%d 2>/dev/null)
        fi
    fi
    
    # 如果busybox方法失败，尝试GNU date
    if [ -z "$BETA_EXP_DATE" ]; then
        BETA_EXP_DATE=$(date -d "$BETA_REL_DATE + 42 days" +%Y-%m-%d 2>/dev/null)
    fi
      # 如果都失败，使用改进的日期计算（考虑实际月份天数）
    if [ -z "$BETA_EXP_DATE" ]; then
        year=$(echo "$BETA_REL_DATE" | cut -d- -f1)
        month=$(echo "$BETA_REL_DATE" | cut -d- -f2)
        day=$(echo "$BETA_REL_DATE" | cut -d- -f3)
        
        # 加42天的改进计算
        new_day=$((day + 42))
        new_month=$month
        new_year=$year
        
        # 考虑不同月份的天数
        while [ $new_day -gt 28 ]; do
            days_in_month=31
            case $new_month in
                04|06|09|11) days_in_month=30 ;;
                02) 
                    # 简化的闰年检查
                    if [ $((new_year % 4)) -eq 0 ] && { [ $((new_year % 100)) -ne 0 ] || [ $((new_year % 400)) -eq 0 ]; }; then
                        days_in_month=29
                    else
                        days_in_month=28
                    fi
                    ;;
            esac
            
            if [ $new_day -gt $days_in_month ]; then
                new_day=$((new_day - days_in_month))
                new_month=$((new_month + 1))
                if [ $new_month -gt 12 ]; then
                    new_year=$((new_year + 1))
                    new_month=1
                fi
            else
                break
            fi
        done
        BETA_EXP_DATE=$(printf "%04d-%02d-%02d" "$new_year" "$new_month" "$new_day")
    fi
fi

# # Debug output for date parsing
# echo "- Date parsing debug info:"
# echo "  Raw date from HTML: '$REL_DATE_RAW'"
# echo "  Fixed date format: '$REL_DATE_FIXED'"
# echo "  Parsed release date: '$BETA_REL_DATE'"
# echo "  Estimated expiry date: '$BETA_EXP_DATE'"
# echo "  Available date commands:"
# echo "    busybox: $(command -v busybox >/dev/null && echo 'yes' || echo 'no')"
# echo "    date: $(command -v date >/dev/null && echo 'yes' || echo 'no')"

# Determine update method
UPDATE_METHOD="manual"
if [ -n "$CRON_JOB" ] || echo "$0" | grep -q "cron"; then
    UPDATE_METHOD="auto"
elif [ -n "$MMRL" ]; then
    UPDATE_METHOD="webui"
fi

# Get current timestamp
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')

echo "- Dumping values to pif.json ..."
cat <<EOF | tee pif.json
{
  "FINGERPRINT": "$FINGERPRINT",
  "MANUFACTURER": "Google",
  "MODEL": "$MODEL",
  "SECURITY_PATCH": "$SECURITY_PATCH",
  "spoofProvider": $spoofProvider,
  "spoofProps": $spoofProps,
  "spoofSignature": $spoofSignature,
  "DEBUG": $DEBUG,
  "spoofVendingSdk": $spoofVendingSdk,
  "// BETA_RELEASE_DATE": "$BETA_REL_DATE",
  "// ESTIMATED_EXPIRY": "$BETA_EXP_DATE",
  "// LAST_UPDATE_TIME": "$CURRENT_TIME",
  "// UPDATE_METHOD": "$UPDATE_METHOD"
}
EOF

cat "$TEMPDIR/pif.json" > /data/adb/pif.json
echo "- new pif.json saved to /data/adb/pif.json"

echo "- Cleaning up ..."
rm -rf "$TEMPDIR"

for i in $(busybox pidof com.google.android.gms.unstable); do
	echo "- Killing pid $i"
	kill -9 "$i"
done

echo "- Done!"
sleep_pause

# Wake lock will be automatically released by the cleanup trap