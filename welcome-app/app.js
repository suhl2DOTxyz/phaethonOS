/* ==============================================================================
# PHAETHON OS - WELCOME LAUNCHER SCRIPT (app.js)
# ==============================================================================
# Core frontend interactivity for the first-launch setup wizard. Handles tab
# routing, hardware GPU detection, modular gaming checkboxes, and mock
# installation console logs while executing actual system commands.
*/

let exec = null;
try {
    const cp = require('child_process');
    exec = cp.exec;
} catch (e) {
    console.log("Not running inside Electron with Node integration. Real shell execution disabled.");
}

document.addEventListener("DOMContentLoaded", () => {
    
    // --- 1. TAB MENU ROUTING SYSTEM ---
    const tabItems = document.querySelectorAll(".tab-item");
    const tabContents = document.querySelectorAll(".tab-content");

    tabItems.forEach(tab => {
        tab.addEventListener("click", () => {
            // Remove active classes
            tabItems.forEach(t => t.classList.remove("active"));
            tabContents.forEach(c => c.classList.remove("active"));

            // Add active classes
            tab.classList.add("active");
            const targetTab = tab.getAttribute("data-tab");
            document.getElementById(`content-${targetTab}`).classList.add("active");
        });
    });

    // Button links to other tabs
    document.getElementById("btn-jump-gaming").addEventListener("click", () => {
        document.getElementById("tab-gaming").click();
    });

    // Real System Command Actions
    if (exec) {
        // Install OS (Calamares)
        document.getElementById("btn-install-os").addEventListener("click", () => {
            exec("/usr/local/bin/phaethon-calamares &", (err) => {
                if (err) console.error("Calamares launch error:", err);
            });
        });

        // Open Plasma Discover (App Center)
        document.getElementById("btn-explore-gui").addEventListener("click", () => {
            exec("plasma-discover &", (err) => {
                if (err) console.error("Discover launch error:", err);
            });
        });
    } else {
        // Fallback alert for manual desktop browsing
        document.getElementById("btn-install-os").addEventListener("click", () => {
            alert("To install Phaethon OS, please launch 'Install Phaethon OS' from your desktop application launcher!");
        });
        document.getElementById("btn-explore-gui").addEventListener("click", () => {
            alert("App Center is only available on a live booted system.");
        });
    }

    // --- 2. GPU / GRAPHICS CARD DETECTION ---
    const gpuStatus = document.getElementById("gpu-detect-status");
    const rowNvidia = document.getElementById("row-nvidia");
    const btnNvidia = document.getElementById("btn-install-nvidia");

    function detectGPU() {
        gpuStatus.textContent = "PROBING SYSTEM HARDWARE... //";
        setTimeout(() => {
            // Probe hardware if exec is available, otherwise mock it
            if (exec) {
                exec("lspci | grep -Ei 'vga|3d'", (err, stdout) => {
                    const gpuInfo = stdout.toLowerCase();
                    if (gpuInfo.includes("nvidia")) {
                        gpuStatus.textContent = "NVIDIA GEFORCE GPU DETECTED // OPTIMAL PROPRIETARY DRIVER RECOMMENDED";
                        gpuStatus.style.borderColor = "#FF4444";
                        rowNvidia.style.opacity = "1";
                    } else if (gpuInfo.includes("amd") || gpuInfo.includes("radeon")) {
                        gpuStatus.textContent = "AMD RADEON GPU DETECTED // MESA STACK OPTIMIZED";
                        gpuStatus.style.borderColor = "#C8FF00";
                        rowNvidia.style.opacity = "0.4";
                        btnNvidia.disabled = true;
                        btnNvidia.style.cursor = "not-allowed";
                    } else {
                        gpuStatus.textContent = "INTEL/INTEGRATED GRAPHICS DETECTED // MESA STACK OPTIMIZED";
                        gpuStatus.style.borderColor = "#C8FF00";
                        rowNvidia.style.opacity = "0.4";
                        btnNvidia.disabled = true;
                        btnNvidia.style.cursor = "not-allowed";
                    }
                });
            } else {
                // Mock default nvidia
                gpuStatus.textContent = "NVIDIA GEFORCE GPU DETECTED // OPTIMAL PROPRIETARY DRIVER RECOMMENDED";
                gpuStatus.style.borderColor = "#FF4444";
                rowNvidia.style.opacity = "1";
            }
        }, 1200);
    }

    detectGPU();

    // --- 3. GAMING SUITE COMPOSITION SELECTIONS ---
    const checkCards = document.querySelectorAll(".check-card");
    checkCards.forEach(card => {
        card.addEventListener("click", () => {
            const indicator = card.querySelector(".checkbox-indicator");
            indicator.classList.toggle("checked");
        });
    });

    // --- 4. INTERACTIVE PROCESS PIPELINES (Executes in background + UI log updates) ---
    function triggerAction(buttonId, originalText, successText, logSteps, systemCmd = null) {
        const btn = document.getElementById(buttonId);
        btn.disabled = true;
        btn.style.backgroundColor = "#888888";
        btn.style.color = "#0a0a0a";
        
        let step = 0;
        const interval = setInterval(() => {
            if (step < logSteps.length) {
                btn.textContent = logSteps[step];
                step++;
            } else {
                clearInterval(interval);
                btn.textContent = "EXECUTING DEPLOYMENT...";
                btn.style.backgroundColor = "#C8FF00";
                btn.style.borderColor = "#C8FF00";
                btn.style.color = "#0a0a0a";
                
                // Execute actual shell command in the background if available
                if (systemCmd && exec) {
                    exec(systemCmd, (error) => {
                        if (error) {
                            console.error(`Command execution failed: ${systemCmd}`, error);
                            btn.textContent = "ERROR // RETRY DEPLOY";
                            btn.disabled = false;
                            btn.style.backgroundColor = "#FF4444";
                            btn.style.borderColor = "#FF4444";
                            btn.style.color = "#FFFFFF";
                        } else {
                            btn.textContent = successText;
                        }
                    });
                } else {
                    btn.textContent = successText;
                }
            }
        }, 1000);
    }

    // Driver Installation
    btnNvidia.addEventListener("click", () => {
        triggerAction("btn-install-nvidia", "INSTALL / NVIDIA", "COMPLETED // DRIVERS INSTALLED", [
            "CONNECTING TO REPOS...",
            "RETRIEVING NVIDIA-DKMS...",
            "COMPILING SYSTEM KERNEL...",
            "REBUILDING INITRAMFS...",
            "ENABLING SERVICES..."
        ], "pkexec pacman -S --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils");
    });

    // Gaming Suite deployment
    document.getElementById("btn-deploy-gaming").addEventListener("click", () => {
        const isSteam = document.getElementById("game-steam").querySelector(".checkbox-indicator").classList.contains("checked");
        const isHeroic = document.getElementById("game-heroic").querySelector(".checkbox-indicator").classList.contains("checked");
        const isBottles = document.getElementById("game-bottles").querySelector(".checkbox-indicator").classList.contains("checked");
        
        let pkgs = [];
        if (isSteam) pkgs.push("steam");
        if (isHeroic) pkgs.push("heroic-games-launcher-bin");
        if (isBottles) pkgs.push("bottles");

        if (pkgs.length === 0) {
            alert("Please select at least one component to deploy!");
            return;
        }

        let cmd = `pkexec pacman -S --noconfirm ${pkgs.join(" ")}`;
        
        triggerAction("btn-deploy-gaming", "DEPLOY / SELECTED GAMES", "DEPLOYED // GAMING READY", [
            "RESOLVING DEPENDENCIES...",
            "DOWNLOADING SELECTED UTILITIES...",
            "INSTALLING WINE-GE LAYERS...",
            "CONFIGURING SHADERS...",
            "LOCKING SCHEDULER DEFAULTS..."
        ], cmd);
    });

    // VS Code deployment
    document.getElementById("btn-install-vscode").addEventListener("click", () => {
        triggerAction("btn-install-vscode", "INSTALL / VS CODE", "INSTALLED // CODE READY", [
            "FETCHING CODE-OSS PACKAGE...",
            "CONFIGURING FONT INTEGRATION...",
            "LINKING TERMINAL PROTOCOLS...",
            "FINISHING DEPLOYMENT..."
        ], "pkexec pacman -S --noconfirm code");
    });

    // Docker services deployment
    document.getElementById("btn-enable-docker").addEventListener("click", () => {
        const btn = document.getElementById("btn-enable-docker");
        btn.disabled = true;
        btn.textContent = "SYNCHRONIZING DAEMON...";
        
        if (exec) {
            exec("pkexec systemctl enable --now docker.service", (err) => {
                if (err) {
                    console.error("Docker service enabling failed:", err);
                    btn.textContent = "ERROR // RETRY DOCKER";
                    btn.disabled = false;
                    btn.style.backgroundColor = "#FF4444";
                    btn.style.borderColor = "#FF4444";
                    btn.style.color = "#FFFFFF";
                } else {
                    btn.textContent = "ENABLED // DOCKER ACTIVE";
                    btn.style.backgroundColor = "#C8FF00";
                    btn.style.borderColor = "#C8FF00";
                    btn.style.color = "#0a0a0a";
                }
            });
        } else {
            setTimeout(() => {
                btn.textContent = "ENABLED // DOCKER ACTIVE";
                btn.style.backgroundColor = "#C8FF00";
                btn.style.borderColor = "#C8FF00";
                btn.style.color = "#0a0a0a";
            }, 1000);
        }
    });
});
