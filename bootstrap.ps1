<#
.SYNOPSIS
    Bootstrap loader for debloater-v2.ps1. Safe to run via:
        irm https://raw.githubusercontent.com/<you>/<repo>/main/bootstrap.ps1 | iex

    Why this exists: debloater-v2.ps1 relies on $PSCommandPath to locate and
    persist a copy of itself for the Task Scheduler resume mechanism. That's
    null when the script body is piped through iex directly, so the main
    script can't self-host. This loader downloads it to a real file first,
    at the exact path Register-ResumeTask already expects, then launches it
    with -File so $PSCommandPath is populated normally.
#>

$ErrorActionPreference = 'Stop'

# Must match $Script:PersistPath inside debloater-v2.ps1 exactly.
# Writing straight to the final location means Initialize-PersistentCopy's
# internal copy check ($currentPath -ne $Script:PersistPath) is a no-op —
# no redundant copy, no changes needed to the main script.
$PersistDir   = Join-Path $Env:ProgramData 'Debloater'
$PersistPath  = Join-Path $PersistDir 'debloater.ps1'

$RawUrl       = 'https://raw.githubusercontent.com/ModernTTY/debloater/refs/heads/main/debloater.ps1'
$BootstrapUrl = 'https://raw.githubusercontent.com/ModernTTY/debloater/refs/heads/main/bootstrap.ps1'

$principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # debloater-v2.ps1 has #Requires -RunAsAdministrator, which just hard-stops
    # with no explanation if launched unelevated. Relaunch elevated instead.
    Write-Host "Not running as Administrator — relaunching elevated..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
        "irm '$BootstrapUrl' | iex"
    )
}
else {
    New-Item -Path $PersistDir -ItemType Directory -Force | Out-Null

    Write-Host "Downloading debloater script to $PersistPath ..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $RawUrl -OutFile $PersistPath -UseBasicParsing

    Write-Host "Launching Stage 1..." -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PersistPath -Stage 1
}