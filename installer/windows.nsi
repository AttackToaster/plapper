; plapper Windows installer. Build from repo root:
;   makensis /DBUNDLE=app\build\windows\x64\runner\Release installer\windows.nsi
!include "MUI2.nsh"

Name "plapper"
OutFile "plapper-setup-windows-x64.exe"
InstallDir "$PROGRAMFILES64\plapper"
RequestExecutionLevel admin
Unicode true

!define MUI_ICON "..\app\windows\runner\resources\app_icon.ico"

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${BUNDLE}\*"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  CreateDirectory "$SMPROGRAMS\plapper"
  CreateShortcut "$SMPROGRAMS\plapper\plapper.lnk" "$INSTDIR\plapper.exe"
  CreateShortcut "$DESKTOP\plapper.lnk" "$INSTDIR\plapper.exe"

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\plapper" \
    "DisplayName" "plapper"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\plapper" \
    "DisplayIcon" "$INSTDIR\plapper.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\plapper" \
    "Publisher" "AttackToaster"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\plapper" \
    "UninstallString" '"$INSTDIR\uninstall.exe"'
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\plapper\plapper.lnk"
  RMDir "$SMPROGRAMS\plapper"
  Delete "$DESKTOP\plapper.lnk"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\plapper"
SectionEnd
