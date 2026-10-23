[Setup]
AppName=ScreenPlayer installer temp probe
AppVersion=1.0
PrivilegesRequired=lowest
CreateAppDir=no
Uninstallable=no
CreateUninstallRegKey=no
DisableWelcomePage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
OutputBaseFilename=TempProbeSetup

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssDone then
    if not SaveStringToFile(ExpandConstant('{param:ProbeMarker}'), ExpandConstant('{tmp}'), False) then
      RaiseException('Cannot write probe marker');
end;
