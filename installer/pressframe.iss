; PressFrame Windows installer (Inno Setup 6, free: https://jrsoftware.org/isinfo.php)
;
; Build steps:
;   1. flutter build windows --release
;   2. Open this file in Inno Setup and press Compile (or run: ISCC installer\pressframe.iss)
; The installer lands in build\installer\PressFrame-Setup-1.0.0.exe

[Setup]
AppId={{6B0F3C1E-7A54-4E0B-9D2A-5F1C2E7A9B01}
AppName=PressFrame
AppVersion=1.0.0
AppPublisher=dewdew-del
DefaultDirName={autopf}\PressFrame
DefaultGroupName=PressFrame
DisableProgramGroupPage=yes
; Installs for the current user, so no administrator password is needed on school laptops.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=PressFrame-Setup-1.0.0
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\pressframe.exe
UninstallDisplayName=PressFrame

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
; Flutter apps need the Visual C++ runtime. Shipping these three files next to the app means
; it also starts on a PC that never had Visual Studio or the VC++ redistributable installed.
; Sysnative, not System32: the Inno compiler is 32-bit, so Windows would hand it the 32-bit
; copies from System32. Sysnative is the real 64-bit folder.
Source: "C:\Windows\Sysnative\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Windows\Sysnative\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Windows\Sysnative\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\PressFrame"; Filename: "{app}\pressframe.exe"
Name: "{autodesktop}\PressFrame"; Filename: "{app}\pressframe.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\pressframe.exe"; Description: "Open PressFrame"; Flags: nowait postinstall skipifsilent
