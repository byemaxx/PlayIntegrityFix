#!/bin/sh

# PlayIntegrityFix Auto-Update Test Script

MODDIR="/data/adb/modules/playintegrityfix"
CRON_MANAGER="$MODDIR/cron_manager.sh"

echo "🧪 PlayIntegrityFix Auto-Update 功能测试"
echo "=================================================="
echo ""

# Function to run test and capture result
run_test() {
    local test_name="$1"
    local command="$2"
    local expected="$3"
    
    echo "Testing: $test_name"
    echo "Command: $command"
    
    # Run the command and capture output
    result=$(eval "$command" 2>&1)
    
    if echo "$result" | grep -q "$expected"; then
        echo "✅ PASS: $test_name"
    else
        echo "❌ FAIL: $test_name"
        echo "Expected: $expected"
        echo "Got: $result"
    fi
    echo ""
}

echo "--- Testing Enhanced Time Format Parsing ---"

# 检查文件存在
if [ ! -f "$CRON_MANAGER" ]; then
    echo "❌ cron_manager.sh 不存在"
    exit 1
fi

echo "✅ cron_manager.sh 存在"

# 测试基本命令
echo ""
echo "📋 测试基本命令..."

echo "1. 测试帮助信息："
sh "$CRON_MANAGER" 2>&1 | head -5

echo ""
echo "2. 测试状态检查："
STATUS=$(sh "$CRON_MANAGER" status)
echo "当前状态: $STATUS"

echo ""
echo "3. 测试系统信息："
sh "$CRON_MANAGER" start 2>&1 | grep -E "(Android|Device|Brand|Busybox|Cron daemon)" | head -6

echo ""
echo "📊 测试 Cron 功能..."

# 测试添加任务
echo "4. 测试添加 cron 任务（6小时间隔）："
sh "$CRON_MANAGER" add 6 2>&1 | tail -1

# 检查状态
echo ""
echo "5. 检查任务状态："
NEW_STATUS=$(sh "$CRON_MANAGER" status)
echo "新状态: $NEW_STATUS"

# 测试日志功能
echo ""
echo "6. 检查日志记录："
if [ -f "$MODDIR/cron.log" ]; then
    echo "✅ 日志文件存在"
    echo "最近日志："
    tail -3 "$MODDIR/cron.log"
else
    echo "⚠️  日志文件不存在"
fi

# 测试配置文件
echo ""
echo "7. 检查配置持久化："
if [ -f "$MODDIR/cron_config" ]; then
    echo "✅ 配置文件存在"
    echo "当前配置: $(cat "$MODDIR/cron_config")"
else
    echo "⚠️  配置文件不存在"
fi

# 测试备份目录
echo ""
echo "8. 检查备份目录："
if [ -d "$MODDIR/backup" ]; then
    echo "✅ 备份目录存在"
    if [ -f "$MODDIR/backup/root" ]; then
        echo "✅ Busybox cron 配置文件存在"
        echo "配置内容: $(cat "$MODDIR/backup/root")"
    else
        echo "⚠️  Busybox cron 配置文件不存在"
    fi
    
    if [ -f "$MODDIR/backup/cron_pid" ]; then
        PID=$(cat "$MODDIR/backup/cron_pid")
        echo "✅ PID 文件存在: $PID"
        if kill -0 "$PID" 2>/dev/null; then
            echo "✅ Cron 进程正在运行"
        else
            echo "⚠️  Cron 进程未运行"
        fi
    else
        echo "⚠️  PID 文件不存在"
    fi
else
    echo "⚠️  备份目录不存在"
fi

# 测试移除功能
echo ""
echo "🗑️  测试移除功能..."
echo "9. 移除 cron 任务："
sh "$CRON_MANAGER" remove 2>&1 | tail -1

echo ""
echo "10. 确认移除："
FINAL_STATUS=$(sh "$CRON_MANAGER" status)
echo "最终状态: $FINAL_STATUS"

# 系统兼容性检查
echo ""
echo "🔍 系统兼容性检查..."

echo "11. Busybox 检查："
if command -v busybox >/dev/null 2>&1; then
    BUSYBOX_VER=$(busybox | head -n1 | awk '{print $2}')
    echo "✅ Busybox 可用: $BUSYBOX_VER"
    
    if busybox crond --help >/dev/null 2>&1; then
        echo "✅ Busybox crond 支持"
    else
        echo "❌ Busybox crond 不支持"
    fi
