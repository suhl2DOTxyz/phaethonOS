/* ==============================================================================
# PHAETHON OS - WELCOME LAUNCHER SCRIPT (app.js)
# ==============================================================================
# Frontend logic for the first-launch dashboard. Handles tab routing, hardware
# detection, and package/service actions.
#
# DESIGN RULE: this dashboard probes, it never asserts. Every "INSTALLED" or
# "ENABLED" badge below is the result of asking pacman or systemd at runtime.
# The panels used to hardcode their own status, which meant the very first thing
# a new user saw was a confident claim that ZRAM and Ananicy were running on an
# ISO that shipped neither, and an "INSTALL / VS CODE" button for an editor that
# was already installed. A dashboard that lies is worse than no dashboard.
#
# The same rule kills the old fake progress animation: buttons used to tick
# through invented steps ("COMPILING SYSTEM KERNEL...", "CONFIGURING SHADERS...")
# on a timer that had nothing to do with the command actually running. Now a
# button says what it is doing, and reports what actually happened.
*/

let exec = null;
try {
    exec = require('child_process').exec;
} catch (e) {
    console.log("Not running inside Electron with Node integration. Real shell execution disabled.");
}

/* Run a shell command. Resolves {ok, out} rather than rejecting, because every
   caller here treats "command failed" as information, not as an exception. */
function sh(cmd) {
    return new Promise(resolve => {
        if (!exec) return resolve({ ok: false, out: "" });
        exec(cmd, { timeout: 15000 }, (err, stdout) =>
            resolve({ ok: !err, out: (stdout || "").trim() }));
    });
}

const hasPkg  = pkg  => sh(`pacman -Qq ${pkg}`).then(r => r.ok);
const hasCmd  = cmd  => sh(`command -v ${cmd}`).then(r => r.ok);

/* systemd reports plenty of non-"enabled" states that still mean "this will
   run" (static, indirect, generated -- zram's unit is generated). Treat those
   as active, and separately check whether it is running right now. */
async function unitState(unit) {
    const enabled = (await sh(`systemctl is-enabled ${unit} 2>/dev/null`)).out;
    const active  = (await sh(`systemctl is-active ${unit} 2>/dev/null`)).out;
    const on = ["enabled", "enabled-runtime", "static", "indirect", "generated", "alias"];
    return { present: enabled !== "" || active !== "", enabled: on.includes(enabled), active: active === "active" };
}

/* A live ISO session, as opposed to an installed system. */
const isLiveSession = () => sh("test -d /run/archiso").then(r => r.ok);

function setBadge(el, text, tone) {
    el.textContent = text;
    el.classList.remove("active-badge");
    if (tone === "on") el.classList.add("active-badge");
    el.style.color       = tone === "on" ? "" : (tone === "off" ? "#888888" : "#FF4444");
    el.style.borderColor = tone === "on" ? "" : (tone === "off" ? "#888888" : "#FF4444");
}

