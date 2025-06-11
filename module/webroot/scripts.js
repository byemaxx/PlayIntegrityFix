let shellRunning = false;
let initialPinchDistance = null;
let currentFontSize = 14;
const MIN_FONT_SIZE = 8;
const MAX_FONT_SIZE = 24;

const spoofProviderToggle = document.getElementById('toggle-spoofProvider');
const spoofPropsToggle = document.getElementById('toggle-spoofProps');
const spoofSignatureToggle = document.getElementById('toggle-spoofSignature');
const debugToggle = document.getElementById('toggle-debug');
const spoofVendingSdkToggle = document.getElementById('toggle-sdk-vending');
const cronToggle = document.getElementById('toggle-cron');
const cronInterval = document.getElementById('cron-interval');
const cronIntervalType = document.getElementById('cron-interval-type');
const customHours = document.getElementById('custom-hours');
const customMinutes = document.getElementById('custom-minutes');
const cronToggleContainer = document.getElementById('cron-toggle-container');
const spoofConfig = [
    { container: "spoofProvider-toggle-container", toggle: spoofProviderToggle, type: 'spoofProvider' },
    { container: "spoofProps-toggle-container", toggle: spoofPropsToggle, type: 'spoofProps' },
    { container: "spoofSignature-toggle-container", toggle: spoofSignatureToggle, type: 'spoofSignature' },
    { container: "debug-toggle-container", toggle: debugToggle, type: 'DEBUG' },
    { container: "sdk-vending-toggle-container", toggle: spoofVendingSdkToggle, type: 'spoofVendingSdk' }
];

// Execute shell commands with ksu.exec
async function execCommand(command) {
    const callbackName = `exec_callback_${Date.now()}`;
    return new Promise((resolve, reject) => {
        window[callbackName] = (errno, stdout, stderr) => {
            delete window[callbackName];
            errno === 0 ? resolve(stdout) : reject(stderr);
        };
        ksu.exec(command, "{}", callbackName);
    });
}

// Apply button event listeners
function applyButtonEventListeners() {    const fetchButton = document.getElementById('fetch');
    const previewFpToggle = document.getElementById('preview-fp-toggle-container');
    const clearButton = document.querySelector('.clear-terminal');
    const terminal = document.querySelector('.output-terminal-content');

    fetchButton.addEventListener('click', runAction);
    previewFpToggle.addEventListener('click', async () => {
        if (shellRunning) return;
        shellRunning = true;
        try {
            const isChecked = document.getElementById('toggle-preview-fp').checked;
            await execCommand(`sed -i 's/^FORCE_PREVIEW=.*$/FORCE_PREVIEW=${isChecked ? 0 : 1}/' /data/adb/modules/playintegrityfix/action.sh`);
            appendToOutput(`[+] Switched fingerprint to ${isChecked ? 'beta' : 'preview'}`);
            loadPreviewFingerprintConfig();
        } catch (error) {
            appendToOutput("[!] Failed to switch fingerprint type");
            console.error('Failed to switch fingerprint type:', error);
        }
        shellRunning = false;
    });    // 已移除advanced按钮点击事件
        clearButton.addEventListener('click', () => {
        terminal.innerHTML = '';
        currentFontSize = 14;
        updateFontSize(currentFontSize);
    });
    
    // Cron interval type change handler
    cronIntervalType.addEventListener('change', () => {
        const isCustom = cronIntervalType.value === 'custom';
        const presetGroup = document.getElementById('preset-interval-group');
        const customGroup = document.getElementById('custom-time-group');
        
        if (isCustom) {
            presetGroup.style.display = 'none';
            customGroup.style.display = 'block';
        } else {
            presetGroup.style.display = 'block';
            customGroup.style.display = 'none';
        }
        
        // Update cron job if currently enabled
        if (cronToggle.checked && !shellRunning) {
            updateCronJobWithCurrentSettings();
        }
    });
    
    terminal.addEventListener('touchstart', (e) => {
        if (e.touches.length === 2) {
            e.preventDefault();
            initialPinchDistance = getDistance(e.touches[0], e.touches[1]);
        }
    }, { passive: false });
    terminal.addEventListener('touchmove', (e) => {
        if (e.touches.length === 2) {
            e.preventDefault();
            const currentDistance = getDistance(e.touches[0], e.touches[1]);
            
            if (initialPinchDistance === null) {
                initialPinchDistance = currentDistance;
                return;
            }

            const scale = currentDistance / initialPinchDistance;
            const newFontSize = currentFontSize * scale;
            updateFontSize(newFontSize);
            initialPinchDistance = currentDistance;
        }
    }, { passive: false });
    terminal.addEventListener('touchend', () => {
        initialPinchDistance = null;
    });
}

