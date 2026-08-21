export const INSTALL_DIR_FRAGMENT = "Programs\\ChaoxingTodo";
export const EXECUTABLE_NAME = "chaoxing_windows.exe";
export const AUTOSTART_VALUE_NAME = "ChaoxingTodo";
export const TASKKILL_IMAGE = "chaoxing_windows.exe";

export type InstallerScript = {
  source: string;
};

export function installerLifecycleInvariants(script: string): {
  terminateOnUninstall: boolean;
  terminateOnUpgrade: boolean;
  autostartCleanup: boolean;
  perUserInstall: boolean;
  startMenuShortcut: boolean;
  webView2Hint: boolean;
} {
  return {
    terminateOnUninstall:
      script.includes("InitializeUninstall") &&
      script.includes("taskkill.exe") &&
      script.includes(TASKKILL_IMAGE),
    terminateOnUpgrade:
      script.includes("PrepareToInstall") && script.includes("taskkill.exe"),
    autostartCleanup:
      script.includes("CurUninstallStepChanged") &&
      script.includes("Software\\Microsoft\\Windows\\CurrentVersion\\Run") &&
      script.includes(AUTOSTART_VALUE_NAME),
    perUserInstall:
      script.includes("PrivilegesRequired=lowest") &&
      script.includes("{localappdata}"),
    startMenuShortcut: script.includes("{group}\\学习通待办"),
    webView2Hint:
      script.includes("WebView2") || script.includes("webview2"),
  };
}

export function silentInstallArgs(): string[] {
  return ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART"];
}

export function expectedAutostartCommand(installedExecutable: string): string {
  return `"${installedExecutable}" --hidden`;
}
