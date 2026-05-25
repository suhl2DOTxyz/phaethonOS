const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');

function createWindow() {
  const mainWindow = new BrowserWindow({
    width: 1080,
    height: 720,
    resizable: false,
    frame: true, // ZZZ themed window frame using standard system window rules
    title: "PHAETHON OS // WELCOME DASHBOARD",
    icon: path.join(__dirname, 'phaethon-logo.png'),
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      enableRemoteModule: true
    }
  });

  // Load the main index.html
  mainWindow.loadFile('index.html');

  // Hide the standard menu bar
  mainWindow.setMenuBarVisibility(false);
}

app.whenReady().then(() => {
  createWindow();

  app.on('activate', function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', function () {
  if (process.platform !== 'darwin') app.quit();
});
