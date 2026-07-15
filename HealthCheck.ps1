# =====================================================
# HealthCheck Local - Reporte visual HTML/PDF
# Version con config.json + CSS externo + credencial segura
# Hecho por: JowelGod
# =====================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# =========================
# RUTAS BASE
# =========================

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
    $ScriptRoot = "C:\Scripts\HealthCheck"
}

$ConfigPath = Join-Path $ScriptRoot "config.json"
$CssPath    = Join-Path $ScriptRoot "templates\report-style.css"

if (!(Test-Path $ConfigPath)) {
    throw "No se encontro el archivo de configuracion: $ConfigPath"
}

$Config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-ConfigValue {
    param(
        $Value,
        $Default
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace("$Value")) {
        return $Default
    }

    return $Value
}

# =========================
# CONFIG GENERAL
# =========================

$Fecha = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$BaseOutputFolder = Get-ConfigValue $Config.General.OutputFolder "C:\Scripts\HealthCheck\reports"

$HtmlFolder = Join-Path $BaseOutputFolder "html"
$PdfFolder  = Join-Path $BaseOutputFolder "pdf"
$LogFolder  = Join-Path $BaseOutputFolder "logs"
$JsonFolder = Join-Path $BaseOutputFolder "json"

@($BaseOutputFolder, $HtmlFolder, $PdfFolder, $LogFolder, $JsonFolder) | ForEach-Object {
    if (!(Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

$HtmlPath = Join-Path $HtmlFolder "HealthCheck_$env:COMPUTERNAME`_$Fecha.html"
$PdfPath  = Join-Path $PdfFolder  "HealthCheck_$env:COMPUTERNAME`_$Fecha.pdf"
$LogPath  = Join-Path $LogFolder  "HealthCheck_$env:COMPUTERNAME`_$Fecha.log"
$JsonPath = Join-Path $JsonFolder "HealthCheck_$env:COMPUTERNAME`_$Fecha.json"

$Environment = Get-ConfigValue $Config.General.Environment "No definido"
$Client      = Get-ConfigValue $Config.General.Client "General"
$ServerType  = Get-ConfigValue $Config.General.ServerType "General"
$KeepReportsDays = Get-ConfigValue $Config.General.KeepReportsDays 30

# =========================
# FUNCIONES BASE
# =========================

function Write-Log {
    param([string]$Message)

    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $LogPath -Value $Line -Encoding UTF8
}

function Invoke-SafeCommand {    param(
        [string]$Name,
        [scriptblock]$Action
    )

    try {
        & $Action
    }
    catch {
        Write-Log "ERROR en $Name : $($_.Exception.Message)"
        return "ERROR: $($_.Exception.Message)"
    }
}

function HtmlEncode {
    param($Value)

    if ($null -eq $Value) {
        return ""
    }

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-StatusClass {
    param([string]$Status)

    switch ($Status) {
        "OK"       { return "status-ok" }
        "REVISAR"  { return "status-review" }
        "ALERTA"   { return "status-alert" }
        "CRITICO"  { return "status-critical" }
        default    { return "status-unknown" }
    }
}

function Get-BadgeHtml {
    param([string]$Status)

    $Class = switch ($Status) {
        "OK"       { "badge badge-ok" }
        "REVISAR"  { "badge badge-review" }
        "ALERTA"   { "badge badge-alert" }
        "CRITICO"  { "badge badge-critical" }
        "Running"  { "badge badge-ok" }
        "Stopped"  { "badge badge-alert" }
        "Abierto"  { "badge badge-ok" }
        "Cerrado"  { "badge badge-alert" }
        default    { "badge badge-neutral" }
    }

    return "<span class='$Class'>$(HtmlEncode $Status)</span>"
}

function Get-PercentBarHtml {
    param(
        $Percent,
        [string]$Status
    )

    if ($Percent -isnot [int] -and $Percent -isnot [double] -and $Percent -isnot [decimal]) {
        return "<span class='muted'>No disponible</span>"
    }

    $SafePercent = [math]::Max(0, [math]::Min(100, [double]$Percent))

    $BarClass = switch ($Status) {
        "OK"       { "bar-fill ok-fill" }
        "REVISAR"  { "bar-fill review-fill" }
        "ALERTA"   { "bar-fill alert-fill" }
        "CRITICO"  { "bar-fill critical-fill" }
        default    { "bar-fill neutral-fill" }
    }

    return "<div class='bar'><div class='$BarClass' style='width:$SafePercent%'></div></div>"
}

function Get-MetricStatus {
    param(
        $Value,
        [double]$Warning,
        [double]$Critical,
        [switch]$Reverse
    )

    if ($Value -isnot [int] -and $Value -isnot [double] -and $Value -isnot [decimal]) {
        return "REVISAR"
    }

    if ($Reverse) {
        if ($Value -le $Critical) { return "CRITICO" }
        if ($Value -le $Warning)  { return "ALERTA" }
        return "OK"
    }
    else {
        if ($Value -ge $Critical) { return "CRITICO" }
        if ($Value -ge $Warning)  { return "ALERTA" }
        return "OK"
    }
}

function New-Finding {
    param(
        [string]$Severity,
        [string]$Title,
        [string]$Detail,
        [string]$Recommendation
    )

    return [PSCustomObject]@{
        Severity = $Severity
        Title = $Title
        Detail = $Detail
        Recommendation = $Recommendation
    }
}

function Convert-FindingsToHtml {
    param($Findings)

    if ($null -eq $Findings -or $Findings.Count -eq 0) {
        return "<div class='empty-state'>No se detectaron hallazgos relevantes durante la ejecucion.</div>"
    }

    $Rows = $Findings | ForEach-Object {
        $Badge = Get-BadgeHtml $_.Severity
        "<tr><td>$Badge</td><td><strong>$(HtmlEncode $_.Title)</strong><br><span class='muted'>$(HtmlEncode $_.Detail)</span></td><td>$(HtmlEncode $_.Recommendation)</td></tr>"
    }

    return @"
<table>
<thead>
<tr>
<th>Severidad</th>
<th>Hallazgo</th>
<th>Recomendacion</th>
</tr>
</thead>
<tbody>
$($Rows -join "`n")
</tbody>
</table>
"@
}

function Remove-OldReports {
    param(
        [string]$Folder,
        [int]$Days
    )

    if (!(Test-Path $Folder)) {
        return
    }

    try {
        Get-ChildItem -Path $Folder -File -ErrorAction Stop |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Days) } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        Write-Log "Limpieza aplicada en $Folder. Retencion: $Days dias."
    }
    catch {
        Write-Log "ERROR limpieza de reportes en $Folder : $($_.Exception.Message)"
    }
}

Write-Log "Inicio Health Check"

# =========================
# CONFIG UMBRALES
# =========================

$CpuWarning = [double](Get-ConfigValue $Config.Thresholds.CpuWarning 70)
$CpuCritical = [double](Get-ConfigValue $Config.Thresholds.CpuCritical 90)

$RamWarning = [double](Get-ConfigValue $Config.Thresholds.RamWarning 80)
$RamCritical = [double](Get-ConfigValue $Config.Thresholds.RamCritical 90)

$DiskWarningFreePercent = [double](Get-ConfigValue $Config.Thresholds.DiskWarningFreePercent 20)
$DiskCriticalFreePercent = [double](Get-ConfigValue $Config.Thresholds.DiskCriticalFreePercent 10)

$Findings = @()

# =========================
# SISTEMA
# =========================

$OS = Invoke-SafeCommand "Sistema Operativo" {    
    Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
}

<<<<<<< HEAD
$ComputerSystem = Invoke-SafeCommand "ComputerSystem" {
=======
$ComputerSystem = Safe-Run "ComputerSystem" {
>>>>>>> origin/main
    Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
}

if ($ComputerSystem -isnot [string]) {
    $Manufacturer = $ComputerSystem.Manufacturer
    $Model = $ComputerSystem.Model
}
else {
    $Manufacturer = "No disponible"
    $Model = "No disponible"
}

if ($OS -isnot [string]) {
    $LastBoot = $OS.LastBootUpTime
    $Uptime = New-TimeSpan -Start $OS.LastBootUpTime -End (Get-Date)
    $UptimeText = "$($Uptime.Days) dias, $($Uptime.Hours) horas, $($Uptime.Minutes) minutos"
    $OsCaption = $OS.Caption
    $OsVersion = $OS.Version
}
else {
    $LastBoot = "No disponible"
    $UptimeText = "No disponible"
    $OsCaption = "No disponible"
    $OsVersion = "No disponible"

    $Findings += New-Finding "REVISAR" "Sistema operativo no disponible" "No fue posible obtener informacion del sistema operativo." "Validar permisos del usuario que ejecuta el script."
}

# =========================
# CPU
# =========================

<<<<<<< HEAD
$CpuUsage = Invoke-SafeCommand "CPU" {
=======
$CpuUsage = Safe-Run "CPU" {
>>>>>>> origin/main
    $CpuData = Get-CimInstance Win32_Processor -ErrorAction Stop |
        Measure-Object -Property LoadPercentage -Average

    if ($null -ne $CpuData.Average) {
        [math]::Round($CpuData.Average, 2)
    }
    else {
        "No disponible"
    }
}

$CpuStatus = Get-MetricStatus -Value $CpuUsage -Warning $CpuWarning -Critical $CpuCritical

<<<<<<< HEAD
$CpuDetailRaw = Invoke-SafeCommand "CPU Detalle" {
=======
$CpuDetailRaw = Safe-Run "CPU Detalle" {
>>>>>>> origin/main
    Get-CimInstance Win32_Processor -ErrorAction Stop
}

if ($CpuDetailRaw -is [string]) {

    $CpuDetailHtml = "<div class='empty-state'>No fue posible obtener detalle de CPU. Detalle: $(HtmlEncode $CpuDetailRaw)</div>"

}
else {

    $CpuDetail = @($CpuDetailRaw)

    $CpuRows = $CpuDetail | ForEach-Object {

        "<tr>
            <td>$(HtmlEncode $_.Name)</td>
            <td>$(HtmlEncode $_.SocketDesignation)</td>
            <td>$($_.NumberOfCores)</td>
            <td>$($_.NumberOfLogicalProcessors)</td>
            <td>$($_.MaxClockSpeed) MHz</td>
            <td>$($_.LoadPercentage)%</td>
        </tr>"
    }

    $CpuDetailHtml = @"
<table>
<thead>
<tr>
<th>Procesador</th>
<th>Socket</th>
<th>Nucleos</th>
<th>Procesadores logicos</th>
<th>Velocidad Max.</th>
<th>Carga actual</th>
</tr>
</thead>
<tbody>
$($CpuRows -join "`n")
</tbody>
</table>
"@
}

if ($CpuStatus -in @("ALERTA", "CRITICO")) {
    $Findings += New-Finding $CpuStatus "Uso elevado de CPU" "CPU actual: $CpuUsage%. Umbral alerta: $CpuWarning%. Umbral critico: $CpuCritical%." "Revisar procesos con mayor consumo y validar si coincide con carga operativa esperada."
}

# =========================
# RAM
# =========================

if ($OS -isnot [string]) {
    $RamUsage = [math]::Round((($OS.TotalVisibleMemorySize - $OS.FreePhysicalMemory) / $OS.TotalVisibleMemorySize) * 100, 2)
    $RamTotalGB = [math]::Round($OS.TotalVisibleMemorySize / 1MB, 2)
    $RamFreeGB = [math]::Round($OS.FreePhysicalMemory / 1MB, 2)
}
else {
    $RamUsage = "No disponible"
    $RamTotalGB = "No disponible"
    $RamFreeGB = "No disponible"
}

$RamStatus = Get-MetricStatus -Value $RamUsage -Warning $RamWarning -Critical $RamCritical

if ($RamStatus -in @("ALERTA", "CRITICO")) {
    $Findings += New-Finding $RamStatus "Uso elevado de memoria RAM" "RAM actual: $RamUsage%. Libre: $RamFreeGB GB de $RamTotalGB GB." "Revisar procesos activos, consumo de aplicaciones y posibles reinicios programados si aplica."
}

# =========================
# PROCESOS TOP
# =========================

<<<<<<< HEAD
$TopProcesses = Invoke-SafeCommand "Procesos principales" {
=======
$TopProcesses = Safe-Run "Procesos principales" {
>>>>>>> origin/main
    Get-Process -ErrorAction Stop |
        Sort-Object -Property CPU -Descending |
        Select-Object -First 8 Name, Id, CPU, WorkingSet64
}

if ($TopProcesses -isnot [string] -and $TopProcesses.Count -gt 0) {
    $TopProcessesRows = $TopProcesses | ForEach-Object {
        $CpuValue = if ($null -ne $_.CPU) { [math]::Round($_.CPU, 2) } else { 0 }
        $RamMB = [math]::Round($_.WorkingSet64 / 1MB, 2)

        "<tr><td>$(HtmlEncode $_.Name)</td><td>$(HtmlEncode $_.Id)</td><td>$CpuValue</td><td>$RamMB MB</td></tr>"
    }

    $TopProcessesHtml = @"
<table>
<thead>
<tr>
<th>Proceso</th>
<th>PID</th>
<th>CPU acumulado</th>
<th>RAM</th>
</tr>
</thead>
<tbody>
$($TopProcessesRows -join "`n")
</tbody>
</table>
"@
}
else {
    $TopProcessesHtml = "<div class='empty-state'>No disponible</div>"
}

# =========================
# DISCOS
# =========================

<<<<<<< HEAD
$DisksRaw = Invoke-SafeCommand "Discos" {
=======
$DisksRaw = Safe-Run "Discos" {
>>>>>>> origin/main
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop |
        Where-Object { $_.Size -ne $null -and $_.Size -gt 0 }
}

$DiskObjects = @()
$WorstDiskStatus = "OK"

if ($DisksRaw -is [string]) {

    $WorstDiskStatus = "REVISAR"
    $DisksHtml = "<div class='empty-state'>No fue posible obtener informacion de discos. Detalle: $(HtmlEncode $DisksRaw)</div>"
    $DiskSummaryHtml = "<div class='mini-empty'>No disponible</div>"
    $Findings += New-Finding `
        "REVISAR" `
        "Discos no disponibles" `
        "No fue posible obtener informacion de discos locales. Detalle: $DisksRaw" `
        "Validar permisos del usuario, WMI/CIM o ejecucion del Task Scheduler."

}
else {

    $Disks = @($DisksRaw)

    if ($Disks.Count -gt 0) {

        $DiskObjects = $Disks | ForEach-Object {

            $SizeGB = [math]::Round($_.Size / 1GB, 2)
            $FreeGB = [math]::Round($_.FreeSpace / 1GB, 2)
            $UsedGB = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
            $FreePercent = [math]::Round(($_.FreeSpace / $_.Size) * 100, 2)
            $UsedPercent = [math]::Round(100 - $FreePercent, 2)

            $Status = Get-MetricStatus `
                -Value $FreePercent `
                -Warning $DiskWarningFreePercent `
                -Critical $DiskCriticalFreePercent `
                -Reverse

            if ($Status -eq "CRITICO") {
                $WorstDiskStatus = "CRITICO"
            }
            elseif ($Status -eq "ALERTA" -and $WorstDiskStatus -ne "CRITICO") {
                $WorstDiskStatus = "ALERTA"
            }

            if ($Status -in @("ALERTA", "CRITICO")) {
                $Findings += New-Finding `
                    $Status `
                    "Espacio en disco bajo" `
                    "Unidad $($_.DeviceID) con $FreePercent% libre ($FreeGB GB disponibles de $SizeGB GB)." `
                    "Liberar espacio, revisar logs historicos, temporales, backups o crecimiento anormal de archivos."
            }

            [PSCustomObject]@{
                Drive = $_.DeviceID
                VolumeName = $_.VolumeName
                FileSystem = $_.FileSystem
                SizeGB = $SizeGB
                UsedGB = $UsedGB
                FreeGB = $FreeGB
                UsedPercent = $UsedPercent
                FreePercent = $FreePercent
                Status = $Status
            }
        }

        $DiskRows = $DiskObjects | ForEach-Object {

            $Badge = Get-BadgeHtml $_.Status
            $Bar = Get-PercentBarHtml -Percent $_.UsedPercent -Status $_.Status

            "<tr>
                <td>$(HtmlEncode $_.Drive)</td>
                <td>$(HtmlEncode $_.VolumeName)</td>
                <td>$(HtmlEncode $_.FileSystem)</td>
                <td>$($_.SizeGB) GB</td>
                <td>$($_.UsedGB) GB</td>
                <td>$($_.FreeGB) GB</td>
                <td>$($_.FreePercent)% libre $Bar</td>
                <td>$Badge</td>
            </tr>"
        }

        $DisksHtml = @"
<table>
<thead>
<tr>
<th>Unidad</th>
<th>Etiqueta</th>
<th>Sistema</th>
<th>Total</th>
<th>Usado</th>
<th>Libre</th>
<th>% Libre</th>
<th>Estado</th>
</tr>
</thead>
<tbody>
$($DiskRows -join "`n")
</tbody>
</table>
"@

        # Resumen visual de discos para tarjeta superior
        $DiskSummaryItems = $DiskObjects | ForEach-Object {

            $Bar = Get-PercentBarHtml -Percent $_.UsedPercent -Status $_.Status
            $Badge = Get-BadgeHtml $_.Status

    @"
    <div class='mini-disk-item'>
        <div class='mini-disk-header'>
            <strong>$(HtmlEncode $_.Drive)</strong>
            <span>$($_.FreePercent)% libre</span>
        </div>
        $Bar
        <div class='mini-disk-footer'>
            $($_.FreeGB) GB libres de $($_.SizeGB) GB $Badge
        </div>
    </div>
"@
}

$DiskSummaryHtml = $DiskSummaryItems -join "`n"
    }
    else {

        $WorstDiskStatus = "REVISAR"
        $DisksHtml = "<div class='empty-state'>No se encontraron discos locales validos con tamaño mayor a 0.</div>"
        $DiskSummaryHtml = "<div class='mini-empty'>No disponible</div>"
        $Findings += New-Finding `
            "REVISAR" `
            "Discos no encontrados" `
            "La consulta se ejecuto correctamente, pero no devolvio discos locales validos." `
            "Validar tipo de volumen, permisos, WMI/CIM o filtros aplicados."
    }
}

# =========================
# IIS
# =========================

$IISStatus = "No disponible"
$SitesHtml = "<div class='empty-state'>No disponible</div>"
$PoolsHtml = "<div class='empty-state'>No disponible</div>"

try {
    Import-Module WebAdministration -ErrorAction Stop

    $AllSites = @(Get-Website)
    $AllAppPools = @(Get-ChildItem IIS:\AppPools)

    # Configuracion IIS desde config.json
    $CheckAllSites = $true
    $SitesToCheck = @()

    $CheckAllAppPools = $true
    $AppPoolsToCheck = @()

    if ($null -ne $Config.IIS.CheckAllSites) {
        $CheckAllSites = [bool]$Config.IIS.CheckAllSites
    }

    if ($null -ne $Config.IIS.SitesToCheck) {
        $SitesToCheck = @($Config.IIS.SitesToCheck)
    }

    if ($null -ne $Config.IIS.CheckAllAppPools) {
        $CheckAllAppPools = [bool]$Config.IIS.CheckAllAppPools
    }

    if ($null -ne $Config.IIS.AppPoolsToCheck) {
        $AppPoolsToCheck = @($Config.IIS.AppPoolsToCheck)
    }

    # Filtrar sitios
    if ($CheckAllSites) {
        $Sites = $AllSites
    }
    else {
        $Sites = @($AllSites | Where-Object { $SitesToCheck -contains $_.Name })
    }

    # Filtrar AppPools
    if ($CheckAllAppPools) {
        $AppPools = $AllAppPools
    }
    else {
        $AppPools = @($AllAppPools | Where-Object { $AppPoolsToCheck -contains $_.Name })
    }

    # Detectar sitios configurados que no existen
    if (-not $CheckAllSites) {
        foreach ($ExpectedSite in $SitesToCheck) {
            if (-not ($AllSites | Where-Object { $_.Name -eq $ExpectedSite })) {
                $Findings += New-Finding `
                    "REVISAR" `
                    "Sitio IIS no encontrado" `
                    "El sitio '$ExpectedSite' esta configurado para validacion, pero no existe en IIS." `
                    "Validar el nombre exacto del sitio en IIS o ajustar el config.json."
            }
        }
    }

    # Detectar AppPools configurados que no existen
    if (-not $CheckAllAppPools) {
        foreach ($ExpectedPool in $AppPoolsToCheck) {
            if (-not ($AllAppPools | Where-Object { $_.Name -eq $ExpectedPool })) {
                $Findings += New-Finding `
                    "REVISAR" `
                    "Application Pool no encontrado" `
                    "El AppPool '$ExpectedPool' esta configurado para validacion, pero no existe en IIS." `
                    "Validar el nombre exacto del AppPool en IIS o ajustar el config.json."
            }
        }
    }

    # HTML sitios
    if ($Sites.Count -gt 0) {
        $SiteRows = $Sites | ForEach-Object {
            $Status = "$($_.State)"
            $Badge = Get-BadgeHtml $Status

            if ($Status -ne "Started") {
                $Findings += New-Finding `
                    "ALERTA" `
                    "Sitio IIS no iniciado" `
                    "El sitio '$($_.Name)' se encuentra en estado $Status." `
                    "Validar si el sitio debe estar activo para este servidor."
            }

            "<tr>
                <td>$(HtmlEncode $_.Name)</td>
                <td>$Badge</td>
                <td>$(HtmlEncode $_.PhysicalPath)</td>
                <td>$(HtmlEncode $_.Bindings.Collection.bindingInformation)</td>
            </tr>"
        }

        $SitesHtml = @"
<table>
<thead>
<tr>
<th>Sitio</th>
<th>Estado</th>
<th>Ruta</th>
<th>Bindings</th>
</tr>
</thead>
<tbody>
$($SiteRows -join "`n")
</tbody>
</table>
"@
    }
    else {
        if ($CheckAllSites) {
            $SitesHtml = "<div class='empty-state'>No se encontraron sitios IIS.</div>"
        }
        else {
            $SitesHtml = "<div class='empty-state'>No se encontraron sitios IIS que coincidan con la configuracion actual.</div>"
        }
    }

    # HTML AppPools
    if ($AppPools.Count -gt 0) {
        $PoolRows = $AppPools | ForEach-Object {
            $Status = "$($_.State)"
            $Badge = Get-BadgeHtml $Status

            if ($Status -ne "Started") {
                $Findings += New-Finding `
                    "ALERTA" `
                    "Application Pool no iniciado" `
                    "El AppPool '$($_.Name)' se encuentra en estado $Status." `
                    "Validar si el AppPool debe estar activo y revisar eventos asociados."
            }

            "<tr>
                <td>$(HtmlEncode $_.Name)</td>
                <td>$Badge</td>
                <td>$(HtmlEncode $_.managedRuntimeVersion)</td>
                <td>$(HtmlEncode $_.managedPipelineMode)</td>
            </tr>"
        }

        $PoolsHtml = @"
<table>
<thead>
<tr>
<th>Application Pool</th>
<th>Estado</th>
<th>.NET Runtime</th>
<th>Pipeline</th>
</tr>
</thead>
<tbody>
$($PoolRows -join "`n")
</tbody>
</table>
"@
    }
    else {
        if ($CheckAllAppPools) {
            $PoolsHtml = "<div class='empty-state'>No se encontraron Application Pools.</div>"
        }
        else {
            $PoolsHtml = "<div class='empty-state'>No se encontraron AppPools que coincidan con la configuracion actual.</div>"
        }
    }

    $IISStatus = "OK"
}
catch {
    $IISStatus = "REVISAR"
    $SitesHtml = "<div class='empty-state'>$(HtmlEncode $_.Exception.Message)</div>"
    $PoolsHtml = "<div class='empty-state'>$(HtmlEncode $_.Exception.Message)</div>"

    Write-Log "ERROR IIS: $($_.Exception.Message)"

    if ($ServerType -match "Web|App|IIS") {
        $Findings += New-Finding `
            "ALERTA" `
            "IIS no disponible" `
            "No fue posible consultar IIS: $($_.Exception.Message)" `
            "Validar si IIS esta instalado y si el usuario tiene permisos suficientes."
    }
}

# =========================
# SERVICIOS
# =========================

$ServicesToCheck = @($Config.Services)
if ($ServicesToCheck.Count -eq 0) {
    $ServicesToCheck = @("W3SVC", "WAS", "MSSQLSERVER", "SQLSERVERAGENT", "Schedule", "WinRM")
}

$ServiceObjects = $ServicesToCheck | ForEach-Object {
    $ServiceName = "$_"
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($svc) {
        $Status = "$($svc.Status)"

        if ($Status -ne "Running") {
            $Findings += New-Finding "ALERTA" "Servicio detenido" "El servicio $ServiceName se encuentra en estado $Status." "Validar si el servicio es requerido para este servidor y reiniciarlo si aplica."
        }

        [PSCustomObject]@{
            Name = $ServiceName
            DisplayName = $svc.DisplayName
            Status = $Status
        }
    }
    else {
        $Findings += New-Finding "REVISAR" "Servicio no encontrado" "El servicio $ServiceName no existe en este servidor." "Confirmar si el servicio aplica para el tipo de servidor configurado."

        [PSCustomObject]@{
            Name = $ServiceName
            DisplayName = "No encontrado"
            Status = "No encontrado"
        }
    }
}

$ServiceRows = $ServiceObjects | ForEach-Object {
    $Badge = Get-BadgeHtml $_.Status
    "<tr><td>$(HtmlEncode $_.Name)</td><td>$(HtmlEncode $_.DisplayName)</td><td>$Badge</td></tr>"
}

$ServicesHtml = @"
<table>
<thead>
<tr>
<th>Servicio</th>
<th>Nombre descriptivo</th>
<th>Estado</th>
</tr>
</thead>
<tbody>
$($ServiceRows -join "`n")
</tbody>
</table>
"@

# =========================
# TAREAS PROGRAMADAS
# =========================

<<<<<<< HEAD
$ScheduledTasksStatus = Invoke-SafeCommand "Tareas programadas" {

    $TaskMode = "ConfiguredOnly" #ConfiguredOnly/All
=======
$ScheduledTasksStatus = Safe-Run "Tareas programadas" {

    $TaskMode = "ConfiguredOnly"
>>>>>>> origin/main
    $IncludePaths = @()
    $IncludeTaskNames = @()
    $MaxTaskResults = 50

    if ($null -ne $Config.ScheduledTasks.Mode) {
        $TaskMode = $Config.ScheduledTasks.Mode
    }

    if ($null -ne $Config.ScheduledTasks.IncludePaths) {
        $IncludePaths = @($Config.ScheduledTasks.IncludePaths)
    }

    if ($null -ne $Config.ScheduledTasks.IncludeTaskNames) {
        $IncludeTaskNames = @($Config.ScheduledTasks.IncludeTaskNames)
    }

    if ($null -ne $Config.ScheduledTasks.MaxResults) {
        $MaxTaskResults = [int]$Config.ScheduledTasks.MaxResults
    }

    $AllTasks = Get-ScheduledTask -ErrorAction Stop |
        Where-Object { $_.State -ne "Disabled" }

    if ($TaskMode -eq "All") {
        $FilteredTasks = $AllTasks | Select-Object -First $MaxTaskResults
    }
    else {
        $FilteredTasks = $AllTasks | Where-Object {

            $TaskPathMatch = $false
            $TaskNameMatch = $false

            foreach ($Path in $IncludePaths) {
                if ($_.TaskPath -eq $Path -or $_.TaskPath -like "$Path*") {
                    $TaskPathMatch = $true
                }
            }

            foreach ($TaskName in $IncludeTaskNames) {
                if ($_.TaskName -eq $TaskName) {
                    $TaskNameMatch = $true
                }
            }

            $TaskPathMatch -or $TaskNameMatch
        } | Select-Object -First $MaxTaskResults
    }

    if (@($FilteredTasks).Count -eq 0) {
        return "<div class='empty-state'>No se encontraron tareas programadas relevantes con la configuracion actual.</div>"
    }

    $Rows = $FilteredTasks | ForEach-Object {

        $TaskName = $_.TaskName
        $TaskPath = $_.TaskPath
        $TaskState = "$($_.State)"

        try {
            $Info = Get-ScheduledTaskInfo `
                -TaskName $TaskName `
                -TaskPath $TaskPath `
                -ErrorAction Stop

            $LastResult = $Info.LastTaskResult
            $LastRun = $Info.LastRunTime
            $NextRun = $Info.NextRunTime
        }
        catch {
            $LastResult = "Info no disponible"
            $LastRun = "Info no disponible"
            $NextRun = "Info no disponible"
        }

        $Badge = Get-BadgeHtml $TaskState

        "<tr>
            <td>$(HtmlEncode $TaskPath)</td>
            <td>$(HtmlEncode $TaskName)</td>
            <td>$Badge</td>
            <td>$(HtmlEncode $LastResult)</td>
            <td>$(HtmlEncode $LastRun)</td>
            <td>$(HtmlEncode $NextRun)</td>
        </tr>"
    }

@"
<table>
<thead>
<tr>
<th>Ruta</th>
<th>Tarea</th>
<th>Estado</th>
<th>Ultimo resultado</th>
<th>Ultima ejecucion</th>
<th>Siguiente ejecucion</th>
</tr>
</thead>
<tbody>
$($Rows -join "`n")
</tbody>
</table>
"@
}

if ($ScheduledTasksStatus -is [string] -and $ScheduledTasksStatus.StartsWith("ERROR:")) {
    $Findings += New-Finding `
        "REVISAR" `
        "Tareas programadas no disponibles" `
        $ScheduledTasksStatus `
        "Validar permisos para consultar Task Scheduler."
}

# =========================
# URLS
# =========================

$UrlsToCheck = @($Config.Urls)

$UrlObjects = @()

if ($UrlsToCheck.Count -gt 0) {
    $UrlObjects = $UrlsToCheck | ForEach-Object {
        $Url = "$_"

        try {
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $Response = Invoke-WebRequest `
                -Uri $Url `
                -UseBasicParsing `
                -TimeoutSec 10 `
                -ErrorAction Stop

            $Stopwatch.Stop()

            [PSCustomObject]@{
                Url = $Url
                Status = "OK"
                HttpCode = $Response.StatusCode
                ResponseMs = $Stopwatch.ElapsedMilliseconds
                Message = "Disponible"
            }
        }
        catch {
            $Findings += New-Finding "CRITICO" "URL no disponible" "La URL $Url no respondio correctamente. Error: $($_.Exception.Message)" "Validar disponibilidad del aplicativo, IIS, DNS, certificados o conectividad."

            [PSCustomObject]@{
                Url = $Url
                Status = "ERROR"
                HttpCode = "N/A"
                ResponseMs = "N/A"
                Message = $_.Exception.Message
            }
        }
    }

    $UrlRows = $UrlObjects | ForEach-Object {
        $Badge = if ($_.Status -eq "OK") { Get-BadgeHtml "OK" } else { Get-BadgeHtml "CRITICO" }
        "<tr><td>$(HtmlEncode $_.Url)</td><td>$Badge</td><td>$(HtmlEncode $_.HttpCode)</td><td>$(HtmlEncode $_.ResponseMs) ms</td><td>$(HtmlEncode $_.Message)</td></tr>"
    }

    $UrlStatusHtml = @"
<table>
<thead>
<tr>
<th>URL</th>
<th>Estado</th>
<th>HTTP</th>
<th>Tiempo</th>
<th>Mensaje</th>
</tr>
</thead>
<tbody>
$($UrlRows -join "`n")
</tbody>
</table>
"@
}
else {
    $UrlStatusHtml = "<div class='empty-state'>No hay URLs configuradas.</div>"
}

# =========================
# EVENTOS
# =========================

<<<<<<< HEAD
$CriticalEvents = Invoke-SafeCommand "Eventos criticos" {
=======
$CriticalEvents = Safe-Run "Eventos criticos" {
>>>>>>> origin/main
    Get-WinEvent -FilterHashtable @{
        LogName = "System"
        Level = 1,2
        StartTime = (Get-Date).AddDays(-1)
    } -ErrorAction Stop |
    Select-Object -First 10
}

if ($CriticalEvents -isnot [string]) {
    $CriticalEventsCount = @($CriticalEvents).Count

    if ($CriticalEventsCount -gt 0) {
        $Findings += New-Finding "REVISAR" "Eventos criticos o errores recientes" "Se detectaron $CriticalEventsCount eventos de nivel critico/error en System durante las ultimas 24 horas." "Revisar el visor de eventos para identificar recurrencia, origen e impacto."

        $EventRows = $CriticalEvents | ForEach-Object {
            "<tr><td>$(HtmlEncode $_.TimeCreated)</td><td>$(HtmlEncode $_.Id)</td><td>$(HtmlEncode $_.ProviderName)</td><td>$(HtmlEncode $_.LevelDisplayName)</td></tr>"
        }

        $EventsHtml = @"
<table>
<thead>
<tr>
<th>Fecha</th>
<th>ID</th>
<th>Proveedor</th>
<th>Nivel</th>
</tr>
</thead>
<tbody>
$($EventRows -join "`n")
</tbody>
</table>
"@
    }
    else {
        $EventsHtml = "<div class='empty-state'>Sin eventos criticos o errores en las ultimas 24 horas.</div>"
    }
}
else {
    $CriticalEventsCount = "No disponible"
    $EventsHtml = "<div class='empty-state'>$(HtmlEncode $CriticalEvents)</div>"
    $Findings += New-Finding "REVISAR" "Eventos no disponibles" "No fue posible consultar eventos del sistema." "Validar permisos del usuario que ejecuta el script."
}

# =========================
# PUERTOS
# =========================

$PortsConfig = @($Config.Ports)

if ($PortsConfig.Count -eq 0) {
    $PortsConfig = @(
        [PSCustomObject]@{
            Port = 80
            Name = "HTTP"
            Description = "Puerto usado para trafico web sin cifrado."
        },
        [PSCustomObject]@{
            Port = 443
            Name = "HTTPS"
            Description = "Puerto usado para trafico web seguro mediante SSL/TLS."
        },
        [PSCustomObject]@{
            Port = 3389
            Name = "RDP"
            Description = "Puerto usado para conexion remota al servidor mediante Remote Desktop."
        },
        [PSCustomObject]@{
            Port = 1433
            Name = "SQL Server"
            Description = "Puerto comunmente usado por Microsoft SQL Server."
        }
    )
}

$PortObjects = $PortsConfig | ForEach-Object {

    if ($_.PSObject.Properties.Name -contains "Port") {
        $Port = [int]$_.Port
        $PortName = $_.Name
        $PortDescription = $_.Description
    }
    else {
        $Port = [int]$_
        $PortName = "Puerto $Port"
        $PortDescription = "Sin descripcion configurada."
    }

    try {
        $Result = Test-NetConnection `
            -ComputerName "127.0.0.1" `
            -Port $Port `
            -InformationLevel Quiet `
            -WarningAction SilentlyContinue 3>$null

        if ($Result) {
            [PSCustomObject]@{
                Port = $Port
                Name = $PortName
                Description = $PortDescription
                Status = "Abierto"
                Message = "Puerto disponible localmente"
            }
        }
        else {
            $Findings += New-Finding `
                "REVISAR" `
                "Puerto cerrado" `
                "El puerto $Port ($PortName) aparece cerrado localmente." `
                "Confirmar si el puerto aplica para este servidor y si el servicio asociado debe estar activo."

            [PSCustomObject]@{
                Port = $Port
                Name = $PortName
                Description = $PortDescription
                Status = "Cerrado"
                Message = "No se detecto escucha local"
            }
        }
    }
    catch {
        [PSCustomObject]@{
            Port = $Port
            Name = $PortName
            Description = $PortDescription
            Status = "ERROR"
            Message = $_.Exception.Message
        }
    }
}

$PortRows = $PortObjects | ForEach-Object {
    $Badge = Get-BadgeHtml $_.Status

    "<tr>
        <td>$(HtmlEncode $_.Port)</td>
        <td>$(HtmlEncode $_.Name)</td>
        <td>$(HtmlEncode $_.Description)</td>
        <td>$Badge</td>
        <td>$(HtmlEncode $_.Message)</td>
    </tr>"
}

$PortsHtml = @"
<table>
<thead>
<tr>
<th>Puerto</th>
<th>Servicio</th>
<th>Descripcion</th>
<th>Estado</th>
<th>Mensaje</th>
</tr>
</thead>
<tbody>
$($PortRows -join "`n")
</tbody>
</table>
"@

# =========================
# ESTADO GENERAL
# =========================

$CriticalFindings = @($Findings | Where-Object { $_.Severity -eq "CRITICO" })
$AlertFindings    = @($Findings | Where-Object { $_.Severity -eq "ALERTA" })
$ReviewFindings   = @($Findings | Where-Object { $_.Severity -eq "REVISAR" })

$CriticalCount = $CriticalFindings.Count
$AlertCount    = $AlertFindings.Count
$ReviewCount   = $ReviewFindings.Count

# Valores por defecto si no existen en config.json
$ReviewFindingsToReview = 1
$AlertFindingsToAlert = 1
$CriticalFindingsToCritical = 1
$IgnoreReviewForGeneralStatus = $false

# Leer reglas desde config.json
if ($null -ne $Config.StatusRules.ReviewFindingsToReview) {
    $ReviewFindingsToReview = [int]$Config.StatusRules.ReviewFindingsToReview
}

if ($null -ne $Config.StatusRules.AlertFindingsToAlert) {
    $AlertFindingsToAlert = [int]$Config.StatusRules.AlertFindingsToAlert
}

if ($null -ne $Config.StatusRules.CriticalFindingsToCritical) {
    $CriticalFindingsToCritical = [int]$Config.StatusRules.CriticalFindingsToCritical
}

if ($null -ne $Config.StatusRules.IgnoreReviewForGeneralStatus) {
    $IgnoreReviewForGeneralStatus = [bool]$Config.StatusRules.IgnoreReviewForGeneralStatus
}

$EstadoGeneral = "OK"

if ($CriticalCount -ge $CriticalFindingsToCritical) {
    $EstadoGeneral = "CRITICO"
}
elseif ($AlertCount -ge $AlertFindingsToAlert) {
    $EstadoGeneral = "ALERTA"
}
elseif (-not $IgnoreReviewForGeneralStatus -and $ReviewCount -ge $ReviewFindingsToReview) {
    $EstadoGeneral = "REVISAR"
}
else {
    $EstadoGeneral = "OK"
}

Write-Log "Hallazgos detectados - CRITICO: $CriticalCount | ALERTA: $AlertCount | REVISAR: $ReviewCount"
Write-Log "Reglas estado general - CRITICO >= $CriticalFindingsToCritical | ALERTA >= $AlertFindingsToAlert | REVISAR >= $ReviewFindingsToReview | Ignorar REVISAR: $IgnoreReviewForGeneralStatus"
Write-Log "Estado general calculado: $EstadoGeneral"

$ExecutiveSummary = switch ($EstadoGeneral) {
    "OK" {
        "El servidor se encuentra operativo y no se detectaron hallazgos relevantes durante la ejecucion del Health Check."
    }
    "REVISAR" {
        "El servidor se encuentra operativo, pero se detectaron hallazgos preventivos que conviene revisar para evitar posibles incidencias."
    }
    "ALERTA" {
        "El servidor se encuentra operativo, pero presenta condiciones que requieren atencion para prevenir afectacion al servicio."
    }
    "CRITICO" {
        "Se detectaron condiciones criticas que pueden afectar la disponibilidad o funcionamiento del servicio. Se recomienda atencion prioritaria."
    }
    default {
        "Estado no determinado."
    }
}

$FindingsHtml = Convert-FindingsToHtml $Findings

# =========================
# CSS EXTERNO
# =========================

if (Test-Path $CssPath) {
    $Css = Get-Content $CssPath -Raw -Encoding UTF8
}
else {
    $Css = @"
body { font-family: Arial, sans-serif; margin: 30px; background: #f4f6f8; color: #111827; }
.card, .section { background: white; padding: 20px; border-radius: 12px; margin-bottom: 20px; }
table { width: 100%; border-collapse: collapse; background: white; }
th, td { border: 1px solid #e5e7eb; padding: 10px; vertical-align: top; }
th { background: #111827; color: white; }
"@
    Write-Log "No se encontro CSS externo: $CssPath. Se uso CSS basico."
}

# =========================
# JSON PARA FUTURA API/DASHBOARD
# =========================

$HealthResult = [PSCustomObject]@{
    serverName = $env:COMPUTERNAME
    user = $env:USERNAME
    executionDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    environment = $Environment
    client = $Client
    serverType = $ServerType
    status = $EstadoGeneral
    summary = $ExecutiveSummary
    iis = @{
        status = $IISStatus
    }
    operatingSystem = @{
        caption = $OsCaption
        version = $OsVersion
        lastBoot = "$LastBoot"
        uptime = $UptimeText
    }
    metrics = @{
        cpuUsage = $CpuUsage
        cpuStatus = $CpuStatus
        ramUsage = $RamUsage
        ramStatus = $RamStatus
        ramTotalGB = $RamTotalGB
        ramFreeGB = $RamFreeGB
    }
    disks = $DiskObjects
    services = $ServiceObjects
    urls = $UrlObjects
    ports = $PortObjects
    findings = $Findings
    paths = @{
        html = $HtmlPath
        pdf = $PdfPath
        log = $LogPath
    }
}

$HealthResult | ConvertTo-Json -Depth 10 | Out-File $JsonPath -Encoding UTF8
Write-Log "JSON generado: $JsonPath"

# =========================
# HTML
# =========================

$GeneratedAt = Get-Date -Format "dd/MM/yyyy HH:mm:ss"

$CpuBar = Get-PercentBarHtml -Percent $CpuUsage -Status $CpuStatus
$RamBar = Get-PercentBarHtml -Percent $RamUsage -Status $RamStatus

#$DiskBadge = Get-BadgeHtml $WorstDiskStatus
$CpuBadge = Get-BadgeHtml $CpuStatus
$RamBadge = Get-BadgeHtml $RamStatus
$GeneralBadge = Get-BadgeHtml $EstadoGeneral

$StatusClass = Get-StatusClass $EstadoGeneral

$Html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<title>Health Check - $env:COMPUTERNAME</title>
<style>
$Css
</style>
</head>

<body>
<div class='page'>

    <div class='hero $StatusClass'>
        <div>
            <div class='eyebrow'>Reporte automatico de Health Check</div>
            <h1>$env:COMPUTERNAME</h1>
            <p>Cliente: $(HtmlEncode $Client) | Ambiente: $(HtmlEncode $Environment) | Tipo: $(HtmlEncode $ServerType)</p>
            <p>Generado: $GeneratedAt | Usuario: $env:USERNAME</p>
        </div>
        <div class='hero-status'>
            <span>Estado general</span>
            <strong>$EstadoGeneral</strong>
        </div>
    </div>

    <div class='summary-grid'>
        <div class='metric-card'>
            <div class='metric-label'>CPU</div>
            <div class='metric-value'>$CpuUsage%</div>
            $CpuBar
            <div class='metric-footer'>$CpuBadge</div>
        </div>

        <div class='metric-card'>
            <div class='metric-label'>RAM</div>
            <div class='metric-value'>$RamUsage%</div>
            $RamBar
            <div class='metric-footer'>$RamBadge</div>
        </div>

        <div class='metric-card metric-card-wide'>
            <div class='metric-label'>Discos locales</div>
            <div class='disk-summary'>$DiskSummaryHtml</div>
        </div>

        <div class='metric-card'>
            <div class='metric-label'>Eventos 24h</div>
            <div class='metric-value'>$CriticalEventsCount</div>
            <div class='metric-footer'>System: Critical/Error</div>
        </div>
    </div>

    <div class='section'>
        <h2>Resumen ejecutivo</h2>
        <p class='summary-text'>$ExecutiveSummary</p>
        <p class='summary-text'>
            Hallazgos detectados:
            <strong>CRITICO:</strong> $CriticalCount |
            <strong>ALERTA:</strong> $AlertCount |
            <strong>REVISAR:</strong> $ReviewCount
        </p>
    </div>

    <div class='section'>
        <h2>Hallazgos principales y recomendaciones</h2>
        $FindingsHtml
    </div>

    <div class='section'>
        <h2>Informacion del servidor</h2>
        <div class='info-grid'>
            <div><span>Servidor</span><strong>$env:COMPUTERNAME</strong></div>
            <div><span>Sistema operativo</span><strong>$(HtmlEncode $OsCaption)</strong></div>
            <div><span>Version</span><strong>$(HtmlEncode $OsVersion)</strong></div>
            <div><span>Ultimo reinicio</span><strong>$(HtmlEncode $LastBoot)</strong></div>
            <div><span>Uptime</span><strong>$(HtmlEncode $UptimeText)</strong></div>
            <div><span>Fabricante</span><strong>$(HtmlEncode $Manufacturer)</strong></div>
            <div><span>Modelo</span><strong>$(HtmlEncode $Model)</strong></div>
            <div><span>Estado</span><strong>$GeneralBadge</strong></div>

        </div>
    </div>

    <div class='section'>
        <h2>CPU / Procesador</h2>
        <p class='summary-text'>
            Uso actual de CPU: <strong>$CpuUsage%</strong> | Estado: $CpuBadge
        </p>
        $CpuDetailHtml
    </div>

    <div class='section'>
        <h2>Discos locales</h2>
        $DisksHtml
    </div>

    <div class='section'>
        <h2>Servicios criticos</h2>
        $ServicesHtml
    </div>

    <div class='section'>
        <h2>IIS - Sitios</h2>
        $SitesHtml
    </div>

    <div class='section'>
        <h2>IIS - Application Pools</h2>
        $PoolsHtml
    </div>

    <div class='section'>
        <h2>URLs / Aplicativos</h2>
        $UrlStatusHtml
    </div>

    <div class='section'>
        <h2>Puertos locales</h2>
        $PortsHtml
    </div>

    <div class='section'>
        <h2>Eventos criticos y errores recientes</h2>
        $EventsHtml
    </div>

    <div class='section'>
        <h2>Tareas programadas</h2>
        $ScheduledTasksStatus
    </div>

    <div class='section'>
        <h2>Procesos principales</h2>
        $TopProcessesHtml
    </div>

    <div class='footer'>
        <p>Reporte generado automaticamente por HealthCheck Local.</p>
    </div>

</div>
</body>
</html>
"@

$Html | Out-File $HtmlPath -Encoding UTF8
Write-Log "HTML generado: $HtmlPath"

# =========================
# PDF CON MICROSOFT EDGE
# =========================

$EdgePaths = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
)

$EdgeExe = $EdgePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($EdgeExe) {
    try {
        Start-Process `
            -FilePath $EdgeExe `
            -ArgumentList "--headless --disable-gpu --print-to-pdf=`"$PdfPath`" `"$HtmlPath`"" `
            -Wait

        Write-Log "PDF generado: $PdfPath"
    }
    catch {
        Write-Log "ERROR generando PDF: $($_.Exception.Message)"
    }
}
else {
    Write-Log "ERROR: No se encontro Microsoft Edge para generar PDF"
}

# =========================
# ENVIO DE CORREO
# =========================

$MailEnabled = $false
if ($null -ne $Config.Mail.Enabled) {
    $MailEnabled = [bool]$Config.Mail.Enabled
}

$SendOnlyOnAlert = $false
if ($null -ne $Config.Mail.SendOnlyOnAlert) {
    $SendOnlyOnAlert = [bool]$Config.Mail.SendOnlyOnAlert
}

$ShouldSendMail = $MailEnabled -and (
    -not $SendOnlyOnAlert -or
    $EstadoGeneral -in @("REVISAR", "ALERTA", "CRITICO")
)

$MailStatus = "Envio de correo deshabilitado o no requerido por configuracion."

if ($ShouldSendMail) {
    try {
        $SmtpServer = $Config.Mail.SmtpServer
        $SmtpPort   = [int]$Config.Mail.SmtpPort
        $UseSsl     = [bool]$Config.Mail.UseSsl
        $From       = $Config.Mail.From
        $To         = @($Config.Mail.To)
        $CredentialPath = $Config.Mail.CredentialPath

        if (!(Test-Path $CredentialPath)) {
            throw "No se encontro el archivo de credenciales SMTP: $CredentialPath"
        }

        $Credential = Import-Clixml -Path $CredentialPath

<<<<<<< HEAD
        $Subject = "HealthCheck $Client - $env:COMPUTERNAME - $EstadoGeneral"
=======
        $Subject = "HealthCheck $env:COMPUTERNAME - $EstadoGeneral"
>>>>>>> origin/main

        $Body = @"
Este es un reporte de ejemplo automatico de Health Check.

Servidor: $env:COMPUTERNAME
Cliente: $Client
Ambiente: $Environment
Tipo: $ServerType
Estado: $EstadoGeneral
Fecha: $(Get-Date)

Resumen:
$ExecutiveSummary

Adjunto: PDF/HTML del reporte.
"@

        $AttachmentToSend = if (Test-Path $PdfPath) { $PdfPath } else { $HtmlPath }

        $MailParams = @{
            From = $From
            To = $To
            Subject = $Subject
            Body = $Body
            SmtpServer = $SmtpServer
            Port = $SmtpPort
            Credential = $Credential
            Attachments = $AttachmentToSend
            Encoding = "UTF8"
            ErrorAction = "Stop"
        }

        if ($UseSsl) {
            $MailParams.UseSsl = $true
        }

        Send-MailMessage @MailParams

        Write-Log "Correo enviado correctamente a $To"
        $MailStatus = "Correo enviado correctamente"
    }
    catch {
        Write-Log "ERROR SMTP: $($_.Exception.Message)"
        $MailStatus = "ERROR SMTP: $($_.Exception.Message)"
    }
}
else {
    Write-Log $MailStatus
}

# =========================
# LIMPIEZA HISTORICA
# =========================

Remove-OldReports -Folder $HtmlFolder -Days $KeepReportsDays
Remove-OldReports -Folder $PdfFolder  -Days $KeepReportsDays
Remove-OldReports -Folder $LogFolder  -Days $KeepReportsDays
Remove-OldReports -Folder $JsonFolder -Days $KeepReportsDays

# =========================
# SALIDA CONSOLA
# =========================

Write-Host ""
Write-Host "Health Check finalizado." -ForegroundColor Green
Write-Host "Estado general: $EstadoGeneral" -ForegroundColor Cyan
Write-Host "HTML generado: $HtmlPath" -ForegroundColor Cyan
Write-Host "PDF generado: $PdfPath" -ForegroundColor Cyan
Write-Host "JSON generado: $JsonPath" -ForegroundColor Cyan
Write-Host "LOG generado: $LogPath" -ForegroundColor Cyan
Write-Host "Correo: $MailStatus" -ForegroundColor Yellow
Write-Host ""