// Function to load the version from module.prop
async function loadVersionFromModuleProp() {
    const versionElement = document.getElementById('version-text');
    try {
        const version = await execCommand("grep '^version=' /data/adb/modules/playintegrityfix/module.prop | cut -d'=' -f2");
        versionElement.textContent = version.trim();
    } catch (error) {
        appendToOutput("[!] Failed to read version from module.prop");
        console.error("Failed to read version from module.prop:", error);
    }
}

// Function to load spoof config
async function loadSpoofConfig() {
    try {
        const pifJson = await execCommand(`cat /data/adb/modules/playintegrityfix/pif.json`);
        const config = JSON.parse(pifJson);        spoofProviderToggle.checked = config.spoofProvider;
        spoofPropsToggle.checked = config.spoofProps;
        spoofSignatureToggle.checked = config.spoofSignature;
        debugToggle.checked = config.DEBUG;
        spoofVendingSdkToggle.checked = config.spoofVendingSdk;
        
    } catch (error) {
        appendToOutput(`[!] Failed to load spoof config`);
        console.error(`Failed to load spoof config:`, error);
    }
}

// Function to setup spoof config button
function setupSpoofConfigButton(container, toggle, type) {
    document.getElementById(container).addEventListener('click', async () => {
        if (shellRunning) return;
        shellRunning = true;
        try {
            const pifFile = await execCommand(`
                [ ! -f /data/adb/modules/playintegrityfix/pif.json ] || echo "/data/adb/modules/playintegrityfix/pif.json"
                [ ! -f /data/adb/pif.json ] || echo "/data/adb/pif.json"
            `);            const files = pifFile.split('\n').filter(line => line.trim() !== '');
            
            for (const line of files) {
                await updateSpoofConfig(toggle, type, line.trim());
            }
            
            execCommand(`
                killall com.google.android.gms.unstable || true
                killall com.android.vending || true
            `);
            loadSpoofConfig();
            appendToOutput(`[+] Changed ${type} config to ${!toggle.checked}`);
        } catch (error) {
            appendToOutput(`[!] Failed to update ${type} config`);
            console.error(`Failed to update ${type} config:`, error);
        }
        shellRunning = false;
    });
}

// Function to update spoof config
async function updateSpoofConfig(toggle, type, pifFile) {
    const isChecked = toggle.checked;
    const pifJson = await execCommand(`cat ${pifFile}`);
    const config = JSON.parse(pifJson);
    config[type] = !isChecked;
    const newPifJson = JSON.stringify(config, null, 2);
    await execCommand(`echo '${newPifJson}' > ${pifFile}`);
}

// Function to load preview fingerprint config
async function loadPreviewFingerprintConfig() {
    try {
        const previewFpToggle = document.getElementById('toggle-preview-fp');
        const isChecked = await execCommand(`grep -o 'FORCE_PREVIEW=[01]' /data/adb/modules/playintegrityfix/action.sh | cut -d'=' -f2`);
        if (isChecked === '0') {
            previewFpToggle.checked = false;
        } else {
            previewFpToggle.checked = true;
        }
    } catch (error) {
        appendToOutput("[!] Failed to load preview fingerprint config");
        console.error("Failed to load preview fingerprint config:", error);
    }
}