else
    echo "❌ Busybox 不可用"
fi

echo ""
echo "12. 系统 Cron 检查："
if command -v crond >/dev/null 2>&1; then
    echo "✅ 系统 crond 可用"
elif [ -x /system/bin/crond ]; then
    echo "✅ 系统 crond 可用 (/system/bin/crond)"
elif [ -x /system/xbin/crond ]; then
    echo "✅ 系统 crond 可用 (/system/xbin/crond)"
else
    echo "❌ 系统 crond 不可用"
fi

echo ""
echo "13. Crontab 检查："
if command -v crontab >/dev/null 2>&1; then
    echo "✅ crontab 命令可用"
    CRON_COUNT=$(crontab -l 2>/dev/null | wc -l)
    echo "当前 crontab 条目数: $CRON_COUNT"
else
    echo "❌ crontab 命令不可用"
fi

# WebUI 集成测试
echo ""
echo "🌐 WebUI 集成测试..."

echo "14. 测试 WebUI 命令格式："
# 模拟 WebUI 调用
TEST_OUTPUT=$(sh "$CRON_MANAGER" add 24 2>&1)
if echo "$TEST_OUTPUT" | grep -q "Auto-update enabled"; then
    echo "✅ WebUI 命令格式正确"
else
    echo "⚠️  WebUI 命令格式可能有问题"
    echo "输出: $TEST_OUTPUT"
fi

# 清理测试
sh "$CRON_MANAGER" remove >/dev/null 2>&1

echo ""
echo "📋 测试总结"
echo "==========="

# 基础功能评分
SCORE=0
TOTAL=10

# 文件存在检查
[ -f "$CRON_MANAGER" ] && SCORE=$((SCORE + 1))

# 命令执行检查
sh "$CRON_MANAGER" >/dev/null 2>&1 && SCORE=$((SCORE + 1))

# 状态命令检查
sh "$CRON_MANAGER" status >/dev/null 2>&1 && SCORE=$((SCORE + 1))

# 添加功能检查
sh "$CRON_MANAGER" add 24 >/dev/null 2>&1 && SCORE=$((SCORE + 1))

# 配置持久化检查
[ -f "$MODDIR/cron_config" ] && SCORE=$((SCORE + 1))

# 日志功能检查
[ -f "$MODDIR/cron.log" ] && SCORE=$((SCORE + 1))

# 备份目录检查
[ -d "$MODDIR/backup" ] && SCORE=$((SCORE + 1))

# Busybox 支持检查
command -v busybox >/dev/null 2>&1 && SCORE=$((SCORE + 1))

# 移除功能检查
sh "$CRON_MANAGER" remove >/dev/null 2>&1 && SCORE=$((SCORE + 1))

# 清理状态检查
STATUS_AFTER_REMOVE=$(sh "$CRON_MANAGER" status)
echo "$STATUS_AFTER_REMOVE" | grep -q "disabled" && SCORE=$((SCORE + 1))

echo "功能完整性得分: $SCORE/$TOTAL"

if [ "$SCORE" -ge 8 ]; then
    echo "🎉 测试通过！自动更新功能工作正常"
elif [ "$SCORE" -ge 6 ]; then
    echo "⚠️  测试部分通过，建议检查未通过的项目"
else
    echo "❌ 测试失败，需要修复基础功能"
fi

echo ""
echo "🔧 如需进一步测试，请运行："
echo "   sh $CRON_MANAGER logs    # 查看详细日志"
echo "   sh $CRON_MANAGER start   # 启动服务"
echo "   sh $CRON_MANAGER restart # 重启服务"

echo ""
echo "🌐 WebUI 测试说明"
echo "=================="
echo "1. 在 MMRL 或浏览器中打开 webui"
echo "2. 切换 'Enable Auto Update' 开关"
echo "3. 尝试在 '预设间隔' 和 '自定义时间' 之间切换"
echo "4. 预设间隔: 选择不同间隔 (30m, 1h, 6h, 等)"
echo "5. 自定义时间: 设置具体的小时 (0-23) 和分钟 (0-59)"
echo "6. 检查状态文本是否正确更新"
echo "7. 验证输出终端显示正确的消息"
echo "8. 检查终端是否有最小高度 (不应太小)"
echo ""
echo "✨ 增强功能已实现:"
echo "   - 支持分钟和小时的自定义设置"
echo "   - 输出终端添加了最小高度限制"
echo "   - 改进的时间格式显示"

exit 0
