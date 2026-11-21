Unicode true
!include "MUI2.nsh"
!include "WinVer.nsh"
!include "FileFunc.nsh"
Var ExtractOnly
!include "x64.nsh"

!define PRODUCT "samaya-desktop"
!define VERSION "0.3.6"
!ifndef UNINSTALL_KEY
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\SamayaDesktop"
!endif
!ifndef SHORTCUT_GROUP
!define SHORTCUT_GROUP "Samaya Desktop"
!endif

Name "Samaya Desktop"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\${PRODUCT}"
InstallDirRegKey HKCU "${UNINSTALL_KEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUninstDetails show
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${PRODUCT}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "Samaya Desktop Setup"
VIAddVersionKey "LegalCopyright" "Samaya Desktop"

!define MUI_ICON "..\assets\samaya.ico"
!define MUI_UNICON "..\assets\samaya.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PRODUCT}.exe"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

Function .onInit
    ${IfNot} ${RunningX64}
        MessageBox MB_ICONSTOP "Samaya Desktop requires 64-bit Windows."
        SetErrorLevel 1
        Quit
    ${EndIf}
    ${IfNot} ${AtLeastBuild} 17763
        MessageBox MB_ICONSTOP "Samaya Desktop requires Windows 10 version 1809 or later."
        SetErrorLevel 1
        Quit
    ${EndIf}
    SetShellVarContext current
    ${GetParameters} $0
    ClearErrors
    ${GetOptions} $0 "/EXTRACT" $1
    ${IfNot} ${Errors}
        StrCpy $ExtractOnly 1
    ${EndIf}
FunctionEnd

Section "Samaya Desktop"
    ${If} $ExtractOnly == 1
        IfFileExists "$INSTDIR\*.*" 0 emptyTarget
        SetErrorLevel 3
        Abort
        emptyTarget:
    ${EndIf}
    SetOutPath "$INSTDIR"
    File /r "${STAGE}\*.*"
    ${If} $ExtractOnly == 1
        Return
    ${EndIf}
    ReadRegStr $0 HKCU "${UNINSTALL_KEY}" "DisplayVersion"
    ReadRegStr $1 HKCU "${UNINSTALL_KEY}" "InstallLocation"
    ${If} $0 == "0.2.0"
    ${AndIf} $1 == "$INSTDIR"
        ExecWait '"$INSTDIR\${PRODUCT}.exe" --clean-legacy' $2
        ${If} $2 != 0
            MessageBox MB_OK|MB_ICONEXCLAMATION "Close Samaya Desktop 0.2.0 and retry the upgrade." /SD IDOK
            SetErrorLevel 2
            Abort
        ${EndIf}
    ${EndIf}
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    CreateDirectory "$SMPROGRAMS\${SHORTCUT_GROUP}"
    CreateShortcut "$SMPROGRAMS\${SHORTCUT_GROUP}\Samaya.lnk" "$INSTDIR\${PRODUCT}.exe"
    CreateShortcut "$SMPROGRAMS\${SHORTCUT_GROUP}\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "Samaya Desktop"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${PRODUCT}.exe,0"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
    WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
    SetShellVarContext current
    !include "${UNINSTALL_FILES}"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
    ReadRegStr $0 HKCU "${UNINSTALL_KEY}" "InstallLocation"
    ${If} $0 != "$INSTDIR"
        Return
    ${EndIf}
    Delete "$SMPROGRAMS\${SHORTCUT_GROUP}\Samaya.lnk"
    Delete "$SMPROGRAMS\${SHORTCUT_GROUP}\Uninstall.lnk"
    RMDir "$SMPROGRAMS\${SHORTCUT_GROUP}"
    DeleteRegKey HKCU "${UNINSTALL_KEY}"
SectionEnd