// Function to load cron job config
async function loadCronConfig() {
    try {
        // Use cron_manager.sh to check status
        const statusOutput = await execCommand(`sh /data/adb/modules/playintegrityfix/cron_manager.sh status`);
        const isEnabled = statusOutput.trim().startsWith('enabled:');
        
        cronToggle.checked = isEnabled;
        
        // Show/hide interval section based on status
        const intervalSection = document.getElementById('cron-interval-section');
        intervalSection.style.display = isEnabled ? 'block' : 'none';
        
        if (isEnabled) {
            // Parse interval from status output
            const cronLine = statusOutput.replace('enabled:', '');
            const timeSettings = parseCronSettings(cronLine.trim());
            applyCronSettings(timeSettings);
        }
        
        updateCronStatus(isEnabled);
    } catch (error) {
        appendToOutput("[!] Failed to load cron config");
        console.error("Failed to load cron config:", error);
    }
}

// Function to get current time settings
function getCurrentTimeSettings() {
    const isCustom = cronIntervalType.value === 'custom';
    
    if (isCustom) {
        const hours = customHours.value;
        const minutes = customMinutes.value;
        return `custom:${hours}:${minutes}`;
    } else {
        return cronInterval.value;
    }
}

// Function to update cron job with current settings
async function updateCronJobWithCurrentSettings() {
    if (shellRunning) return;
    shellRunning = true;
    try {
        const timeSettings = getCurrentTimeSettings();
        await setupCronJob(true, timeSettings);
        updateCronStatus(true);
    } catch (error) {
        appendToOutput("[!] Failed to update cron settings");
        console.error('Failed to update cron settings:', error);
    }
    shellRunning = false;
}
// Function to parse cron settings from cron line
function parseCronSettings(cronLine) {
    if (!cronLine) return { type: 'preset', value: '24h' };
    
    // Parse different cron formats
    if (cronLine.match(/^\d+ \d+ \* \* \*/)) {
        // Custom time format: "M H * * *"
        const match = cronLine.match(/^(\d+) (\d+) \* \* \*/);
        if (match) {
            return {
                type: 'custom',
                hours: match[2],
                minutes: match[1]
            };
        }
    } else if (cronLine.match(/^0 \*\/(\d+) \* \* \*/)) {
        // Interval format: "0 */X * * *"
        const match = cronLine.match(/^0 \*\/(\d+) \* \* \*/);
        if (match) {
            return { type: 'preset', value: `${match[1]}h` };
        }
    } else if (cronLine.match(/^\*\/(\d+) \* \* \* \*/)) {
        // Minute interval format: "*/X * * * *"
        const match = cronLine.match(/^\*\/(\d+) \* \* \* \*/);
        if (match) {
            return { type: 'preset', value: `${match[1]}m` };
        }
    } else if (cronLine.match(/^0 0 \* \* \*/)) {
        // Daily format: "0 0 * * *"
        return { type: 'preset', value: '24h' };
    }
    
    return { type: 'preset', value: '24h' }; // Default fallback
}

// Function to apply cron settings to UI
function applyCronSettings(settings) {
    if (settings.type === 'custom') {
        cronIntervalType.value = 'custom';
        customHours.value = settings.hours;
        customMinutes.value = settings.minutes;
        document.getElementById('preset-interval-group').style.display = 'none';
        document.getElementById('custom-time-group').style.display = 'block';
    } else {
        cronIntervalType.value = 'preset';
        cronInterval.value = settings.value;
        document.getElementById('preset-interval-group').style.display = 'block';
        document.getElementById('custom-time-group').style.display = 'none';
    }
}

// Function to update cron status display
function updateCronStatus(isEnabled) {
    const statusText = document.getElementById('cron-status-text');
    if (isEnabled) {
        const timeSettings = getCurrentTimeSettings();
        let statusMessage;
        
        if (timeSettings.startsWith('custom:')) {
            const [, hours, minutes] = timeSettings.split(':');
            statusMessage = `Status: Active (Daily at ${hours.padStart(2, '0')}:${minutes.padStart(2, '0')})`;
        } else {
            const value = timeSettings.replace(/[hm]$/, '');
            const unit = timeSettings.endsWith('m') ? 'minute' : 'hour';
            const plural = value !== '1' ? 's' : '';
            statusMessage = `Status: Active (Every ${value} ${unit}${plural})`;
        }
        
        statusText.textContent = statusMessage;
        statusText.style.color = 'var(--btn-primary)';
    } else {
        statusText.textContent = 'Status: Disabled';
        statusText.style.color = 'var(--text-muted)';
    }
}

