# SPDX-License-Identifier: Apache-2.0
# Windows PowerShell 5.1 compatible. Never logs credentials or changes global policy.
[CmdletBinding()]
param(
    [ValidateSet('Start', 'Stop', 'Status')][string]$Action = 'Start',
    [ValidateRange(1024, 65535)][int]$Port = 8080
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$deploy = Join-Path $root 'deploy'
$envFile = Join-Path $deploy '.env.windows-local'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function New-LocalSecret {
    $bytes = New-Object byte[] 24
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

function Find-Docker {
    $cmd = Get-Command docker.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $paths = @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin\docker.exe')
    )
    foreach ($path in $paths) { if (Test-Path $path) { return $path } }
    return $null
}

function Get-DockerOS {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $value = & $script:docker info --format '{{.OSType}}' 2>$null
        if ($LASTEXITCODE -eq 0) { return $value }
        return $null
    } finally { $ErrorActionPreference = $previous }
}

function Ensure-Docker {
    $script:docker = Find-Docker
    if (-not $script:docker) {
        Write-Host 'Docker Desktop is missing. Opening the official installer.'
        Write-Host 'Complete its Windows dialogs. If a restart is required, restart and run Start-Local.cmd again.'
        $arch = 'amd64'
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { $arch = 'arm64' }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $installer = Join-Path ([IO.Path]::GetTempPath()) ('aicc-docker-' + [guid]::NewGuid().ToString('N') + '.exe')
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "https://desktop.docker.com/win/main/$arch/Docker%20Desktop%20Installer.exe" -OutFile $installer
            $signature = Get-AuthenticodeSignature -FilePath $installer
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Docker') {
                throw 'Docker installer signature verification failed. Installation was not started.'
            }
            $result = Start-Process -FilePath $installer -ArgumentList @('install', '--backend=wsl-2') -Wait -PassThru
            if ($result.ExitCode -in @(1641, 3010)) { throw 'Windows needs a restart. Restart, then run Start-Local.cmd again.' }
            if ($result.ExitCode -ne 0) { throw "Docker installer exited with code $($result.ExitCode). Run Start-Local.cmd after resolving it." }
        } finally { Remove-Item -LiteralPath $installer -ErrorAction SilentlyContinue }
        $script:docker = Find-Docker
        if (-not $script:docker) { throw 'Docker Desktop is not installed yet. Finish installation and run Start-Local.cmd again.' }
    }
    $os = Get-DockerOS
    if (-not $os) {
        $desktops = @(
            (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe')
        )
        foreach ($desktop in $desktops) {
            if (Test-Path $desktop) { Start-Process -FilePath $desktop; break }
        }
        Write-Host 'Waiting for Docker Desktop. Complete any first-run dialogs in its window.'
        $deadline = (Get-Date).AddMinutes(5)
        do {
            Start-Sleep -Seconds 3
            $os = Get-DockerOS
            if ($os) { break }
        } while ((Get-Date) -lt $deadline)
        if (-not $os) { throw 'Docker did not become ready. Open Docker Desktop, resolve its WSL/virtualization message, then run Start-Local.cmd again. WSL setup: https://learn.microsoft.com/windows/wsl/install' }
    }
    if ($os -ne 'linux') { throw 'Switch Docker Desktop to Linux containers, then run Start-Local.cmd again.' }
    $composeVersion = & $script:docker compose version --short
    if ($LASTEXITCODE -ne 0 -or $composeVersion -notmatch '(\d+)\.(\d+)\.(\d+)') { throw 'Docker Compose is missing. Update Docker Desktop.' }
    if ([version]$Matches[0] -lt [version]'2.24.4') { throw 'Docker Compose 2.24.4 or newer is required. Update Docker Desktop.' }
}

function Invoke-Stack {
    param([string[]]$CommandArgs)
    & $script:docker compose --project-name aicc-sales-local --project-directory $deploy --env-file $envFile -f (Join-Path $deploy 'docker-compose.yml') -f (Join-Path $deploy 'compose.windows-local.yml') @CommandArgs
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose failed (exit $LASTEXITCODE). Read the error above; no existing data was deleted." }
}

