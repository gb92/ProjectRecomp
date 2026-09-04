#ifndef SourceDir
  #error SourceDir must point to the staged application files.
#endif
#ifndef RepoDir
  #error RepoDir must point to the ProjectRecomp repository.
#endif
#ifndef OutputDir
  #define OutputDir AddBackslash(SourcePath) + "..\..\dist"
#endif
#ifndef AppVersion
  #define AppVersion "0.1.0-alpha.1"
#endif

[Setup]
AppId={{CB99BE6F-0204-4D50-9A97-D1DCC428B776}
AppName=ProjectRecomp
AppVersion={#AppVersion}
VersionInfoVersion=0.1.0.0
AppPublisher=ProjectRecomp contributors
AppPublisherURL=https://github.com/gb92/ProjectRecomp
AppSupportURL=https://github.com/gb92/ProjectRecomp/issues
DefaultDirName={autopf}\ProjectRecomp
DefaultGroupName=ProjectRecomp
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline
OutputDir={#OutputDir}
OutputBaseFilename=ProjectRecomp-{#AppVersion}-Windows-x64-Setup
SetupIconFile={#RepoDir}\icons\projectrecomp.ico
UninstallDisplayIcon={app}\thp8.exe
LicenseFile={#RepoDir}\LICENSE
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern dynamic
SetupLogging=yes
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; \
    GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#RepoDir}\scripts\import_game_windows.ps1"; \
    Flags: dontcopy noencryption
Source: "{#SourceDir}\*"; DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\ProjectRecomp"; Filename: "{app}\thp8.exe"
Name: "{autodesktop}\ProjectRecomp"; Filename: "{app}\thp8.exe"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\thp8.exe"; Description: "Launch ProjectRecomp"; \
    Flags: nowait postinstall skipifsilent

[Code]
var
  ExistingGamePage: TInputOptionWizardPage;
  GameSourcePage: TInputDirWizardPage;
  GameDestinationPage: TInputDirWizardPage;
  ImportProgressPage: TOutputProgressWizardPage;
  ImporterMessage: String;
  InitialGameDestination: String;

function GameDestination: String;
begin
  if GameDestinationPage <> nil then
    Result := GameDestinationPage.Values[0]
  else if InitialGameDestination <> '' then
    Result := InitialGameDestination
  else
    Result := ExpandConstant('{%USERPROFILE}\Games\ProjectRecomp');
end;

function HasManagedGameImport: Boolean;
begin
  Result :=
    FileExists(AddBackslash(GameDestination) + 'default.xex') and
    FileExists(AddBackslash(GameDestination) + '.projectrecomp-game');
end;

function ShouldImportGame: Boolean;
begin
  Result :=
    (ExistingGamePage = nil) or
    ExistingGamePage.Values[1];
end;

procedure ImporterLog(
  const S: String;
  const Error, FirstLine: Boolean
);
var
  Percent: Integer;
begin
  Log(S);
  if Pos('PROGRESS:', S) = 1 then
  begin
    Percent := StrToIntDef(Copy(S, 10, MaxInt), 0);
    ImportProgressPage.SetProgress(Percent, 100);
  end
  else if Pos('ERROR:', S) = 1 then
    ImporterMessage := Copy(S, 7, MaxInt)
  else if Trim(S) <> '' then
    ImporterMessage := S;
end;

function RunImporter(const Mode: String): Boolean;
var
  Parameters: String;
  ResultCode: Integer;
begin
  ImporterMessage := '';
  Parameters :=
    '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
    AddQuotes(ExpandConstant('{tmp}\import_game_windows.ps1')) +
    ' -Mode ' + Mode +
    ' -Source ' + AddQuotes(GameSourcePage.Values[0]) +
    ' -Destination ' + AddQuotes(GameDestination);
  Result :=
    ExecAndLogOutput(
      ExpandConstant(
        '{sys}\WindowsPowerShell\v1.0\powershell.exe'
      ),
      Parameters,
      '',
      SW_SHOWNORMAL,
      ewWaitUntilTerminated,
      ResultCode,
      @ImporterLog
    ) and (ResultCode = 0);
  if (not Result) and (ImporterMessage = '') then
    ImporterMessage :=
      'The game importer failed with exit code ' + IntToStr(ResultCode) + '.';
end;

procedure InitializeWizard;
var
  PreviousPageId: Integer;
begin
  ExtractTemporaryFile('import_game_windows.ps1');
  InitialGameDestination := ExpandConstant('{param:GAMEDIR|}');
  if InitialGameDestination = '' then
    InitialGameDestination := GetPreviousData(
      'GameDestination',
      ExpandConstant('{%USERPROFILE}\Games\ProjectRecomp')
    );
  PreviousPageId := wpSelectDir;

  if HasManagedGameImport then
  begin
    ExistingGamePage := CreateInputOptionPage(
      PreviousPageId,
      'Game files',
      'Choose how Setup should handle the existing game import.',
      'ProjectRecomp found previously imported game files.',
      True,
      False
    );
    ExistingGamePage.Add('Keep the existing imported game files');
    ExistingGamePage.Add('Replace them from an extracted disc folder');
    ExistingGamePage.SelectedValueIndex := 0;
    PreviousPageId := ExistingGamePage.ID;
  end;

  GameSourcePage := CreateInputDirPage(
    PreviousPageId,
    'Import Tony Hawk''s Project 8',
    'Select your extracted Xbox 360 disc folder.',
    'Setup validates the unmodified base default.xex before copying your ' +
      'legally acquired game files. Title updates are not supported.',
    False,
    ''
  );
  GameSourcePage.Add('');
  GameSourcePage.Values[0] := ExpandConstant('{param:GAMESOURCE|}');
  if
    (ExistingGamePage <> nil) and
    (GameSourcePage.Values[0] <> '')
  then
    ExistingGamePage.SelectedValueIndex := 1;

  GameDestinationPage := CreateInputDirPage(
    GameSourcePage.ID,
    'Choose game data location',
    'Select where ProjectRecomp should store your imported game files.',
    'The extracted game is approximately 5 GB. You may choose another drive.',
    False,
    ''
  );
  GameDestinationPage.Add('');
  GameDestinationPage.Values[0] := InitialGameDestination;

  ImportProgressPage := CreateOutputProgressPage(
    'Importing game files',
    'Copying your extracted disc to per-user storage...'
  );
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result :=
    ((PageID = GameSourcePage.ID) or
     (PageID = GameDestinationPage.ID)) and
    (ExistingGamePage <> nil) and
    ExistingGamePage.Values[0];
end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
begin
  SetPreviousData(
    PreviousDataKey,
    'GameDestination',
    GameDestination
  );
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = GameSourcePage.ID) and ShouldImportGame then
  begin
    WizardForm.NextButton.Enabled := False;
    WizardForm.Cursor := crHourGlass;
    try
      Result := RunImporter('Validate');
      if (not Result) and (not WizardSilent) then
        MsgBox(ImporterMessage, mbError, MB_OK);
    finally
      WizardForm.Cursor := crDefault;
      WizardForm.NextButton.Enabled := True;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not ShouldImportGame then
    exit;

  ImportProgressPage.SetProgress(0, 100);
  ImportProgressPage.Show;
  try
    if not RunImporter('Install') then
      Result := ImporterMessage;
  finally
    ImportProgressPage.Hide;
  end;
end;