// Function to setup cron job
async function setupCronJob(enable, timeSettings) {
    try {
        if (enable) {
            // Use cron_manager.sh to add cron job
            await execCommand(`sh /data/adb/modules/playintegrityfix/cron_manager.sh add "${timeSettings}"`);
            
            let message;
            if (timeSettings.startsWith('custom:')) {
                const [, hours, minutes] = timeSettings.split(':');
                message = `[+] Cron job enabled: Daily at ${hours.padStart(2, '0')}:${minutes.padStart(2, '0')}`;
            } else {
                const value = timeSettings.replace(/[hm]$/, '');
                const unit = timeSettings.endsWith('m') ? 'minute' : 'hour';
                const plural = value !== '1' ? 's' : '';
                message = `[+] Cron job enabled: Every ${value} ${unit}${plural}`;
            }
            appendToOutput(message);
        } else {
            // Use cron_manager.sh to remove cron job
            await execCommand(`sh /data/adb/modules/playintegrityfix/cron_manager.sh remove`);
            appendToOutput("[+] Cron job disabled");
        }
        
        updateCronStatus(enable);
        return true;
    } catch (error) {
        appendToOutput("[!] Failed to setup cron job");
        console.error("Failed to setup cron job:", error);
        return false;
    }
}
/**
 * Simulate MD3 ripple animation
 * Usage: class="ripple-element" style="position: relative; overflow: hidden;"
 * Note: Require background-color to work properly
 * @return {void}
 */
function applyRippleEffect() {
    document.querySelectorAll('.ripple-element').forEach(element => {
        if (element.dataset.rippleListener !== "true") {
            element.addEventListener("pointerdown", async (event) => {
                // Pointer up event
                const handlePointerUp = () => {
                    ripple.classList.add("end");
                    setTimeout(() => {
                        ripple.classList.remove("end");
                        ripple.remove();
                    }, duration * 1000);
                    element.removeEventListener("pointerup", handlePointerUp);
                    element.removeEventListener("pointercancel", handlePointerUp);
                };
                element.addEventListener("pointerup", handlePointerUp);
                element.addEventListener("pointercancel", handlePointerUp);

                const ripple = document.createElement("span");
                ripple.classList.add("ripple");

                // Calculate ripple size and position
                const rect = element.getBoundingClientRect();
                const width = rect.width;
                const size = Math.max(rect.width, rect.height);
                const x = event.clientX - rect.left - size / 2;
                const y = event.clientY - rect.top - size / 2;

                // Determine animation duration
                let duration = 0.2 + (width / 800) * 0.4;
                duration = Math.min(0.8, Math.max(0.2, duration));

                // Set ripple styles
                ripple.style.width = ripple.style.height = `${size}px`;
                ripple.style.left = `${x}px`;
                ripple.style.top = `${y}px`;
                ripple.style.animationDuration = `${duration}s`;
                ripple.style.transition = `opacity ${duration}s ease`;

                // Adaptive color
                const computedStyle = window.getComputedStyle(element);
                const bgColor = computedStyle.backgroundColor || "rgba(0, 0, 0, 0)";
                const isDarkColor = (color) => {
                    const rgb = color.match(/\d+/g);
                    if (!rgb) return false;
                    const [r, g, b] = rgb.map(Number);
                    return (r * 0.299 + g * 0.587 + b * 0.114) < 96; // Luma formula
                };
                ripple.style.backgroundColor = isDarkColor(bgColor) ? "rgba(255, 255, 255, 0.2)" : "";

                // Append ripple
                element.appendChild(ripple);
            });
            element.dataset.rippleListener = "true";
        }
    });
}

