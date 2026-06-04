#Requires -Version 5
# Install the built .wsl image (needs WSL 2.4.4+).
[CmdletBinding()]
param(
    [string]$WslFile = "$PSScriptRoot\..\out\t2sde.wsl",
    [string]$Name
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $WslFile)) { throw "not found: $WslFile (build it first)" }
$WslFile = (Resolve-Path $WslFile).Path

if ($Name) { wsl.exe --install --from-file $WslFile --name $Name }
else        { wsl.exe --install --from-file $WslFile }
