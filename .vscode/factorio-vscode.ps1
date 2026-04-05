param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('sync', 'start', 'smoke')]
  [string]$Action,

  [string]$FactorioExe
)

$ErrorActionPreference = 'Stop'

function Get-RepoPath {
  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Ensure-TestConfig {
  param(
    [string]$RepoPath
  )

  $config = Join-Path $RepoPath 'factorio-test-config.ini'
  if (Test-Path $config) {
    return $config
  }

  $template = Join-Path $RepoPath 'factorio-test-config.example.ini'
  $userData = (Join-Path $RepoPath '.factorio-test\user-data') -replace '\\', '/'
  $configContent = (Get-Content -Path $template -Raw).Replace('<ABSOLUTE_WRITE_DATA_PATH>', $userData)
  Set-Content -Path $config -Value $configContent -Encoding Ascii
  return $config
}

function Get-TestPaths {
  param(
    [string]$RepoPath
  )

  $modInfo = Get-Content -Path (Join-Path $RepoPath 'info.json') -Raw | ConvertFrom-Json
  $modRoot = Join-Path $RepoPath '.factorio-test\mods'
  $modDir = Join-Path $modRoot ($modInfo.name + '_' + $modInfo.version)
  $userData = Join-Path $RepoPath '.factorio-test\user-data'

  return @{
    ModName = $modInfo.name
    ModRoot = $modRoot
    ModDir = $modDir
    UserData = $userData
    LogPath = Join-Path $userData 'factorio-current.log'
  }
}

function Sync-TestModFiles {
  param(
    [string]$RepoPath
  )

  $paths = Get-TestPaths -RepoPath $RepoPath
  $config = Ensure-TestConfig -RepoPath $RepoPath

  New-Item -ItemType Directory -Force -Path $paths.ModRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $paths.UserData | Out-Null

  if (Test-Path $paths.ModDir) {
    $resolvedModDir = [System.IO.Path]::GetFullPath($paths.ModDir)
    $resolvedModRoot = [System.IO.Path]::GetFullPath($paths.ModRoot)
    if (-not $resolvedModDir.StartsWith($resolvedModRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw 'Refusing to clean unexpected test mod directory.'
    }
    Remove-Item -LiteralPath $paths.ModDir -Recurse -Force
  }

  New-Item -ItemType Directory -Force -Path $paths.ModDir | Out-Null

  Get-ChildItem -Path $RepoPath -File |
    Where-Object { $_.Name -eq 'info.json' -or $_.Extension -eq '.lua' } |
    ForEach-Object {
      Copy-Item $_.FullName (Join-Path $paths.ModDir $_.Name) -Force
    }

  foreach ($optionalDir in @('locale', 'graphics', 'sound', 'prototypes', 'migrations')) {
    $sourceDir = Join-Path $RepoPath $optionalDir
    if (Test-Path $sourceDir) {
      Copy-Item $sourceDir (Join-Path $paths.ModDir $optionalDir) -Recurse -Force
    }
  }

  $modList = @{
    mods = @(
      @{ name = 'base'; enabled = $true },
      @{ name = $paths.ModName; enabled = $true }
    )
  } | ConvertTo-Json -Depth 4

  Set-Content -Path (Join-Path $paths.ModRoot 'mod-list.json') -Value $modList -Encoding Ascii

  return @{
    ConfigPath = $config
    ModRoot = $paths.ModRoot
    LogPath = $paths.LogPath
  }
}

function Get-ValidatedFactorioExe {
  param(
    [string]$PathValue
  )

  if (-not $PathValue) {
    throw 'Set advancedBiterTactics.factorioExe in .vscode/settings.json or in your user settings.'
  }

  if (-not (Test-Path $PathValue)) {
    throw ('Configured Factorio executable does not exist: ' + $PathValue)
  }

  return $PathValue
}

function Start-LocalFactorio {
  param(
    [string]$RepoPath,
    [string]$ExecutablePath
  )

  $paths = Get-TestPaths -RepoPath $RepoPath
  $config = Ensure-TestConfig -RepoPath $RepoPath
  Start-Process -FilePath $ExecutablePath -WorkingDirectory $RepoPath -ArgumentList @(
    '--config',
    $config,
    '--mod-directory',
    $paths.ModRoot
  ) | Out-Null
}

function Invoke-StartupSmokeTest {
  param(
    [string]$RepoPath,
    [string]$ExecutablePath
  )

  $paths = Get-TestPaths -RepoPath $RepoPath
  $config = Ensure-TestConfig -RepoPath $RepoPath
  if (Test-Path $paths.LogPath) {
    Remove-Item -LiteralPath $paths.LogPath -Force
  }

  $process = $null
  try {
    $process = Start-Process -FilePath $ExecutablePath -WorkingDirectory $RepoPath -ArgumentList @(
      '--config',
      $config,
      '--mod-directory',
      $paths.ModRoot,
      '--disable-audio',
      '--start-server-load-scenario',
      'base/freeplay'
    ) -PassThru

    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $deadline) {
      Start-Sleep -Milliseconds 250

      if (Test-Path $paths.LogPath) {
        $logText = Get-Content -Path $paths.LogPath -Raw
        if ($logText -match 'Error ') {
          throw 'Factorio startup smoke test logged an error.'
        }

        if ($logText -match 'changing state from\(CreatingGame\) to\(InGame\)') {
          Write-Output 'factorio startup smoke ok'
          return
        }
      }

      if ($process.HasExited) {
        throw ('Factorio exited before reaching InGame with exit code ' + $process.ExitCode)
      }
    }

    throw 'Factorio startup smoke test timed out before reaching InGame.'
  }
  finally {
    if ($process -and -not $process.HasExited) {
      Stop-Process -Id $process.Id -Force
    }
  }
}

$repoPath = Get-RepoPath

switch ($Action) {
  'sync' {
    Sync-TestModFiles -RepoPath $repoPath | Out-Null
    Write-Output 'factorio test mod sync ok'
  }
  'start' {
    $factorioPath = Get-ValidatedFactorioExe -PathValue $FactorioExe
    Start-LocalFactorio -RepoPath $repoPath -ExecutablePath $factorioPath
  }
  'smoke' {
    $factorioPath = Get-ValidatedFactorioExe -PathValue $FactorioExe
    Invoke-StartupSmokeTest -RepoPath $repoPath -ExecutablePath $factorioPath
  }
}