// Function to check if running in MMRL
async function checkMMRL() {
    if (typeof ksu !== 'undefined' && ksu.mmrl) {
        // Set status bars theme based on device theme
        try {
            $playintegrityfix.setLightStatusBars(!window.matchMedia('(prefers-color-scheme: dark)').matches)
        } catch (error) {
            console.log("Error setting status bars theme:", error)
        }
    }
}

function getDistance(touch1, touch2) {
    return Math.hypot(
        touch1.clientX - touch2.clientX,
        touch1.clientY - touch2.clientY
    );
}

function updateFontSize(newSize) {
    currentFontSize = Math.min(Math.max(newSize, MIN_FONT_SIZE), MAX_FONT_SIZE);
    const terminal = document.querySelector('.output-terminal-content');
    terminal.style.fontSize = `${currentFontSize}px`;
}

document.addEventListener('DOMContentLoaded', async () => {
    checkMMRL();
    loadVersionFromModuleProp();
    await loadSpoofConfig();
    await loadCronConfig();
    spoofConfig.forEach(config => {
        setupSpoofConfigButton(config.container, config.toggle, config.type);
    });
    loadPreviewFingerprintConfig();
    applyButtonEventListeners();
    applyRippleEffect();
      // Enable all toggle elements after loading configs
    document.querySelectorAll('input[type="checkbox"], input[type="number"], select').forEach(element => {
        element.disabled = false;
    });
    
    const lists = Array.from(document.querySelectorAll('.toggle-list'));
    lists.forEach(list => list.style.borderBottom = '1px solid var(--border-color)');
    const visibleLists = lists.filter(list => getComputedStyle(list).display !== 'none');
    if (visibleLists.length > 0) visibleLists[visibleLists.length - 1].style.borderBottom = 'none';
});

// Cron toggle event listener
cronToggleContainer.addEventListener('click', async () => {
    if (shellRunning) return;
    shellRunning = true;
    try {
        const isChecked = cronToggle.checked;
        const timeSettings = getCurrentTimeSettings();
        
        const success = await setupCronJob(!isChecked, timeSettings);
        if (success) {
            cronToggle.checked = !isChecked;
            const intervalSection = document.getElementById('cron-interval-section');
            intervalSection.style.display = !isChecked ? 'block' : 'none';
        }
    } catch (error) {
        appendToOutput("[!] Failed to toggle cron job");
        console.error('Failed to toggle cron job:', error);
    }
    shellRunning = false;
});

// Cron interval change event listener
cronInterval.addEventListener('change', async () => {
    if (shellRunning || !cronToggle.checked) return;
    updateCronJobWithCurrentSettings();
});

// Custom time change event listeners
customHours.addEventListener('change', async () => {
    if (shellRunning || !cronToggle.checked || cronIntervalType.value !== 'custom') return;
    updateCronJobWithCurrentSettings();
});

customMinutes.addEventListener('change', async () => {
    if (shellRunning || !cronToggle.checked || cronIntervalType.value !== 'custom') return;
    updateCronJobWithCurrentSettings();
});

// Function to append element in output terminal
function appendToOutput(content) {
    const output = document.querySelector('.output-terminal-content');
    if (content.trim() === "") {
        const lineBreak = document.createElement('br');
        output.appendChild(lineBreak);
    } else {
        const line = document.createElement('p');
        line.className = 'output-content';
        line.textContent = content;
        output.appendChild(line);
    }
    output.scrollTop = output.scrollHeight;
}

// Function to run the script and display its output
async function runAction() {
    if (shellRunning) return;
    shellRunning = true;
    try {
        appendToOutput("[+] Fetching pif.json...");
        await new Promise(resolve => setTimeout(resolve, 200));
        // Set MMRL environment variable to indicate webui execution
        const scriptOutput = await execCommand("MMRL=1 sh /data/adb/modules/playintegrityfix/action.sh");
        const lines = scriptOutput.split('\n');
        lines.forEach(line => {
            appendToOutput(line)
        });
        appendToOutput("");
    } catch (error) {
        console.error('Script execution failed:', error);
        appendToOutput("[!] Error: Fail to execute action.sh");
        appendToOutput("");
    }
    shellRunning = false;
}