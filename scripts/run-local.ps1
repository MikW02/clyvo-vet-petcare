# Windows / PowerShell equivalent of run-local.sh
# Spins up the full Clyvo-vet PetCare stack locally using plain `docker` commands.

$ErrorActionPreference = 'Stop'

$Network      = 'clyvo-net'
$Volume       = 'clyvo-oracle-data'
$DbContainer  = 'clyvo-oracle'
$AppContainer = 'clyvo-petcare'

# Carrega .env.local se existir (ignorado pelo git) — copie de .env.sample
$EnvFile = Join-Path (Split-Path -Parent $PSScriptRoot) '.env.local'
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | Where-Object { $_ -match '^[^#].+=' } | ForEach-Object {
        $k,$v = $_ -split '=',2
        Set-Item "env:$($k.Trim())" $v.Trim()
    }
}

if (-not $env:ORACLE_PASSWORD)    { throw 'Defina ORACLE_PASSWORD (copie .env.sample para .env.local e edite)' }
if (-not $env:APP_USER_PASSWORD)  { throw 'Defina APP_USER_PASSWORD' }
$OraclePassword     = $env:ORACLE_PASSWORD
$AppUser            = if ($env:APP_USER) { $env:APP_USER } else { 'clyvo' }
$AppUserPassword    = $env:APP_USER_PASSWORD

$RootDir = Split-Path -Parent $PSScriptRoot
if (-not $RootDir) { $RootDir = Resolve-Path (Join-Path $PSScriptRoot '..') }

Write-Host '==> Ensuring docker network and named volume exist'
docker network inspect $Network *> $null; if (-not $?) { docker network create $Network | Out-Null }
docker volume  inspect $Volume  *> $null; if (-not $?) { docker volume  create $Volume  | Out-Null }

Write-Host '==> Removing previous containers (if any)'
docker rm -f $AppContainer $DbContainer *> $null

Write-Host '==> Building Oracle image'
docker build -t clyvo/oracle:local (Join-Path $RootDir 'oracle')
if (-not $?) { throw 'Oracle image build failed' }

Write-Host '==> Starting Oracle container (named volume persists /opt/oracle/oradata)'
docker run -d `
    --name $DbContainer `
    --network $Network `
    -p 1521:1521 `
    --shm-size=2g `
    -e ORACLE_PASSWORD=$OraclePassword `
    -e APP_USER=$AppUser `
    -e APP_USER_PASSWORD=$AppUserPassword `
    -v "$($Volume):/opt/oracle/oradata" `
    clyvo/oracle:local | Out-Null

Write-Host '==> Waiting for Oracle to report healthy (this can take a couple minutes on first start)'
while ($true) {
    $status = (docker inspect -f '{{.State.Health.Status}}' $DbContainer 2>$null)
    if ($status -eq 'healthy') { break }
    Write-Host -NoNewline '.'
    Start-Sleep -Seconds 5
}
Write-Host ''

Write-Host '==> Building application image'
docker build -t clyvo/petcare:local (Join-Path $RootDir 'app')
if (-not $?) { throw 'App image build failed' }

Write-Host '==> Starting application container (non-root user inside the image)'
docker run -d `
    --name $AppContainer `
    --network $Network `
    -p 8080:8080 `
    -e DB_URL="jdbc:oracle:thin:@${DbContainer}:1521/XEPDB1" `
    -e DB_USER=$AppUser `
    -e DB_PASSWORD=$AppUserPassword `
    clyvo/petcare:local | Out-Null

Write-Host ''
Write-Host 'Stack is up:'
Write-Host '  API : http://localhost:8080/api/pets'
Write-Host "  DB  : localhost:1521  (service XEPDB1, user $AppUser)"
Write-Host ''
Write-Host "Tail logs with:  docker logs -f $AppContainer"
