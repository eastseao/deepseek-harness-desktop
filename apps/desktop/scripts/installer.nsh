!include "LogicLib.nsh"
!define INSTALLER_SOURCE_DIR "${__FILEDIR__}\..\installer"
!define /ifndef INSTALLER_BUILD_DIR "${__FILEDIR__}\..\.desktop-build\targets\win-x64\installer-ui"

!ifndef BUILD_UNINSTALLER
  ManifestDPIAware true
  !define MUI_CUSTOMFUNCTION_GUIINIT InstallerGuiInit
!endif

; "current" installs only for the running user; "all" installs for every user
; (the welcome page re-launches elevated when all-users is chosen).
!ifndef BUILD_UNINSTALLER
Var InstallerMode
!endif

!macro customHeader
  !define /ifndef INSTALLER_STRINGS_FILE "${INSTALLER_SOURCE_DIR}\strings.nsh"
  !include "${INSTALLER_STRINGS_FILE}"
  !ifndef BUILD_UNINSTALLER
    !include "${INSTALLER_SOURCE_DIR}\theme.nsh"
    !include "${INSTALLER_SOURCE_DIR}\pages.nsh"
    !include "${INSTALLER_SOURCE_DIR}\lifecycle.nsh"
  !endif
!macroend

!macro customInit
  StrCpy $InstallerMode "current"
  ${GetParameters} $0
  ${GetOptions} $0 "/allusers" $1
  ${If} ${Errors}
    ${GetOptions} $0 "/ALLUSERS" $1
  ${EndIf}
  ${IfNot} ${Errors}
    StrCpy $InstallerMode "all"
  ${EndIf}
  StrCpy $InstallerPath $INSTDIR
  StrCpy $InstallerTheme "auto"
  ${GetParameters} $0
  ${GetOptions} $0 "/THEME=" $1
  ${IfNot} ${Errors}
    ${If} $1 == "light"
    ${OrIf} $1 == "dark"
    ${OrIf} $1 == "auto"
      StrCpy $InstallerTheme $1
    ${Else}
      MessageBox MB_OK|MB_ICONEXCLAMATION "$(INSTALLER_THEME_ERROR)" /SD IDOK
      SetErrorLevel 2
      Quit
    ${EndIf}
  ${EndIf}
  Call InstallerResolveTheme
  InitPluginsDir
  File "/oname=$PLUGINSDIR\brand.bmp" "${INSTALLER_BUILD_DIR}\brand.bmp"
  File "/oname=$PLUGINSDIR\brand-2x.bmp" "${INSTALLER_BUILD_DIR}\brand-2x.bmp"
  File "/oname=$PLUGINSDIR\brand-dark.bmp" "${INSTALLER_BUILD_DIR}\brand-dark.bmp"
  File "/oname=$PLUGINSDIR\brand-dark-2x.bmp" "${INSTALLER_BUILD_DIR}\brand-dark-2x.bmp"
  File "/oname=$PLUGINSDIR\window-frame.dll" "${INSTALLER_BUILD_DIR}\window-frame.dll"
  ${If} ${Silent}
    ${If} $InstallerMode != "all"
      ; Silent all-users installs elevate inside the install section.
      Call InstallerPreflight
      ${If} $InstallerError != ""
        SetErrorLevel 2
        Quit
      ${EndIf}
    ${EndIf}
  ${EndIf}
!macroend

!macro customInstallMode
  ; The install mode is chosen on the custom welcome page (installer) or
  ; restored from the registry (uninstaller); keep the stock mode-selection
  ; page skipped and mirror the active mode into electron-builder's state.
  !ifndef BUILD_UNINSTALLER
    ${If} $InstallerMode == "all"
      StrCpy $hasPerMachineInstallation 1
      StrCpy $hasPerUserInstallation 0
    ${Else}
      StrCpy $installMode CurrentUser
      SetShellVarContext current
      StrCpy $hasPerMachineInstallation 0
      StrCpy $hasPerUserInstallation 1
    ${EndIf}
    Abort
  !endif
