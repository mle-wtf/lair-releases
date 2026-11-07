# Install or upgrade LAIR on Windows, without elevation:
#
#   irm https://lair.mle.wtf/install.ps1 | iex
#
# Uses winget when it knows MLE.LAIR. Otherwise downloads the Inno Setup
# installer and SHA256SUMS from the latest lair-releases release, refuses a
# checksum mismatch, and runs the installer silently for the current user
# (it is PrivilegesRequired=lowest, so nothing here asks for admin).
#
# An upgrade first stops this user's lair and lair-minion-tray processes
# running from the install folder, which hold its files: a silent install
# cannot replace them and aborts with exit 5 (d13506dd). Afterwards it starts
# the tray, since a silent install skips the installer's own launch: when
# LAIR was running before, or on a desktop session (not over ssh).
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
    $dir = Join-Path $env:LOCALAPPDATA 'Programs\LAIR Minion'
    $tray = Join-Path $dir 'lair-minion-tray.exe'
    # This user's LAIR processes running from $dir: the minion, the tray, and
    # any TUI or MCP child. Another user's, or a build run from elsewhere,
    # holds none of these files and is left alone.
    # By SID: over ssh $env:USERDOMAIN can read WORKGROUP, not the machine.
    $running = {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        @(Get-CimInstance Win32_Process -Filter "Name = 'lair.exe' OR Name = 'lair-minion-tray.exe'" | Where-Object {
            $_.ExecutablePath -and $_.ExecutablePath.StartsWith("$dir\", [StringComparison]::OrdinalIgnoreCase) -and $(
                # A process that exits mid-list has no owner to read: not ours to stop.
                $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction SilentlyContinue
                $owner.ReturnValue -eq 0 -and $owner.Sid -eq $me
            )
        })
    }
    # Stopped and confirmed gone before the installer runs: a stop that
    # failed would only show up as the installer's exit 5.
    $stop = {
        # @() as well: PowerShell 5.1 gives one CimInstance no Count.
        $found = @(& $running)
        if (-not $found.Count) { return $false }
        foreach ($p in $found) {
            Write-Host "Stopping $($p.Name) (pid $($p.ProcessId)) so its files can be replaced ..."
            # One may already have gone with its parent; the re-list below is the check.
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Wait-Process -Id ($found | ForEach-Object { $_.ProcessId }) -Timeout 15 -ErrorAction SilentlyContinue
        if (@(& $running).Count) { throw 'lair install: a LAIR process would not stop. Stop it from an elevated prompt (Stop-Process -Name lair, lair-minion-tray) and run this again.' }
        return $true
    }
    # Over ssh there is no desktop for the tray to stand on: one started here
    # would have no taskbar and would die with the ssh session.
    $ssh = [bool]($env:SSH_CONNECTION -or $env:SSH_CLIENT)
    $desktop = [Environment]::UserInteractive -and -not $ssh
    $relaunch = {
        param([bool]$WasRunning)
        if ($ssh) {
            if ($WasRunning) { Write-Host 'LAIR was stopped for the upgrade. Start it again from the Start menu on the desktop.' }
            return
        }
        if (($WasRunning -or $desktop) -and (Test-Path -LiteralPath $tray)) {
            Write-Host 'Starting the LAIR tray ...'
            Start-Process -FilePath $tray -WorkingDirectory $dir
        }
    }
    # `iex` runs in the window it was pasted into, so lair goes on this window's
    # PATH as well: the installer's change to the user PATH only reaches windows
    # opened afterwards, and `lair` straight after installing must just work.
    $ready = {
        param([bool]$WasRunning)
        & $relaunch $WasRunning
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
                $was = & $stop
                Write-Host 'Installing LAIR with winget ...'
                & winget install --id MLE.LAIR --exact --scope user --source winget --silent --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -ne 0) {
                    $rc = $LASTEXITCODE
                    if ($was) { & $relaunch $true }
                    throw "lair install: winget install failed (exit $rc)."
                }
                & $ready $was
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

        $was = & $stop
        Write-Host 'Installing ...'
        # /CLOSEAPPLICATIONS: Inno's Restart Manager closes whatever still
        # holds a file, a second layer under the stop above.
        $p = Start-Process -FilePath $exe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', '/CLOSEAPPLICATIONS' -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            # The old install is still in place: bring back what was stopped.
            if ($was) { & $relaunch $true }
            $why = if ($p.ExitCode -eq 5) { ' A LAIR process it could not replace may still be running, perhaps one started as administrator: stop it from an elevated prompt (Stop-Process -Name lair, lair-minion-tray) and run this again.' } else { '' }
            throw "lair install: the installer failed (exit $($p.ExitCode)).$why"
        }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    & $ready $was
}
