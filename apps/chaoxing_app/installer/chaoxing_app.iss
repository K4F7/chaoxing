#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\build"
#endif

[Setup]
AppId={{937AA486-7EE4-4D24-AFB5-D59EA5F1074B}
AppName=学习通待办
AppVersion={#AppVersion}
AppPublisher=K4F7
AppPublisherURL=https://github.com/K4F7/chaoxinghelper
DefaultDirName={localappdata}\Programs\ChaoxingTodo
DefaultGroupName=学习通待办
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=chaoxing-app-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\chaoxing_app.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\学习通待办"; Filename: "{app}\chaoxing_app.exe"; WorkingDir: "{app}"

[Code]
function WebView2Installed: Boolean;
var
  Version: String;
begin
  Result :=
    RegQueryStringValue(HKLM64,
      'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F1E7E2F8-A4E8-4A4A-9B9A-8F6F8C5A0D54}',
      'pv', Version) or
    RegQueryStringValue(HKLM32,
      'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F1E7E2F8-A4E8-4A4A-9B9A-8F6F8C5A0D54}',
      'pv', Version) or
    RegQueryStringValue(HKCU,
      'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F1E7E2F8-A4E8-4A4A-9B9A-8F6F8C5A0D54}',
      'pv', Version);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RegDeleteValue(HKCU,
      'Software\Microsoft\Windows\CurrentVersion\Run', 'ChaoxingTodo');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ErrorCode: Integer;
begin
  if (CurStep = ssPostInstall) and (not WebView2Installed) and
     (not WizardSilent) then begin
    if MsgBox(
      '内置登录需要 Microsoft Edge WebView2 Runtime。现在打开官方下载页吗？',
      mbConfirmation, MB_YESNO) = IDYES then
      ShellExec('open', 'https://go.microsoft.com/fwlink/p/?LinkId=2124703',
        '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;
end;