!macroend

!macro customWelcomePage
  Page custom InstallerWelcome InstallerWelcomeLeave
!macroend

!macro customPageAfterChangeDir
  !define MUI_PAGE_CUSTOMFUNCTION_PRE InstallerBeforeInstall
  !define MUI_PAGE_CUSTOMFUNCTION_SHOW InstallerProgressShow
!macroend

!macro customFinishPage
  Page custom InstallerFinish InstallerFinishLeave
!macroend

; Installation work publishes stage changes without disturbing the NSIS caller.
!macro InstallerPublishStage Stage
  ; Extraction owns the stack and error flag across these callbacks.
  Push $0
  StrCpy $0 0
  ${If} ${Errors}
    StrCpy $0 1
  ${EndIf}
  System::Store /NOUNLOAD "S"
  System::Call /NOUNLOAD 'user32::SetPropW(p $HWNDPARENT, w "HarnessInstaller.Stage", p ${Stage})'
  System::Store "L"
  ${If} $0 == 1
    SetErrors
  ${Else}
    ClearErrors
  ${EndIf}
  Pop $0
!macroend

!macro customInstallerExtract Archive
  !insertmacro InstallerPublishStage 1
  System::Store /NOUNLOAD "S"
  System::Call /NOUNLOAD '$PLUGINSDIR\window-frame.dll::InstallerExtract(p $HWNDPARENT, w "$PLUGINSDIR\dsh-7za.exe", w "${Archive}", w "$INSTDIR", w "$PLUGINSDIR\extract.log") i.s ?c'
  System::Store "L"
  Pop $R0
  StrCpy $R1 "$R0"
  ${If} $R0 != 0
    Push $0
    FileOpen $0 "$PLUGINSDIR\extract.log" r
    ${IfNot} ${Errors}
      FileRead $0 $R1
      FileClose $0
    ${EndIf}
    Pop $0
  ${EndIf}
!macroend

!macro customCheckAppRunning
  !ifdef BUILD_UNINSTALLER
    InitPluginsDir
    File "/oname=$PLUGINSDIR\window-frame.dll" "${INSTALLER_BUILD_DIR}\window-frame.dll"
  !endif
  System::Call '$PLUGINSDIR\window-frame.dll::InstallerFindProcess(w "$INSTDIR\${APP_EXECUTABLE_FILENAME}") i.R0 ?c'
  ${If} $R0 == 0
    ${If} ${isUpdated}
      StrCpy $R1 0
      ${DoWhile} $R0 == 0
        Sleep 250
        System::Call '$PLUGINSDIR\window-frame.dll::InstallerFindProcess(w "$INSTDIR\${APP_EXECUTABLE_FILENAME}") i.R0 ?c'
        IntOp $R1 $R1 + 1
        ${If} $R1 >= 40
          ${ExitDo}
        ${EndIf}
      ${Loop}
    ${EndIf}
    ${If} $R0 == 0
      MessageBox MB_OK|MB_ICONINFORMATION "$(INSTALLER_RUNNING)" /SD IDOK
      SetErrorLevel 2
      Quit
    ${EndIf}
  ${EndIf}
  ${If} $R0 < 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(INSTALLER_UI_ERROR)" /SD IDOK
    SetErrorLevel 2
    Quit
  ${EndIf}
!macroend

!ifndef BUILD_UNINSTALLER
  !include "${__FILEDIR__}\installer-directories.nsh"
!endif

!macro customInstall
  Push $0
  StrCpy $0 0
  ${If} ${Errors}
    StrCpy $0 1
  ${EndIf}
  !insertmacro InstallerPublishStage 4
  !insertmacro dshFinishDirectories
  ${If} $0 == 1
    SetErrors
  ${Else}
    ClearErrors
  ${EndIf}
  Pop $0
!macroend