function Initialize-LocalEnvironment {
    if (Test-Path $envFile) {
        $values = Get-Content -LiteralPath $envFile -Raw | ConvertFrom-StringData
        if (-not $values.AICC_LOCAL_INSTALL -or -not $values.AICC_LOCAL_HTTP_PORT -or -not $values.AICC_SEED_PASSWORD) {
            throw 'Existing .env.windows-local is not an installer configuration. It was left unchanged.'
        }
        return $values
    }
    # Write atomically and refuse a competing installation rather than replacing it.
    $seedPassword = New-LocalSecret
    $lines = @(
        '# Generated for the isolated Windows browser demo.',
        'AICC_LOCAL_INSTALL=1',
        "AICC_LOCAL_HTTP_PORT=$Port",
        'FS_EXTERNAL_IP=127.0.0.1',
        'HTTP_BIND=127.0.0.1',
        'SIP_BIND=127.0.0.1',
        'AICC_SUBNET=10.131.0.0/24',
        'AICC_APP_IP=10.131.0.10',
        'AICC_BOT_ENABLED=false',
        'AICC_PROVIDER=qwen',
        'AICC_OUTBOUND_ENDPOINT=',
        'AICC_TRANSCRIPTION_ENABLED=false',
        'AICC_SEED=demo',
        'AICC_DEFAULT_COUNTRY_CODE=86',
        "POSTGRES_PASSWORD=$(New-LocalSecret)",
        "LUA_PASSWORD=$(New-LocalSecret)",
        "ESL_PASSWORD=$(New-LocalSecret)",
        "AICC_SEED_PASSWORD=$seedPassword"
    )
    $stream = [IO.File]::Open($envFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = $utf8.GetBytes(($lines -join "`n") + "`n")
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
    # Limit credential-file access to the current Windows account and SYSTEM.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($identity)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'Allow')))
    $system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($system, 'FullControl', 'Allow')))
    Set-Acl -LiteralPath $envFile -AclObject $acl
    return (($lines -join "`n") | ConvertFrom-StringData)
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'Run this launcher on your Windows computer.' }
    Write-Host 'AI sales workspace - local demo'
    Write-Host 'The database and browser app run locally. No carrier or paid AI API is connected.'
    Ensure-Docker
    # Compose inherits ambient variables ahead of --env-file. Do not let an
    # unrelated shell select a carrier, a different image, or topology.
    foreach ($item in @(Get-ChildItem Env:)) {
        if ($item.Name -match '^(AICC_|COMPOSE_|FS_|POSTGRES_PASSWORD$|LUA_PASSWORD$|ESL_PASSWORD$|HTTP_BIND$|HTTP_PORT$|SIP_|SWITCH_DOMAIN$|RTP_|BASE_IMAGE$|GOPROXY$|OPENAI_API_KEY$|XAI_API_KEY$|ALIYUN_API_KEY$|REALTIME_API_KEY$|DOUBAO_API_KEY$)') {
            [Environment]::SetEnvironmentVariable($item.Name, $null, 'Process')
        }
    }
    if ($Action -ne 'Start' -and -not (Test-Path $envFile)) { throw 'No local installation was found in this folder.' }
    $values = Initialize-LocalEnvironment
    if ($Action -eq 'Stop') { Invoke-Stack -CommandArgs @('stop'); Write-Host 'Stopped. Your local data is preserved.'; exit 0 }
    if ($Action -eq 'Status') { Invoke-Stack -CommandArgs @('ps', '-a'); exit 0 }
    Invoke-Stack -CommandArgs @('config', '--quiet')
    Write-Host 'Building your sales-workbench branch and starting PostgreSQL, FreeSWITCH, and the app.'
    Write-Host 'The first build downloads dependencies. Keep this window open.'
    Invoke-Stack -CommandArgs @('up', '-d', '--build')
    $base = "http://127.0.0.1:$($values.AICC_LOCAL_HTTP_PORT)"
    $deadline = (Get-Date).AddMinutes(3)
    $ready = $false
    $body = @{username='admin'; password=$values.AICC_SEED_PASSWORD} | ConvertTo-Json -Compress
    do {
        try {
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $login = Invoke-RestMethod -Uri "$base/api/v1/auth/login" -Method Post -ContentType 'application/json' -Body $body -WebSession $session -TimeoutSec 5
            if ($login.user.username -eq 'admin') {
                $health = Invoke-RestMethod -Uri "$base/api/v1/system/health" -WebSession $session -TimeoutSec 5
                $page = Invoke-WebRequest -UseBasicParsing -Uri $base -TimeoutSec 5
                if ($page.StatusCode -eq 200 -and $page.Content -match '<html') { $ready = $true; break }
            }
        } catch { }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    if (-not $ready) {
        Invoke-Stack -CommandArgs @('ps', '-a')
        throw 'The browser login check did not pass. Do not delete the folder. Open Docker Desktop > Containers > aicc-sales-local > aicc to view its logs.'
    }
    Invoke-Stack -CommandArgs @('ps', '-a')
    Write-Host "`nVerified browser and administrator login: $base" -ForegroundColor Green
    Write-Host 'Username: admin'
    Write-Host "Password: $($values.AICC_SEED_PASSWORD)"
    Write-Host 'Keep this password private. It is also stored in deploy\.env.windows-local.'
    Write-Host 'To stop: double-click Stop-Local.cmd. To restart: double-click Start-Local.cmd.'
    Start-Process $base
} catch {
    Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
