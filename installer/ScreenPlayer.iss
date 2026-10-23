#ifndef AppVersion
  #define AppVersion "0.1.2"
#endif
#ifndef SourceDir
  #define SourceDir "..\dist\ScreenPlayer-Windows-x86_64"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

[Setup]
AppId={{B49EC39E-4789-4B04-A9A1-1BB1FD91C540}
AppName=ScreenPlayer
AppVersion={#AppVersion}
AppVerName=ScreenPlayer {#AppVersion}
AppPublisher=ScreenPlayer
DefaultDirName={localappdata}\Programs\ScreenPlayer
DefaultGroupName=ScreenPlayer
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=ScreenPlayer-Setup-{#AppVersion}
SetupIconFile=..\assets\app_icon.ico
UninstallDisplayIcon={app}\ScreenPlayer.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
MinVersion=10.0
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName=ScreenPlayer
VersionInfoDescription=ScreenPlayer 安装程序

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加选项："; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\ScreenPlayer"; Filename: "{app}\ScreenPlayer.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\ScreenPlayer"; Filename: "{app}\ScreenPlayer.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\ScreenPlayer.exe"; Description: "启动 ScreenPlayer"; Flags: nowait postinstall skipifsilent
