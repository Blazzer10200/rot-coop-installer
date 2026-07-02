# ProgressReader.ps1 - THE headline feature.
# Tails Bannerlord's live engine log during load and renders a friendly, human progress screen.
# Goal: comfort a non-technical user. No jargon. Reassure while working; celebrate when in-game.
#
# Design constraints learned the hard way:
#  - ASCII ONLY (PowerShell 5.1 default console encoding turns em-dashes / box-art into mojibake).
#  - Progress must never go backwards (ratchet) - Bannerlord loads in overlapping waves.
#  - Redraw in place (no full-screen clear) to avoid strobe flicker and preserve scrollback.

function Watch-BannerlordLoad {
    [CmdletBinding()]
    param(
        [string] $LogDir = "C:\ProgramData\Mount and Blade II Bannerlord\logs",
        [int]    $PollSeconds = 2,
        [int]    $StallWarnSeconds = 300,
        [int]    $MaxMinutes = 45      # safety: stop watching after this long
    )

    # Ordered phases: friendly title + calming blurb + detection regex.
    $phases = @(
        @{ Key='boot';  Title='Waking up the game';      Blurb='Starting the engine and loading the mod launcher.';        Rx='Initializing engine|create device|renderer|rgl_gpu' }
        @{ Key='data';  Title='Reading the world files';  Blurb='Loading all the text, dialogue and rules for Westeros.';   Rx='voice_strings|action_strings|comment_strings|GameText|ModuleData.*strings' }
        @{ Key='rot';   Title='Building Westeros';        Blurb='Loading Realm of Thrones content. This is the big one.';   Rx='ROT_wanderer|ROT-Content|ROT-Dragon' }
        @{ Key='gen';   Title='Creating the realm';       Blurb='Placing every lord, house and army onto the map.';         Rx='Initializing new game|CampaignBehavior|MobileParty|SpawnParties|sp_battles' }
        @{ Key='scene'; Title='Painting the map';         Blurb='Almost there - drawing the campaign map of Westeros.';     Rx='terrain|atmosphere|campaign_map|InitializeCampaign' }
        @{ Key='done';  Title='You made it in!';          Blurb='Welcome to Westeros.';                                     Rx='campaign started|OnGameLoaded|OnCampaignStart|EnterMenu' }
    )

    function Write-Screen($idx, $pct, $spin, $status, $sc, $barColor, $phases) {
        # Move cursor to home (ESC[H) WITHOUT clearing whole buffer -> no flicker, keeps scrollback.
        $e = [char]27
        $out = New-Object System.Text.StringBuilder
        [void]$out.AppendLine("$e[H")
        [void]$out.AppendLine("")
        [void]$out.AppendLine("   +--------------------------------------------------+")
        [void]$out.AppendLine("   |         REALM OF THRONES  -  Co-op Loader         |")
        [void]$out.AppendLine("   +--------------------------------------------------+")
        [void]$out.AppendLine("")
        $barLen=40; $fill=[int]($pct/100*$barLen)
        $bar = ('#'*$fill) + ('.'*($barLen-$fill))
        [void]$out.AppendLine("     [$bar] $pct%   ")
        [void]$out.AppendLine("")
        for ($i=0; $i -lt $phases.Count; $i++) {
            $t = $phases[$i].Title.PadRight(26)
            if     ($i -lt $idx) { [void]$out.AppendLine("       [x] $t") }
            elseif ($i -eq $idx) { [void]$out.AppendLine("        $($spin)  $t") }
            else                 { [void]$out.AppendLine("       [ ] $t") }
        }
        [void]$out.AppendLine("")
        [void]$out.AppendLine("     $($phases[$idx].Blurb)".PadRight(70))
        [void]$out.AppendLine("")
        [void]$out.AppendLine("     Status: $status".PadRight(70))
        [void]$out.AppendLine("     ---------------------------------------------------")
        # Print buffer, then color the status line separately isn't trivial in one write;
        # keep it simple + readable: whole frame one color-neutral write, status colored after.
        Write-Host $out.ToString() -NoNewline
    }

    try { Clear-Host } catch {}
    $lastWrite=$null; $lastCpu=0; $flatSince=Get-Date; $spinner=@('|','/','-','\'); $spin=0
    $maxIdx=0; $start=Get-Date

    while ($true) {
        if (((Get-Date)-$start).TotalMinutes -gt $MaxMinutes) {
            Write-Host "`n`n  Stopped watching after $MaxMinutes minutes. If the game still isn't in," -ForegroundColor Yellow
            Write-Host "  something may be wrong - check the game window, or re-run the repair tool.`n" -ForegroundColor Yellow
            break
        }

        $main = Get-ChildItem $LogDir -Filter 'rgl_log_*.txt' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'errors' } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $proc = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'Bannerlord' } | Select-Object -First 1

        if (-not $proc -and -not $main) {
            try { Clear-Host } catch {}
            Write-Host "`n  Waiting for Bannerlord to start..." -ForegroundColor Cyan
            Write-Host "  Launch the game, then click 'Into the Realm' or 'Host Co-op'.`n" -ForegroundColor DarkGray
            Start-Sleep $PollSeconds; continue
        }

        $tail = if ($main) { Get-Content $main.FullName -Tail 100 -ErrorAction SilentlyContinue } else { @() }
        $joined = ($tail -join "`n")

        $detected = 0
        for ($i = $phases.Count-1; $i -ge 0; $i--) { if ($joined -match $phases[$i].Rx) { $detected = $i; break } }
        if ($detected -gt $maxIdx) { $maxIdx = $detected }   # ratchet
        $idx = $maxIdx
        $pct = [int](($idx+1)/$phases.Count*100)

        $cpu  = if ($proc){ [int]$proc.CPU } else { 0 }
        $resp = if ($proc){ $proc.Responding } else { $true }
        $procGone = ($null -eq $proc)
        $logMoved = $main -and ($main.LastWriteTime -ne $lastWrite)
        if ($logMoved -or $cpu -gt $lastCpu) { $flatSince = Get-Date }
        $flatSecs = [int]((Get-Date)-$flatSince).TotalSeconds
        $lastWrite = if($main){$main.LastWriteTime}; $lastCpu = $cpu

        # If the game process vanished mid-load = it crashed.
        if ($procGone -and $idx -lt ($phases.Count-1)) {
            try { Clear-Host } catch {}
            Write-Host "`n  The game closed unexpectedly before finishing loading." -ForegroundColor Red
            Write-Host "  This usually means a crash. Re-run the tool's 'Fix common crashes'" -ForegroundColor Yellow
            Write-Host "  option, then launch again.`n" -ForegroundColor Yellow
            break
        }

        if     (-not $resp)                      { $status='Working hard. (Windows may say "not responding" - that is NORMAL during big loads.)'; $sc='Yellow' }
        elseif ($flatSecs -gt $StallWarnSeconds) { $status="Still going, but quiet for a bit. On a first-ever load this can take a while - hang tight."; $sc='Yellow' }
        else                                     { $status='Everything looks healthy. Sit tight!'; $sc='Green' }

        Write-Screen $idx $pct $spinner[$spin % 4] $status $sc 'Cyan' $phases

        if ($phases[$idx].Key -eq 'done') {
            Write-Host "`n" -NoNewline
            Write-Host "        *****************************************" -ForegroundColor Green
            Write-Host "        *   YOU OFFICIALLY MADE IT INTO         *" -ForegroundColor Green
            Write-Host "        *          W E S T E R O S !            *" -ForegroundColor Green
            Write-Host "        *****************************************" -ForegroundColor Green
            Write-Host ""
            Write-Host "        Have fun out there. Press Enter to close this window." -ForegroundColor Gray
            $null = Read-Host
            break
        }
        $spin++
        Start-Sleep $PollSeconds
    }
}
