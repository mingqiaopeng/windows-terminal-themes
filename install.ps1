<#
.SYNOPSIS
    Install VS Code theme color schemes into Windows Terminal.

.DESCRIPTION
    Reads schemes.json from the same folder as this script and merges the
    schemes into Windows Terminal's settings.json. Existing schemes with the
    same name are replaced. A timestamped backup is created before writing.

.PARAMETER SettingsPath
    Path to Windows Terminal settings.json. Auto-detected when omitted.

.PARAMETER Uninstall
    Remove the schemes listed in schemes.json instead of installing them.

.PARAMETER DryRun
    Show what would change without writing to settings.json.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
    .\install.ps1 -Uninstall

.EXAMPLE
    .\install.ps1 -SettingsPath "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
#>
[CmdletBinding()]
param(
    [string]$SettingsPath,
    [switch]$Uninstall,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$schemesFile = Join-Path $PSScriptRoot 'schemes.json'
if (-not (Test-Path -LiteralPath $schemesFile)) {
    throw "schemes.json was not found next to install.ps1."
}

function Get-WindowsTerminalSettingsPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json'),
        (Join-Path $env:USERPROFILE 'scoop\persist\windows-terminal\settings.json')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

function Find-JsonStringEnd {
    param([string]$Text, [int]$Start)
    $i = $Start + 1
    while ($i -lt $Text.Length) {
        if ($Text[$i] -eq '\') {
            $i += 2
            continue
        }
        if ($Text[$i] -eq '"') {
            return $i
        }
        $i++
    }
    throw "Unterminated JSON string."
}

function Skip-JsonTrivia {
    param([string]$Text, [int]$Index)
    $i = $Index
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ([char]::IsWhiteSpace($c)) {
            $i++
            continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $Text.Length) {
            if ($Text[$i + 1] -eq '/') {
                $i += 2
                while ($i -lt $Text.Length -and $Text[$i] -ne "`n" -and $Text[$i] -ne "`r") {
                    $i++
                }
                continue
            }
            if ($Text[$i + 1] -eq '*') {
                $i += 2
                while ($i -lt $Text.Length -and -not ($Text[$i] -eq '*' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/')) {
                    $i++
                }
                $i += 2
                continue
            }
        }
        break
    }
    return $i
}

function Find-JsonArrayEnd {
    param([string]$Text, [int]$OpenIndex)
    $i = $OpenIndex
    $depth = 0
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ($c -eq '"') {
            $i = (Find-JsonStringEnd $Text $i) + 1
            continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $Text.Length) {
            if ($Text[$i + 1] -eq '/') {
                $i += 2
                while ($i -lt $Text.Length -and $Text[$i] -ne "`n" -and $Text[$i] -ne "`r") { $i++ }
                continue
            }
            if ($Text[$i + 1] -eq '*') {
                $i += 2
                while ($i -lt $Text.Length -and -not ($Text[$i] -eq '*' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/')) { $i++ }
                $i += 2
                continue
            }
        }
        if ($c -eq '[') { $depth++ }
        elseif ($c -eq ']') {
            $depth--
            if ($depth -eq 0) { return $i }
        }
        $i++
    }
    throw "Unterminated JSON array."
}

function Find-SchemesProperty {
    param([string]$Text)
    $i = 0
    $depth = 0
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ($c -eq '"') {
            $end = Find-JsonStringEnd $Text $i
            if ($depth -eq 1) {
                $key = $Text.Substring($i + 1, $end - $i - 1)
                $colon = Skip-JsonTrivia $Text ($end + 1)
                if ($key -eq 'schemes' -and $colon -lt $Text.Length -and $Text[$colon] -eq ':') {
                    $open = Skip-JsonTrivia $Text ($colon + 1)
                    if ($open -lt $Text.Length -and $Text[$open] -eq '[') {
                        $close = Find-JsonArrayEnd $Text $open
                        return [pscustomobject]@{
                            KeyStart   = $i
                            ArrayStart = $open
                            ArrayEnd   = $close
                        }
                    }
                }
            }
            $i = $end + 1
            continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $Text.Length) {
            if ($Text[$i + 1] -eq '/') {
                $i += 2
                while ($i -lt $Text.Length -and $Text[$i] -ne "`n" -and $Text[$i] -ne "`r") { $i++ }
                continue
            }
            if ($Text[$i + 1] -eq '*') {
                $i += 2
                while ($i -lt $Text.Length -and -not ($Text[$i] -eq '*' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/')) { $i++ }
                $i += 2
                continue
            }
        }
        if ($c -eq '{' -or $c -eq '[') { $depth++ }
        elseif ($c -eq '}' -or $c -eq ']') { $depth-- }
        $i++
    }
    return $null
}

function Remove-JsonComments {
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    $inString = $false
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if ($c -eq '\' -and ($i + 1) -lt $Text.Length) {
                [void]$sb.Append($Text[$i + 1])
                $i += 2
                continue
            }
            if ($c -eq '"') { $inString = $false }
            $i++
            continue
        }
        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $Text.Length) {
            if ($Text[$i + 1] -eq '/') {
                $i += 2
                while ($i -lt $Text.Length -and $Text[$i] -ne "`n" -and $Text[$i] -ne "`r") { $i++ }
                continue
            }
            if ($Text[$i + 1] -eq '*') {
                $i += 2
                while ($i -lt $Text.Length -and -not ($Text[$i] -eq '*' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/')) { $i++ }
                $i += 2
                continue
            }
        }
        [void]$sb.Append($c)
        $i++
    }
    return $sb.ToString()
}

function ConvertFrom-Jsonc {
    param([string]$Text)
    $clean = Remove-JsonComments $Text
    $clean = [regex]::Replace($clean, ',(\s*[}\]])', '$1')
    return $clean | ConvertFrom-Json
}

function Format-SchemesArray {
    param($Schemes, [string]$Indent)
    $list = @($Schemes)
    if ($list.Count -eq 0) {
        return '[]'
    }
    $entryIndent = $Indent + '    '
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($scheme in $list) {
        $json = ConvertTo-Json -InputObject $scheme -Depth 10
        $lines = $json -split "`r?`n"
        $indented = ($lines | ForEach-Object { $entryIndent + $_ }) -join "`r`n"
        $parts.Add($indented)
    }
    return "[`r`n" + ($parts -join ",`r`n") + "`r`n" + $Indent + ']'
}

if (-not $SettingsPath) {
    $SettingsPath = Get-WindowsTerminalSettingsPath
}
if (-not $SettingsPath) {
    throw "Windows Terminal settings.json was not found. Use -SettingsPath to specify it."
}
if (-not (Test-Path -LiteralPath $SettingsPath)) {
    throw "Settings file not found: $SettingsPath"
}

$incoming = @(ConvertFrom-Jsonc (Get-Content -LiteralPath $schemesFile -Raw))
if ($incoming.Count -eq 1 -and $incoming[0] -is [System.Array]) {
    $incoming = @($incoming[0])
}
$incomingNames = @($incoming | ForEach-Object { $_.name })
$text = Get-Content -LiteralPath $SettingsPath -Raw
$property = Find-SchemesProperty $text

$existing = @()
if ($property) {
    $arrayText = $text.Substring($property.ArrayStart + 1, $property.ArrayEnd - $property.ArrayStart - 1)
    if ($arrayText.Trim().Length -gt 0) {
        $existing = @(ConvertFrom-Jsonc ('[' + $arrayText + ']'))
        if ($existing.Count -eq 1 -and $existing[0] -is [System.Array]) {
            $existing = @($existing[0])
        }
    }
}

$kept = @($existing | Where-Object { $incomingNames -notcontains $_.name })
if ($Uninstall) {
    $merged = $kept
} else {
    $merged = @($kept) + $incoming
}

if ($property) {
    $lineStart = $text.LastIndexOf("`n", $property.KeyStart)
    if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }
    $indent = ''
    for ($j = $lineStart; $j -lt $property.KeyStart; $j++) {
        if ($text[$j] -eq ' ' -or $text[$j] -eq "`t") { $indent += $text[$j] } else { break }
    }
    $arrayText = Format-SchemesArray $merged $indent
    $newText = $text.Substring(0, $property.KeyStart) + '"schemes": ' + $arrayText + $text.Substring($property.ArrayEnd + 1)
} else {
    $indent = '    '
    $arrayText = Format-SchemesArray $merged $indent
    $closeIndex = $text.LastIndexOf('}')
    if ($closeIndex -lt 0) { throw "Invalid settings.json: missing closing brace." }
    $before = $text.Substring(0, $closeIndex).TrimEnd()
    $separator = ''
    if (-not $before.EndsWith('{') -and -not $before.EndsWith(',')) { $separator = ',' }
    $newText = $before + $separator + "`r`n" + $indent + '"schemes": ' + $arrayText + "`r`n" + $text.Substring($closeIndex)
}

# Validate the result before touching the real file.
$null = ConvertFrom-Jsonc $newText

if ($DryRun) {
    Write-Host "Settings file : $SettingsPath"
    if ($Uninstall) {
        Write-Host "Would remove $($incomingNames.Count) scheme(s):"
    } else {
        Write-Host "Would install $($incoming.Count) scheme(s):"
    }
    $incomingNames | ForEach-Object { Write-Host "  - $_" }
    Write-Host "Dry run: no changes written."
    return
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$SettingsPath.bak-vscode-themes-$timestamp"
$suffix = 1
while (Test-Path -LiteralPath $backup) {
    $backup = "$SettingsPath.bak-vscode-themes-$timestamp-$suffix"
    $suffix++
}
Copy-Item -LiteralPath $SettingsPath -Destination $backup

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($SettingsPath, $newText, $utf8)

Write-Host "Settings file : $SettingsPath"
Write-Host "Backup        : $backup"
if ($Uninstall) {
    Write-Host "Removed       : $($incomingNames.Count) scheme(s)"
} else {
    Write-Host "Installed     : $($incoming.Count) scheme(s)"
}
Write-Host ""
Write-Host "Next: open Windows Terminal Settings > Appearance > Color scheme,"
Write-Host "or add a scheme name to a profile's 'colorScheme' setting."
