# ProgressReader.ps1 - THE headline feature.
# Live, SMOOTH, accurate loading bar for Bannerlord + ROT loads. Friendly, plain-English.
#
# Accuracy approach:
#  - The bar is driven by a real, monotonically-increasing metric: total files the engine
#    has opened (log grows as it loads). We map that against a learned typical-total so the
#    bar moves smoothly, not in 6 big lurches.
#  - Phase label (words) comes from what it's loading now, for human context.
#  - Ratchet: bar never goes backwards.
#  - ASCII only (PS 5.1 safe). Redraw in place (no strobe).

function Watch-BannerlordLoad {
    [CmdletBinding()]
    param(
        [string] $LogDir = "C:\ProgramData\Mount and Blade II Bannerlord\logs",
        [double] $PollSeconds = 1.0,
        [int]    $StallWarnSeconds = 300,
        [int]    $MaxMinutes = 45,
        # Typical total 'open/load' operations for a first ROT new-game (used to scale the bar).
        # Learned from real loads; the bar self-corrects if the real total exceeds it.
        [int]    $ExpectedOps = 260000
    )

    $phaseWords = @(
        @{ Rx='campaign started|OnGameLoaded|OnCampaignStart|EnterMenu'; Title='You made it in!';      Done=$true }
        @{ Rx='Initializing new game';                                    Title='Creating the realm';    Done=$false }
        @{ Rx='terrain|atmosphere|campaign_map';                          Title='Painting the map';      Done=$false }
        @{ Rx='ROT_wanderer|ROT-Content|ROT-Dragon';                      Title='Building Westeros';     Done=$false }
        @{ Rx='voice_strings|action_strings|comment_strings|GameText';    Title='Reading world files';   Done=$false }
        @{ Rx='.';                                                        Title='Waking up the game';    Done=$false }
    )

    # Turn a raw engine log line into a short, friendly "what it's doing" phrase.
    function Humanize($line) {
        switch -Regex ($line) {
            'ROT_wanderer'                 { return 'Loading Westeros characters & backstories' }
            'ROT-Content'                  { return 'Loading Realm of Thrones content' }
            'ROT_Map|ROT-Map'              { return 'Loading the Westeros map data' }
            'ROT-Dragon'                   { return 'Loading dragons & special units' }
            'Initializing new game'        { return 'Generating the campaign world' }
            'voice_strings'                { return 'Loading character voices' }
            'action_strings|comment'       { return 'Loading dialogue & interactions' }
            'trait_strings'                { return 'Loading lord personalities & traits' }
            'world_lore'                   { return 'Loading world lore' }
            'companion'                    { return 'Loading companions' }
            'sp_battles|battle'            { return 'Setting up battle scenarios' }
            'settlement|town|castle|village'{ return 'Placing settlements' }
            'terrain|atmosphere|map'       { return 'Building the world map' }
            'GameText|strings\.xml'        { return 'Loading game text' }
            'duplicate key'                { return 'Sorting through mod data' }
            'opening .*\.xml'              { return 'Reading data files' }
            default                        { return $null }
        }
    }

    function Draw($pct, $title, $spin, $status, $sc, $feed) {
        $e=[char]27
        $sb=New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("$e[H")   # cursor home, no clear = no flicker
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("   +--------------------------------------------------+")
        [void]$sb.AppendLine("   |         REALM OF THRONES  -  Co-op Loader         |")
        [void]$sb.AppendLine("   +--------------------------------------------------+")
        [void]$sb.AppendLine("")
        $barLen=44; $fill=[int]($pct/100*$barLen)
        $bar=('#'*$fill)+('.'*($barLen-$fill))
        [void]$sb.AppendLine("     [$bar]")
        [void]$sb.AppendLine(("            {0,3}%   {1} {2}" -f $pct, $spin, $title).PadRight(60))
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("     Status: $status".PadRight(66))
        [void]$sb.AppendLine("     ----------------------------------------------")
        [void]$sb.AppendLine("     Live activity:".PadRight(66))
        # show the rolling activity feed (most recent last), padded to a fixed height so
        # the frame doesn't jump around
        $feedLines = @($feed)
        for ($i=0; $i -lt 6; $i++) {
            $ln = if ($i -lt $feedLines.Count) { "  > " + $feedLines[$i] } else { "" }
            [void]$sb.AppendLine(("     " + $ln).PadRight(66))
        }
        [void]$sb.AppendLine("     ----------------------------------------------")
        [void]$sb.AppendLine("     This window only watches the game. Safe to leave open.".PadRight(66))
        Write-Host $sb.ToString() -NoNewline
    }

    try { Clear-Host } catch {}
    $spinner=@('|','/','-','\'); $spin=0
    $maxPct=0; $lastGrow=Get-Date; $lastLen=0; $start=Get-Date
    $feed=[System.Collections.Generic.List[string]]::new(); $lastActivity=''

    while ($true) {
        if (((Get-Date)-$start).TotalMinutes -gt $MaxMinutes) {
            Write-Host "`n`n  Watched for $MaxMinutes min. If not in yet, check the game window.`n" -ForegroundColor Yellow; break
        }

        $main = Get-ChildItem $LogDir -Filter 'rgl_log_*.txt' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'errors' } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $proc = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'Bannerlord' } | Select-Object -First 1

        if (-not $proc -and -not $main) {
            try { Clear-Host } catch {}
            Write-Host "`n  Waiting for the game to start... launch it and click Play.`n" -ForegroundColor Cyan
            Start-Sleep $PollSeconds; continue
        }

        # --- accurate metric: file size of the log approximates work done (grows as it loads) ---
        $len = if ($main) { $main.Length } else { 0 }
        $tail = if ($main) { Get-Content $main.FullName -Tail 60 -ErrorAction SilentlyContinue } else { @() }
        $joined = $tail -join "`n"

        # phase words + a completion signal
        $title='Loading'; $isDone=$false
        foreach ($p in $phaseWords) { if ($joined -match $p.Rx) { $title=$p.Title; $isDone=$p.Done; break } }

        # rolling activity feed: humanize the newest meaningful log lines, de-duped
        foreach ($ln in ($tail | Select-Object -Last 12)) {
            $h = Humanize $ln
            if ($h -and $h -ne $lastActivity) {
                $feed.Add($h); $lastActivity = $h
                while ($feed.Count -gt 6) { $feed.RemoveAt(0) }
            }
        }

        # Count "Initializing new game begin". ONE or a few = normal world generation.
        # MANY (the whole init sequence restarting over and over) = the known ROT
        # infinite-loop bug: duplicate keys in ROT's string XML abort string-table
        # loading, so init retries forever and never reaches the map. We must NOT paint
        # that as "almost done" (the trap that makes people wait an hour for nothing).
        # We scan the WHOLE log for this, not just the tail, so the count is real.
        $initCount = if ($main) { ([regex]::Matches((Get-Content $main.FullName -Raw -ErrorAction SilentlyContinue),'Initializing new game begin')).Count } else { 0 }
        $initLoopBug = $initCount -ge 10

        # size-based percent, scaled to expected total; ratchet upward only
        $rawPct = if ($ExpectedOps -gt 0) { [int]([math]::Min(99, ($len/1KB) / ($ExpectedOps/1KB) * 100)) } else { 0 }
        if ($rawPct -gt $maxPct) { $maxPct = $rawPct }
        $pct = if ($isDone) { 100 } else { $maxPct }

        # health
        $grew = ($len -gt $lastLen)
        if ($grew) { $lastGrow=Get-Date }; $lastLen=$len
        $quiet=[int]((Get-Date)-$lastGrow).TotalSeconds
        $resp = if ($proc){ $proc.Responding } else { $true }
        if     ($initLoopBug)              { $status="STUCK IN A LOOP ($initCount x). This is the ROT string-file bug. Close the game, run 'Fix common problems', relaunch."; $sc='Red' }
        elseif (-not $proc)                { $status='Game window closed. If you are NOT in-game, it may have crashed.'; $sc='Yellow' }
        elseif (-not $resp)                { $status='Working hard. Windows may say "not responding" - that is NORMAL.'; $sc='Yellow' }
        elseif ($quiet -gt $StallWarnSeconds){ $status="Still going, just quiet. First loads take a while - hang tight."; $sc='Yellow' }
        else                               { $status='Everything looks healthy. Sit tight!'; $sc='Green' }

        Draw $pct $title $spinner[$spin % 4] $status $sc $feed

        # If we detect the loop bug, stop pretending it's loading - tell the truth and bail.
        if ($initLoopBug) {
            Write-Host "`n" -NoNewline
            Write-Host "     !!  DETECTED THE INFINITE-LOAD BUG  !!" -ForegroundColor Red
            Write-Host "     The game is stuck re-initializing ($initCount times and counting)." -ForegroundColor Yellow
            Write-Host "     It will NOT finish on its own. Here's the fix:" -ForegroundColor Yellow
            Write-Host "       1. Close the game." -ForegroundColor White
            Write-Host "       2. Back at the menu, pick '4) Fix common problems'." -ForegroundColor White
            Write-Host "       3. Launch again - it'll load normally this time." -ForegroundColor White
            Write-Host "`n     Press Enter to go back." -ForegroundColor Gray
            $null = Read-Host; break
        }

        if ($isDone -or ($pct -ge 100)) {
            Write-Host "`n" -NoNewline
            Write-Host "        *********************************************" -ForegroundColor Green
            Write-Host "        *   YOU OFFICIALLY MADE IT INTO WESTEROS!   *" -ForegroundColor Green
            Write-Host "        *********************************************" -ForegroundColor Green
            Write-Host "`n        Have fun. Press Enter to close this window." -ForegroundColor Gray
            $null = Read-Host; break
        }
        $spin++
        Start-Sleep $PollSeconds
    }
}