document.addEventListener("DOMContentLoaded", () => {

    // --- 1. TAB MENU ROUTING SYSTEM ---
    const tabItems = document.querySelectorAll(".tab-item");
    const tabContents = document.querySelectorAll(".tab-content");

    tabItems.forEach(tab => {
        tab.addEventListener("click", () => {
            tabItems.forEach(t => t.classList.remove("active"));
            tabContents.forEach(c => c.classList.remove("active"));
            tab.classList.add("active");
            document.getElementById(`content-${tab.getAttribute("data-tab")}`).classList.add("active");
        });
    });

    document.getElementById("btn-jump-gaming")
        .addEventListener("click", () => document.getElementById("tab-gaming").click());

    // --- 2. WELCOME PANEL: installer + app centre -----------------------------
    const btnInstall = document.getElementById("btn-install-os");
    const btnAppCentre = document.getElementById("btn-explore-gui");

    (async () => {
        // The installer button only belongs on a live session. On an installed
        // system Calamares is gone (shellprocess.conf strips its launcher), so
        // the button could only ever produce an error.
        const live = await isLiveSession();
        const haveInstaller = await hasCmd("calamares");
        if (!live || !haveInstaller) {
            btnInstall.closest(".hero-actions").style.display = "none";
        }
    })();

    btnInstall.addEventListener("click", async () => {
        btnInstall.disabled = true;
        btnInstall.textContent = "STARTING INSTALLER...";
        const r = await sh("setsid /usr/local/bin/phaethon-calamares >/dev/null 2>&1 &");
        if (!r.ok) {
            btnInstall.textContent = "ERROR // SEE TERMINAL";
            btnInstall.disabled = false;
        } else {
            btnInstall.textContent = "INSTALLER LAUNCHED";
        }
    });

    (async () => {
        // Plasma Discover is the "app center" the beginner card promises. If it
        // is not installed, offer to install it rather than opening nothing --
        // this button used to silently do nothing at all.
        const have = await hasCmd("plasma-discover");
        btnAppCentre.textContent = have ? "OPEN / APP CENTER" : "INSTALL / APP CENTER";
        btnAppCentre.addEventListener("click", async () => {
            if (await hasCmd("plasma-discover")) {
                sh("setsid plasma-discover >/dev/null 2>&1 &");
                return;
            }
            btnAppCentre.disabled = true;
            btnAppCentre.textContent = "INSTALLING DISCOVER...";
            const r = await sh("pkexec pacman -S --noconfirm --needed discover");
            btnAppCentre.disabled = false;
            btnAppCentre.textContent = r.ok ? "OPEN / APP CENTER" : "FAILED // RETRY";
        });
    })();

    // --- 3. GPU / GRAPHICS CARD DETECTION ------------------------------------
    const gpuStatus = document.getElementById("gpu-detect-status");
    const rowNvidia = document.getElementById("row-nvidia");
    const btnNvidia = document.getElementById("btn-install-nvidia");

    function disableNvidiaRow(msg, colour) {
        gpuStatus.textContent = msg;
        gpuStatus.style.borderColor = colour;
        rowNvidia.style.opacity = "0.4";
        btnNvidia.disabled = true;
        btnNvidia.style.cursor = "not-allowed";
    }

    (async () => {
        gpuStatus.textContent = "PROBING SYSTEM HARDWARE... //";
        const { ok, out } = await sh("lspci | grep -Ei 'vga|3d|display'");
        if (!ok && !out) {
            // Previously this fell back to *claiming* an NVIDIA card was found,
            // which offered a driver install to machines that have no NVIDIA GPU.
            disableNvidiaRow("GPU DETECTION UNAVAILABLE // NO CHANGES RECOMMENDED", "#888888");
            return;
        }
        const gpu = out.toLowerCase();
        if (gpu.includes("nvidia")) {
            gpuStatus.textContent = "NVIDIA GPU DETECTED // PROPRIETARY DRIVER RECOMMENDED";
            gpuStatus.style.borderColor = "#FF4444";
            rowNvidia.style.opacity = "1";
            if (await hasPkg("nvidia-open-dkms")) {
                btnNvidia.textContent = "INSTALLED // NVIDIA ACTIVE";
                btnNvidia.disabled = true;
            }
        } else if (gpu.includes("amd") || gpu.includes("radeon")) {
            disableNvidiaRow("AMD RADEON GPU DETECTED // MESA STACK OPTIMIZED", "#C8FF00");
        } else {
            disableNvidiaRow("INTEL/INTEGRATED GRAPHICS DETECTED // MESA STACK OPTIMIZED", "#C8FF00");
        }
    })();

    // --- 4. PACKAGE ACTIONS ---------------------------------------------------
    /* One real pipeline: disable, run, report. No invented progress steps. */
    async function installPackages(btn, pkgs, doneText, idleText) {
        const original = btn.textContent;
        btn.disabled = true;
        btn.style.backgroundColor = "#888888";
        btn.style.color = "#0a0a0a";
        btn.textContent = `INSTALLING ${pkgs.length} PACKAGE${pkgs.length === 1 ? "" : "S"}...`;

        const r = await sh(`pkexec pacman -S --noconfirm --needed ${pkgs.join(" ")}`);

        if (r.ok) {
            btn.textContent = doneText;
            btn.style.backgroundColor = "#C8FF00";
            btn.style.borderColor = "#C8FF00";
            btn.style.color = "#0a0a0a";
        } else {
            btn.textContent = "FAILED // RETRY";
            btn.title = "pacman failed. Check the network, or run the command in a terminal for detail.";
            btn.disabled = false;
            btn.style.backgroundColor = "#FF4444";
            btn.style.borderColor = "#FF4444";
            btn.style.color = "#FFFFFF";
            setTimeout(() => { btn.textContent = idleText || original; }, 4000);
        }
        return r.ok;
    }

    btnNvidia.addEventListener("click", () => installPackages(
        btnNvidia,
        ["nvidia-open-dkms", "nvidia-utils", "lib32-nvidia-utils", "egl-wayland"],
        "INSTALLED // REBOOT TO APPLY", "INSTALL / NVIDIA"));

    // --- 5. GAMING SUITE ------------------------------------------------------
    const gameCards = document.querySelectorAll(".check-card");

    gameCards.forEach(card => {
        card.addEventListener("click", () =>
            card.querySelector(".checkbox-indicator").classList.toggle("checked"));

        // Anything already installed starts unticked, so "deploy" only ever
        // means "install the things I do not have".
        (async () => {
            const state = card.querySelector("[data-state]");
            if (await hasPkg(card.dataset.pkg)) {
                state.textContent = "INSTALLED";
                state.style.color = "#C8FF00";
                card.querySelector(".checkbox-indicator").classList.remove("checked");
            } else {
                state.textContent = "AVAILABLE";
                state.style.color = "#888888";
            }
        })();
    });

    document.getElementById("btn-deploy-gaming").addEventListener("click", () => {
        const pkgs = [...gameCards]
            .filter(c => c.querySelector(".checkbox-indicator").classList.contains("checked"))
            .map(c => c.dataset.pkg);

        if (pkgs.length === 0) {
            alert("Nothing selected. Tick a component that is not already installed.");
            return;
        }
        installPackages(document.getElementById("btn-deploy-gaming"), pkgs,
            "DEPLOYED // GAMING READY", "DEPLOY / SELECTED GAMES");
    });

    // --- 6. DEVELOPER SUITE ---------------------------------------------------
    const btnVsCode = document.getElementById("btn-install-vscode");
    const stateVsCode = document.getElementById("state-vscode");

    (async () => {
        if (await hasPkg("code")) {
            stateVsCode.textContent = "INSTALLED";
            stateVsCode.style.color = "#C8FF00";
            btnVsCode.textContent = "OPEN / VS CODE";
            btnVsCode.addEventListener("click", () => sh("setsid code >/dev/null 2>&1 &"));
        } else {
            stateVsCode.textContent = "NOT INSTALLED";
            stateVsCode.style.color = "#888888";
            btnVsCode.addEventListener("click", () =>
                installPackages(btnVsCode, ["code"], "INSTALLED // CODE READY", "INSTALL / VS CODE"));
        }
    })();

    const btnDocker = document.getElementById("btn-enable-docker");
    const stateDocker = document.getElementById("state-docker");

    async function refreshDocker() {
        if (!await hasPkg("docker")) {
            stateDocker.textContent = "NOT INSTALLED";
            stateDocker.style.color = "#888888";
            btnDocker.textContent = "INSTALL / DOCKER";
            return "absent";
        }
        const st = await unitState("docker.service");
        stateDocker.textContent = st.active ? "RUNNING" : (st.enabled ? "ENABLED" : "INSTALLED / STOPPED");
        stateDocker.style.color = st.active ? "#C8FF00" : "#888888";
        btnDocker.textContent = st.active ? "DOCKER ACTIVE" : "ENABLE / DOCKER";
        btnDocker.disabled = st.active;
        return st.active ? "active" : "inactive";
    }
    refreshDocker();

    btnDocker.addEventListener("click", async () => {
        if (!await hasPkg("docker")) {
            if (await installPackages(btnDocker, ["docker", "docker-compose"],
                                      "INSTALLED // ENABLE NEXT", "INSTALL / DOCKER")) {
                btnDocker.disabled = false;
                refreshDocker();
            }
            return;
        }
        btnDocker.disabled = true;
        btnDocker.textContent = "STARTING DAEMON...";
        const r = await sh("pkexec systemctl enable --now docker.service");
        if (!r.ok) {
            btnDocker.textContent = "ERROR // RETRY DOCKER";
            btnDocker.disabled = false;
            btnDocker.style.backgroundColor = "#FF4444";
            btnDocker.style.borderColor = "#FF4444";
            btnDocker.style.color = "#FFFFFF";
            return;
        }
        btnDocker.style.backgroundColor = "#C8FF00";
        btnDocker.style.borderColor = "#C8FF00";
        btnDocker.style.color = "#0a0a0a";
        refreshDocker();
    });

    // --- 7. SYSTEM TWEAKS: probe, never assert --------------------------------
    document.querySelectorAll(".tweak-item[data-unit]").forEach(item => {
        (async () => {
            const badge = item.querySelector("[data-state]");
            const st = await unitState(item.dataset.unit);
            if (st.active)       setBadge(badge, "ACTIVE", "on");
            else if (st.enabled) setBadge(badge, "ENABLED // NEXT BOOT", "on");
            else if (st.present) setBadge(badge, "INSTALLED // DISABLED", "off");
            else                 setBadge(badge, "NOT INSTALLED", "off");
        })();
    });
});
