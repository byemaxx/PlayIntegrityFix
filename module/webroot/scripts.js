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
            const interval = parseCronInterval(cronLine.trim());
            if (interval) {
                cronInterval.value = interval;
            }
        }
        
        updateCronStatus(isEnabled);
    } catch (error) {
        appendToOutput("[!] Failed to load cron config");
        console.error("Failed to load cron config:", error);
    }
}

// Function to parse cron interval from cron line
function parseCronInterval(cronLine) {
    if (!cronLine) return null;
    
    // Parse cron format: "0 */X * * *" for every X hours
    const match = cronLine.match(/^0 \*\/(\d+) \* \* \*/);
    if (match) {
        return match[1];
    }
    
    // Parse cron format: "0 0 * * *" for daily (24 hours)
    if (cronLine.match(/^0 0 \* \* \*/)) {
        return "24";
    }
    
    return "24"; // Default fallback
}

// Function to update cron status display
function updateCronStatus(isEnabled) {
    const statusText = document.getElementById('cron-status-text');
    if (isEnabled) {
        const interval = cronInterval.value;
        statusText.textContent = `Status: Active (Every ${interval} hour${interval !== '1' ? 's' : ''})`;
        statusText.style.color = 'var(--btn-primary)';
    } else {
        statusText.textContent = 'Status: Disabled';
        statusText.style.color = 'var(--text-muted)';
    }
}

// Function to setup cron job
async function setupCronJob(enable, intervalHours) {
    try {
        if (enable) {
            // Use cron_manager.sh to add cron job
            await execCommand(`sh /data/adb/modules/playintegrityfix/cron_manager.sh add ${intervalHours}`);
            appendToOutput(`[+] Cron job enabled: Every ${intervalHours} hour${intervalHours !== '1' ? 's' : ''}`);
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
    document.querySelectorAll('input[type="checkbox"], select').forEach(element => {
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
        const intervalHours = cronInterval.value;
        
        const success = await setupCronJob(!isChecked, intervalHours);
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
    shellRunning = true;
    try {
        const intervalHours = cronInterval.value;
        await setupCronJob(true, intervalHours);
        updateCronStatus(true);    } catch (error) {
        appendToOutput("[!] Failed to update cron interval");
        console.error('Failed to update cron interval:', error);
    }
    shellRunning = false;
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