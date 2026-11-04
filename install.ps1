# Install or upgrade LAIR on Windows, without elevation:
#
#   irm https://lair.mle.wtf/install.ps1 | iex
#
# Uses winget when it knows MLE.LAIR. Otherwise downloads the Inno Setup
# installer and SHA256SUMS from the latest lair-releases release, refuses a
# checksum mismatch, and runs the installer silently for the current user
# (it is PrivilegesRequired=lowest, so nothing here asks for admin).
#
# $env:LAIR_RELEASE_BASE points it at another release directory (a staging
# release, or a local server for testing); winget is skipped when it is set,
# since winget would install its own release instead.
#
# Windows PowerShell 5.1 compatible. Errors throw rather than exit, so a
# failure under `iex` does not close the window it was pasted into.

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'  # 5.1's progress bar slows downloads to a crawl
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $done = 'Run `lair` to sign in or create an account.'
    # `iex` runs in the window it was pasted into, so lair goes on this window's
    # PATH as well: the installer's change to the user PATH only reaches windows
    # opened afterwards, and `lair` straight after installing must just work.
    $ready = {
        $dir = Join-Path $env:LOCALAPPDATA 'Programs\LAIR Minion'
        if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$env:Path;$dir" }
        Write-Host 'Installed. `lair` is ready in this window.'
        Write-Host $done
    }
    $base = $env:LAIR_RELEASE_BASE
    if (-not $base) {
        $base = 'https://github.com/mle-wtf/lair-releases/releases/latest/download'
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            # 5.1 turns a native command's redirected stderr into a terminating
            # error under 'Stop', so the probe runs under 'Continue'.
            $known = & {
                $ErrorActionPreference = 'Continue'
                & winget show --id MLE.LAIR --exact --source winget --accept-source-agreements *> $null
                $LASTEXITCODE -eq 0
            }
            if ($known) {
                Write-Host 'Installing LAIR with winget ...'
                & winget install --id MLE.LAIR --exact --scope user --source winget --silent --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -ne 0) { throw "lair install: winget install failed (exit $LASTEXITCODE)." }
                & $ready
                return
            }
        }
    }

    $asset = 'lair-windows-x64-setup.exe'
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('lair-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $exe = Join-Path $tmp $asset
        $sums = Join-Path $tmp 'SHA256SUMS'
        Write-Host "Downloading $asset ..."
        Invoke-WebRequest -UseBasicParsing -Uri "$base/$asset" -OutFile $exe
        Invoke-WebRequest -UseBasicParsing -Uri "$base/SHA256SUMS" -OutFile $sums

        $want = $null
        foreach ($line in Get-Content -LiteralPath $sums) {
            $fields = $line.Trim() -split '\s+'
            if ($fields.Count -eq 2 -and $fields[1].TrimStart('*') -eq $asset) { $want = $fields[0].ToLower() }
        }
        if (-not $want) { throw "lair install: SHA256SUMS has no entry for $asset." }
        $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash.ToLower()
        if ($got -ne $want) {
            throw "lair install: checksum mismatch for $asset (expected $want, got $got). Nothing was installed."
        }

        Write-Host 'Installing ...'
        $p = Start-Process -FilePath $exe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER' -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "lair install: the installer failed (exit $($p.ExitCode))." }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    & $ready
}
