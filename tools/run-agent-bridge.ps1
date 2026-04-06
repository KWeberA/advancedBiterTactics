param(
  [Parameter(Mandatory = $true)]
  [string]$Scenario,

  [string]$FactorioExe,

  [int]$BenchmarkTicks = 1800,

  [string]$CaptureTicks = "0,60,120,180,240,300,360,480,600,720,900,1200,1500,1800",

  [string]$RunTag
)

$ErrorActionPreference = "Stop"

function Get-RepoPath {
  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

function Ensure-FactorioExe {
  param(
    [string]$RepoPath,
    [string]$ExplicitPath
  )

  if ($ExplicitPath) {
    if (-not (Test-Path $ExplicitPath)) {
      throw ("Configured Factorio executable does not exist: " + $ExplicitPath)
    }
    return $ExplicitPath
  }

  $settingsPath = Join-Path $RepoPath ".vscode\settings.json"
  if (Test-Path $settingsPath) {
    $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    if ($settings.advancedBiterTactics.factorioExe) {
      $configuredPath = [string]$settings.advancedBiterTactics.factorioExe
      if (-not (Test-Path $configuredPath)) {
        throw ("Configured Factorio executable does not exist: " + $configuredPath)
      }
      return $configuredPath
    }
  }

  throw "Set advancedBiterTactics.factorioExe in .vscode/settings.json or pass -FactorioExe explicitly."
}

function Invoke-TestModSync {
  param(
    [string]$RepoPath
  )

  & "powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoPath ".vscode\factorio-vscode.ps1") -Action sync
}

function Get-TestPaths {
  param(
    [string]$RepoPath
  )

  $modInfo = Get-Content -Path (Join-Path $RepoPath "info.json") -Raw | ConvertFrom-Json
  $modRoot = Join-Path $RepoPath ".factorio-test\mods"
  $userData = Join-Path $RepoPath ".factorio-test\user-data"

  return @{
    ModName = $modInfo.name
    ModVersion = $modInfo.version
    ModRoot = $modRoot
    UserData = $userData
    SavesDir = Join-Path $userData "saves"
    ScriptOutputDir = Join-Path $userData "script-output"
  }
}

function New-RunId {
  param(
    [string]$Scenario,
    [string]$RunTag
  )

  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $safeScenario = ($Scenario -replace "[^a-zA-Z0-9_-]", "-")
  $safeTag = if ($RunTag) { "-" + ($RunTag -replace "[^a-zA-Z0-9_-]", "-") } else { "" }
  return ($timestamp + "-" + $safeScenario + $safeTag)
}

function Convert-CaptureTicks {
  param(
    [string]$CaptureTicksValue,
    [int]$BenchmarkTicksValue
  )

  $ticks = @()
  foreach ($part in ($CaptureTicksValue -split ",")) {
    $trimmed = $part.Trim()
    if ($trimmed -eq "") {
      continue
    }

    $value = 0
    if (-not [int]::TryParse($trimmed, [ref]$value)) {
      throw ("Invalid capture tick: " + $trimmed)
    }

    if ($value -lt 0) {
      throw ("Capture tick must be non-negative: " + $trimmed)
    }

    $ticks += $value
  }

  if ($ticks.Count -eq 0) {
    $ticks = @(0, $BenchmarkTicksValue)
  }

  if (-not ($ticks -contains 0)) {
    $ticks += 0
  }

  if (-not ($ticks -contains $BenchmarkTicksValue)) {
    $ticks += $BenchmarkTicksValue
  }

  $ticks = $ticks | Sort-Object -Unique
  return ,$ticks
}

function New-HarnessInfoJson {
  param(
    [string]$TargetModName,
    [string]$TargetModVersion
  )

  return @"
{
  "name": "abt-agent-bridge-harness",
  "version": "0.1.0",
  "title": "ABT Agent Bridge Harness",
  "author": "OpenAI",
  "factorio_version": "2.0",
  "dependencies": ["base >= 2.0.0", "? space-age", "$TargetModName >= $TargetModVersion"]
}
"@
}

function New-HarnessControlLua {
  param(
    [string]$Scenario,
    [string]$RunDir,
    [int[]]$CaptureTickList,
    [int]$BenchmarkTicksValue
  )

  $tickLiterals = ($CaptureTickList | ForEach-Object { [string]$_ }) -join ", "

  return @"
local RUN_DIR = "$RunDir"
local SCENARIO_NAME = "$Scenario"
local FINAL_TICK = $BenchmarkTicksValue
local CAPTURE_TICKS = {$tickLiterals}

local function write_json(path, data)
  helpers.write_file(path, helpers.table_to_json(data), false)
end

local function append_jsonl(path, data)
  helpers.write_file(path, helpers.table_to_json(data) .. "\n", true)
end

local function ensure_state()
  storage.capture_tick_lookup = storage.capture_tick_lookup or {}
  storage.seen_event_keys = storage.seen_event_keys or {}
  storage.captured_ticks = storage.captured_ticks or {}
  storage.finalized = storage.finalized or false
  storage.start_tick = storage.start_tick or nil
end

local function make_event_key(event)
  return table.concat({
    event.tick or 0,
    event.event or "",
    event.group_id or 0,
    event.reason or "",
    event.wave_index or 0
  }, ":")
end

local function append_recent_events(frame)
  local recent_events = frame and frame.recent_events or {}
  for index = 1, #recent_events do
    local event = recent_events[index]
    local key = make_event_key(event)
    if not storage.seen_event_keys[key] then
      storage.seen_event_keys[key] = true
      append_jsonl(RUN_DIR .. "/events.jsonl", event)
    end
  end
end

local function capture_frame(relative_tick, reason)
  local frame = remote.call("agent_bridge", "capture_frame", {
    radius = 56,
    reason = reason
  })

  if frame then
    frame.relative_tick = relative_tick
    write_json(RUN_DIR .. "/frames/frame-" .. relative_tick .. ".json", frame)
    append_recent_events(frame)
    storage.captured_ticks[relative_tick] = true
    storage.last_frame_tick = frame.tick
    storage.last_relative_tick = relative_tick
  end
end

local function finalize_run(reason)
  if storage.finalized then
    return
  end

  local relative_tick = math.max(0, game.tick - (storage.start_tick or game.tick))
  capture_frame(relative_tick, reason or "final")

  local assertions = remote.call("agent_bridge", "evaluate_assertions", SCENARIO_NAME, {
    reason = reason or "final"
  }) or {}

  write_json(RUN_DIR .. "/assertions.json", assertions)

  local passed = 0
  for index = 1, #assertions do
    if assertions[index].passed then
      passed = passed + 1
    end
  end

  local summary = {
    scenario_name = SCENARIO_NAME,
    final_tick = game.tick,
    final_relative_tick = relative_tick,
    assertion_count = #assertions,
    passed_count = passed,
    failed_count = #assertions - passed,
    passed = passed == #assertions,
    captured_ticks = CAPTURE_TICKS,
    last_frame_tick = storage.last_frame_tick,
    last_relative_tick = storage.last_relative_tick
  }

  write_json(RUN_DIR .. "/summary.json", summary)
  remote.call("agent_bridge", "reset_scenario")
  storage.finalized = true
end

local function bootstrap_run(reason)
  ensure_state()

  if storage.bridge_setup_complete then
    return
  end

  for index = 1, #CAPTURE_TICKS do
    storage.capture_tick_lookup[CAPTURE_TICKS[index]] = true
  end

  storage.start_tick = game.tick

  local setup = remote.call("agent_bridge", "setup_scenario", SCENARIO_NAME, {
    reason = reason or "runner-setup"
  })

  write_json(RUN_DIR .. "/run-manifest.json", {
    scenario_name = SCENARIO_NAME,
    final_tick = FINAL_TICK,
    capture_ticks = CAPTURE_TICKS,
    setup = setup,
    started_tick = game.tick,
    start_tick = storage.start_tick,
    bootstrap_reason = reason or "runner-setup"
  })

  capture_frame(0, "post-setup")
  storage.bridge_setup_complete = true
end

script.on_init(function()
  bootstrap_run("runner-init")
end)

script.on_configuration_changed(function()
  bootstrap_run("runner-config-changed")
end)

script.on_event(defines.events.on_tick, function(event)
  ensure_state()

  if storage.finalized then
    return
  end

  local relative_tick = event.tick - (storage.start_tick or event.tick)

  if storage.capture_tick_lookup[relative_tick] and not storage.captured_ticks[relative_tick] then
    capture_frame(relative_tick, "scheduled")
  end

  if relative_tick >= FINAL_TICK then
    finalize_run("benchmark-complete")
  end
end)
"@
}

function Write-HarnessMod {
  param(
    [string]$RepoPath,
    [hashtable]$Paths,
    [string]$Scenario,
    [string]$RunDir,
    [int[]]$CaptureTickList,
    [int]$BenchmarkTicksValue
  )

  $harnessName = "abt-agent-bridge-harness"
  $harnessVersion = "0.1.0"
  $harnessDir = Join-Path $Paths.ModRoot ($harnessName + "_" + $harnessVersion)
  if (Test-Path $harnessDir) {
    Remove-Item -LiteralPath $harnessDir -Recurse -Force
  }

  New-Item -ItemType Directory -Force -Path $harnessDir | Out-Null

  $infoJson = New-HarnessInfoJson -TargetModName $Paths.ModName -TargetModVersion $Paths.ModVersion
  $controlLua = New-HarnessControlLua -Scenario $Scenario -RunDir $RunDir -CaptureTickList $CaptureTickList -BenchmarkTicksValue $BenchmarkTicksValue

  Set-Content -Path (Join-Path $harnessDir "info.json") -Value $infoJson -Encoding Ascii
  Set-Content -Path (Join-Path $harnessDir "control.lua") -Value $controlLua -Encoding Ascii

  $modList = @{
    mods = @(
      @{ name = "base"; enabled = $true },
      @{ name = $Paths.ModName; enabled = $true },
      @{ name = $harnessName; enabled = $true }
    )
  } | ConvertTo-Json -Depth 4

  Set-Content -Path (Join-Path $Paths.ModRoot "mod-list.json") -Value $modList -Encoding Ascii
}

function Invoke-FactorioProcess {
  param(
    [string]$ExecutablePath,
    [string]$RepoPath,
    [string]$UserDataPath,
    [string[]]$ArgumentList
  )

  $lockPath = Join-Path $UserDataPath ".lock"
  $deadline = [DateTime]::UtcNow.AddSeconds(5)
  while ((Test-Path $lockPath) -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 250
  }

  if (Test-Path $lockPath) {
    $factorioProcess = Get-Process factorio -ErrorAction SilentlyContinue
    if ($factorioProcess) {
      throw ("Factorio lock file is still present and a factorio process is still running: " + $lockPath)
    }

    Remove-Item -LiteralPath $lockPath -Force
  }

  $process = Start-Process -FilePath $ExecutablePath -WorkingDirectory $RepoPath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow
  if ($process.ExitCode -ne 0) {
    throw ("Factorio exited with code " + $process.ExitCode)
  }
}

function Invoke-FactorioBenchmark {
  param(
    [string]$ExecutablePath,
    [string]$RepoPath,
    [string]$ConfigPath,
    [string]$ModDirectory,
    [string]$SavePath,
    [int]$BenchmarkTicksValue
  )

  $effectiveBenchmarkTicks = $BenchmarkTicksValue + 1

  Invoke-FactorioProcess -ExecutablePath $ExecutablePath -RepoPath $RepoPath -UserDataPath (Split-Path (Split-Path $SavePath -Parent) -Parent) -ArgumentList @(
    "--config",
    $ConfigPath,
    "--mod-directory",
    $ModDirectory,
    "--disable-audio",
    "--benchmark",
    $SavePath,
    "--benchmark-ticks",
    [string]$effectiveBenchmarkTicks,
    "--benchmark-runs",
    "1",
    "--benchmark-ignore-paused"
  )
}

function Invoke-FactorioCreate {
  param(
    [string]$ExecutablePath,
    [string]$RepoPath,
    [string]$ConfigPath,
    [string]$ModDirectory,
    [string]$SavePath
  )

  Invoke-FactorioProcess -ExecutablePath $ExecutablePath -RepoPath $RepoPath -UserDataPath (Split-Path (Split-Path $SavePath -Parent) -Parent) -ArgumentList @(
    "--config",
    $ConfigPath,
    "--mod-directory",
    $ModDirectory,
    "--disable-audio",
    "--map-gen-seed",
    "424242",
    "--create",
    $SavePath
  )
}

$repoPath = Get-RepoPath
$factorioPath = Ensure-FactorioExe -RepoPath $repoPath -ExplicitPath $FactorioExe
$paths = Get-TestPaths -RepoPath $repoPath
$configPath = Join-Path $repoPath "factorio-test-config.ini"
$runId = New-RunId -Scenario $Scenario -RunTag $RunTag
$captureTickList = Convert-CaptureTicks -CaptureTicksValue $CaptureTicks -BenchmarkTicksValue $BenchmarkTicks
$relativeRunDir = "agent-bridge-runs/$runId"
$absoluteRunDir = Join-Path $paths.ScriptOutputDir $relativeRunDir
$savePath = Join-Path $paths.SavesDir ("agent-bridge-" + $runId + ".zip")

New-Item -ItemType Directory -Force -Path $paths.SavesDir | Out-Null
if (Test-Path $absoluteRunDir) {
  Remove-Item -LiteralPath $absoluteRunDir -Recurse -Force
}
if (Test-Path $savePath) {
  Remove-Item -LiteralPath $savePath -Force
}

Invoke-TestModSync -RepoPath $repoPath
Write-HarnessMod -RepoPath $repoPath -Paths $paths -Scenario $Scenario -RunDir $relativeRunDir -CaptureTickList $captureTickList -BenchmarkTicksValue $BenchmarkTicks
Invoke-FactorioCreate -ExecutablePath $factorioPath -RepoPath $repoPath -ConfigPath $configPath -ModDirectory $paths.ModRoot -SavePath $savePath
Invoke-FactorioBenchmark -ExecutablePath $factorioPath -RepoPath $repoPath -ConfigPath $configPath -ModDirectory $paths.ModRoot -SavePath $savePath -BenchmarkTicksValue $BenchmarkTicks

$summaryPath = Join-Path $absoluteRunDir "summary.json"
$assertionsPath = Join-Path $absoluteRunDir "assertions.json"

if (-not (Test-Path $summaryPath)) {
  throw ("Bridge run did not produce summary.json: " + $summaryPath)
}

$summary = Get-Content -Path $summaryPath -Raw | ConvertFrom-Json

Write-Output ("agent bridge run ok: " + $relativeRunDir)
Write-Output ("summary: " + ($summary | ConvertTo-Json -Compress -Depth 8))

if (Test-Path $assertionsPath) {
  Write-Output ("assertions: " + $assertionsPath)
}
