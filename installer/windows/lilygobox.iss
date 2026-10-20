#ifndef AppVersion
  #error AppVersion must be supplied by the build script.
#endif
#ifndef ReleaseDir
  #define ReleaseDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{ADCE099E-0B2F-43CE-B6DD-C2688E9C437D}
AppName=LilygoBox
AppVersion={#AppVersion}
AppPublisher=LILYGO
DefaultDirName={localappdata}\Programs\LilygoBox
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=LilygoBox-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
AppMutex=Local\LilygoBox.Main.5D67190D-7E46-4EA8-A99B-9C2E25668A0D
CloseApplications=no
RestartApplications=no
UninstallDisplayName=LilygoBox
UninstallDisplayIcon={app}\lilygobox-windows-x64.exe
WizardStyle=modern
ShowLanguageDialog=yes
LicenseFile=..\..\build\installer\LICENSE.rtf

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[CustomMessages]
english.UninstallOptions=LilygoBox Uninstall
english.UninstallDataDescription=By default, only LilygoBox is uninstalled. Your settings, account sign-in, device pairing records and firmware cache are kept for reinstallation.
english.RemoveUserData=Also delete LilygoBox user data
english.RemoveUserDataWarning=This permanently removes settings, locally saved GitHub sign-in information, device pairing records and firmware cache. You will need to sign in and pair devices again after reinstalling. Your devices will not be reset.
english.ContinueUninstall=Uninstall
english.UninstallEntryFailed=Unable to configure the uninstall entry. Please reinstall LilygoBox before uninstalling.
english.ExitBeforeUninstall=Please fully exit LilygoBox, including its tray process, before uninstalling.
english.ExitBeforeInstall=Please fully exit LilygoBox, including its tray process, before installing. If a device firmware update is in progress, wait for it to finish first, then exit the application and retry.
english.UserDataDeleteFailed=Some LilygoBox user data could not be deleted. Close any programs using these folders, then remove them manually:
chinesesimplified.UninstallOptions=LilygoBox 卸载
chinesesimplified.UninstallDataDescription=默认仅卸载 LilygoBox，保留设置、账号登录信息、设备配对记录和固件缓存，方便重新安装。
chinesesimplified.RemoveUserData=同时删除 LilygoBox 用户数据
chinesesimplified.RemoveUserDataWarning=将永久删除设置、本机保存的 GitHub 登录信息、设备配对记录和固件缓存。重新安装后需要重新登录和配对，设备本身不会被重置。
chinesesimplified.ContinueUninstall=卸载
chinesesimplified.UninstallEntryFailed=无法配置卸载入口，请重新安装 LilygoBox 后再卸载。
chinesesimplified.ExitBeforeUninstall=请先完全退出 LilygoBox（包括托盘进程），再进行卸载。
chinesesimplified.ExitBeforeInstall=请先完全退出 LilygoBox（包括托盘进程），再进行安装。如果正在更新设备固件，请等待更新结束后再退出应用并重试。
chinesesimplified.UserDataDeleteFailed=部分 LilygoBox 用户数据未能删除。请关闭占用这些目录的程序后手动清理：

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\LilygoBox"; Filename: "{app}\lilygobox-windows-x64.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\LilygoBox"; Filename: "{app}\lilygobox-windows-x64.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\lilygobox-windows-x64.exe"; Description: "{cm:LaunchProgram,LilygoBox}"; Flags: nowait postinstall skipifsilent

[Code]
var
  RemoveUserData: Boolean;

procedure CurStepChanged(CurStep: TSetupStep);
var
  UninstallKey: String;
begin
  if CurStep = ssDone then
  begin
    UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{ADCE099E-0B2F-43CE-B6DD-C2688E9C437D}_is1';
    // 普通入口保留自定义确认和进度窗口，仅跳过 Inno Setup 的重复确认。
    if not RegWriteStringValue(HKCU, UninstallKey, 'UninstallString',
      '"' + ExpandConstant('{uninstallexe}') + '" /SILENT /LILYGOBOXINTERACTIVE') then
      MsgBox(CustomMessage('UninstallEntryFailed'), mbError, MB_OK);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if CheckForMutexes('Local\LilygoBox.Main.5D67190D-7E46-4EA8-A99B-9C2E25668A0D') then
    Result := CustomMessage('ExitBeforeInstall');
end;

function InitializeUninstall(): Boolean;
var
  OptionsForm: TSetupForm;
  DescriptionLabel, WarningLabel: TNewStaticText;
  RemoveDataCheck: TNewCheckBox;
  ContinueButton, CancelButton: TNewButton;
  InteractiveUninstall: Boolean;
  ParameterIndex: Integer;
begin
  Result := False;
  RemoveUserData := False;
  InteractiveUninstall := not UninstallSilent;
  for ParameterIndex := 1 to ParamCount do
    if CompareText(ParamStr(ParameterIndex), '/LILYGOBOXINTERACTIVE') = 0 then
      InteractiveUninstall := True;
  if CheckForMutexes('Local\LilygoBox.Main.5D67190D-7E46-4EA8-A99B-9C2E25668A0D') then
  begin
    if InteractiveUninstall then
      MsgBox(CustomMessage('ExitBeforeUninstall'), mbInformation, MB_OK);
    Exit;
  end;
  if not InteractiveUninstall then
  begin
    Result := True;
    Exit;
  end;

  OptionsForm := CreateCustomForm(ScaleX(480), ScaleY(250), False, True);
  try
    OptionsForm.Caption := CustomMessage('UninstallOptions');
    OptionsForm.ClientWidth := ScaleX(480);
    OptionsForm.ClientHeight := ScaleY(250);
    DescriptionLabel := TNewStaticText.Create(OptionsForm);
    DescriptionLabel.Parent := OptionsForm;
    DescriptionLabel.SetBounds(ScaleX(20), ScaleY(20), ScaleX(440), ScaleY(64));
    DescriptionLabel.AutoSize := False;
    DescriptionLabel.WordWrap := True;
    DescriptionLabel.Caption := CustomMessage('UninstallDataDescription');
    RemoveDataCheck := TNewCheckBox.Create(OptionsForm);
    RemoveDataCheck.Parent := OptionsForm;
    RemoveDataCheck.SetBounds(ScaleX(20), ScaleY(96), ScaleX(440), ScaleY(28));
    RemoveDataCheck.Caption := CustomMessage('RemoveUserData');
    RemoveDataCheck.Checked := False;
    WarningLabel := TNewStaticText.Create(OptionsForm);
    WarningLabel.Parent := OptionsForm;
    WarningLabel.SetBounds(ScaleX(20), ScaleY(136), ScaleX(440), ScaleY(60));
    WarningLabel.AutoSize := False;
    WarningLabel.WordWrap := True;
    WarningLabel.Caption := CustomMessage('RemoveUserDataWarning');
    ContinueButton := TNewButton.Create(OptionsForm);
    ContinueButton.Parent := OptionsForm;
    ContinueButton.SetBounds(ScaleX(284), ScaleY(210), ScaleX(84), ScaleY(26));
    ContinueButton.Caption := CustomMessage('ContinueUninstall');
    ContinueButton.ModalResult := mrOk;
    ContinueButton.Default := True;
    CancelButton := TNewButton.Create(OptionsForm);
    CancelButton.Parent := OptionsForm;
    CancelButton.SetBounds(ScaleX(376), ScaleY(210), ScaleX(84), ScaleY(26));
    CancelButton.Caption := SetupMessage(msgButtonCancel);
    CancelButton.ModalResult := mrCancel;
    CancelButton.Cancel := True;
    OptionsForm.ActiveControl := ContinueButton;
    Result := OptionsForm.ShowModal = mrOk;
    if Result then
      RemoveUserData := RemoveDataCheck.Checked;
  finally
    OptionsForm.Free;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  RoamingData, LocalData, FailedPaths: String;
begin
  if (CurUninstallStep = usPostUninstall) and RemoveUserData then
  begin
    RoamingData := ExpandConstant('{userappdata}\LILYGO\LilygoBox');
    LocalData := ExpandConstant('{localappdata}\LILYGO\lilygobox');
    FailedPaths := '';
    if DirExists(RoamingData) then
      if not DelTree(RoamingData, True, True, True) then
        FailedPaths := RoamingData;
    if DirExists(LocalData) then
      if not DelTree(LocalData, True, True, True) then
        FailedPaths := FailedPaths + #13#10 + LocalData;
    if FailedPaths <> '' then
      MsgBox(CustomMessage('UserDataDeleteFailed') + #13#10 + FailedPaths, mbError, MB_OK);
  end;
end;
