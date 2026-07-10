<#
.SYNOPSIS
    Script maestro: lanza el pipeline WebODM en múltiples PCs en paralelo.
    Correr desde el PC maestro. Cada PC procesa sus propias fotos locales.

.NOTES
    Requiere que cada PC trabajador haya ejecutado habilitar_worker.ps1 primero.
    Uso: .\lanzar_todos.ps1 [-Config config_maestro.json] [-Preset "Fast Orthophoto"]
#>

param(
    [string]$Config  = "config_maestro.json",
    [string]$Preset  = $null
)

$ErrorActionPreference = "Stop"

function Log  { param($m) Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $m" -ForegroundColor Cyan }
function OK   { param($m) Write-Host "[OK]  $m" -ForegroundColor Green }
function WARN { param($m) Write-Host "[!]   $m" -ForegroundColor Yellow }

# ── Leer configuración maestra ─────────────────────────────────────────────
if (-not (Test-Path $Config)) { Write-Error "No se encontró: $Config" }
$cfg    = Get-Content $Config -Raw | ConvertFrom-Json
$preset = if ($Preset) { $Preset } else { $cfg.preset }

Log "=== Lanzador WebODM Multi-PC ==="
Log "Preset: $preset"
Log "PCs configurados: $($cfg.pcs.Count)"

# ── Lanzar jobs en paralelo ────────────────────────────────────────────────
$jobs = @()

foreach ($pc in $cfg.pcs) {

    if ($pc.ip -eq "localhost") {
        # ── PC Maestro: ejecutar localmente ──────────────────────────────
        Log "[$($pc.nombre)] Lanzando localmente..."
        $job = Start-Job -Name $pc.nombre -ScriptBlock {
            param($pipeline, $config, $images, $preset)
            & python $pipeline --config $config --preset $preset --images $images --no-wait
        } -ArgumentList $pc.pipeline, $pc.config, $pc.images_dir, $preset

    } else {
        # ── PC Trabajador: ejecutar remotamente via WinRM ─────────────────
        Log "[$($pc.nombre)] Conectando a $($pc.ip)..."
        $secPass = ConvertTo-SecureString $pc.password -AsPlainText -Force
        $cred    = New-Object System.Management.Automation.PSCredential($pc.usuario, $secPass)

        $job = Invoke-Command `
            -ComputerName $pc.ip `
            -Credential $cred `
            -AsJob `
            -JobName $pc.nombre `
            -ScriptBlock {
                param($pipeline, $config, $images, $preset)
                & python $pipeline --config $config --preset $preset --images $images --no-wait
            } -ArgumentList $pc.pipeline, $pc.config, $pc.images_dir, $preset
    }

    $jobs += [PSCustomObject]@{ Job = $job; Nombre = $pc.nombre; IP = $pc.ip }
    OK "[$($pc.nombre)] Job lanzado (ID: $($job.Id))"
}

# ── Monitorear hasta que todos terminen ────────────────────────────────────
Log ""
Log "Esperando que todos los PCs inicien el procesamiento..."

$pendientes = $jobs.Count
while ($pendientes -gt 0) {
    Start-Sleep -Seconds 5
    $pendientes = 0
    foreach ($entry in $jobs) {
        $estado = $entry.Job.State
        if ($estado -in @("Running", "NotStarted")) {
            $pendientes++
        }
    }
    $completados = $jobs.Count - $pendientes
    Write-Host "  Completados: $completados / $($jobs.Count)" -NoNewline
    Write-Host "`r" -NoNewline
}

# ── Mostrar resultados ─────────────────────────────────────────────────────
Write-Host ""
Log "=== Resultados ==="
foreach ($entry in $jobs) {
    $estado = $entry.Job.State
    $color  = if ($estado -eq "Completed") { "Green" } else { "Red" }
    Write-Host "  [$($entry.Nombre) - $($entry.IP)] $estado" -ForegroundColor $color

    if ($estado -eq "Failed") {
        $entry.Job | Receive-Job -ErrorAction SilentlyContinue | Write-Host
    } else {
        $entry.Job | Receive-Job | Write-Host
    }
}

OK "Todos los jobs procesados. Revisar WebODM en cada PC para ver el progreso."
