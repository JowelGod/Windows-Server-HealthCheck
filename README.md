# 🖥️ Windows Server HealthCheck

Local PowerShell script to perform an automated **Health Check** on Windows servers, generate executive reports, and validate the overall status of the server.

The script collects operational information, evaluates findings, generates reports in **HTML**, **PDF**, and **JSON**, saves execution logs, and can optionally send the results by email.

---

## 📌 Main Features

- Operating system and last boot validation.
- Server uptime calculation.
- CPU usage check.
- RAM usage check.
- Local disk and free space validation.
- Critical services validation.
- IIS websites validation.
- IIS Application Pools validation.
- Configured URL validation.
- Local port validation.
- Recent critical events and errors review.
- Scheduled tasks validation.
- Top processes by resource consumption.
- HTML report generation.
- Optional PDF report generation.
- JSON results file generation.
- Execution log generation.
- Optional email report delivery.
- Overall server health status calculation.

---

## 🚦 Report Status

The HealthCheck can return one of the following overall statuses:

| Status | Description |
|---|---|
| `OK` | No relevant findings were detected. |
| `REVIEW` | Preventive findings were detected and should be reviewed. |
| `ALERT` | Conditions were detected that require attention to prevent service impact. |
| `CRITICAL` | Critical conditions were detected that may affect service availability or functionality. |

---

## 📁 Project Structure

Recommended base path:

```text
C:\Scripts\HealthCheck\
```

Suggested structure:

```text
C:\Scripts\HealthCheck\
│
├── HealthCheck.ps1
├── config.json
│
├── credentials\
│   └── smtp_credential.xml
│
├── templates\
│   └── report-style.css
│
└── reports\
    ├── html\
    ├── pdf\
    ├── json\
    └── logs\
```

---

## 📄 Files and Folders Description

| File / Folder | Description |
|---|---|
| `HealthCheck.ps1` | Main HealthCheck script. |
| `config.json` | Main server configuration file. |
| `credentials\` | Folder where the encrypted SMTP credential is stored. |
| `templates\` | Folder where the report CSS file is stored. |
| `reports\html` | Folder where HTML reports are generated. |
| `reports\pdf` | Folder where PDF reports are generated. |
| `reports\json` | Folder where JSON result files are generated. |
| `reports\logs` | Folder where execution logs are generated. |

---

## ⚙️ Requirements

The server must have:

- Windows Server.
- PowerShell.
- Permissions to query WMI/CIM.
- Permissions to query services.
- Permissions to query disks.
- Permissions to query Event Viewer.
- Permissions to query Task Scheduler.
- Permissions to query IIS, if applicable.
- Microsoft Edge installed if PDF generation is required.
- SMTP access if email delivery is enabled.
- A valid `config.json` file.
- An encrypted SMTP credential if email delivery is enabled.

---

## 🚀 Initial Setup

### 1. Create the base folder

```powershell
New-Item -ItemType Directory -Path "C:\Scripts\HealthCheck" -Force
```

### 2. Create the required subfolders

```powershell
New-Item -ItemType Directory -Path "C:\Scripts\HealthCheck\credentials" -Force
New-Item -ItemType Directory -Path "C:\Scripts\HealthCheck\templates" -Force
New-Item -ItemType Directory -Path "C:\Scripts\HealthCheck\reports\html" -Force
New-Item -ItemType Directory -Path "C:\Scripts\HealthCheck\reports\pdf" -Force
New-Item -ItemType Directory -Path "C:\Scripts\HealthCheck\reports\json" -Force
New-Item -ItemType Directory -Path "C:\Scripts\HealthCheck\reports\logs" -Force
```

---

## 🧩 `config.json` File

The `config.json` file must be stored at:

```text
C:\Scripts\HealthCheck\config.json
```

Base example:

```json
{
  "General": {
    "ServerName": "",
    "Environment": "Production",
    "Client": "Unicomer DataBase",
    "ServerType": "Web",
    "OutputFolder": "C:\\Scripts\\HealthCheck\\reports",
    "KeepReportsDays": 30
  },
  "Thresholds": {
    "CpuWarning": 70,
    "CpuCritical": 90,
    "RamWarning": 80,
    "RamCritical": 90,
    "DiskWarningFreePercent": 20,
    "DiskCriticalFreePercent": 10
  },
  "Mail": {
    "Enabled": true,
    "SmtpServer": "smtp.gmail.com",
    "SmtpPort": 587,
    "UseSsl": true,
    "From": "notifications@example.com",
    "To": [
      "recipient@example.com"
    ],
    "CredentialPath": "C:\\Scripts\\HealthCheck\\credentials\\smtp_credential.xml",
    "SendOnlyOnAlert": false
  },
  "StatusRules": {
    "ReviewFindingsToReview": 1,
    "AlertFindingsToAlert": 1,
    "CriticalFindingsToCritical": 1,
    "IgnoreReviewForGeneralStatus": false
  },
  "Services": [
    {
      "Name": "W3SVC",
      "Description": "Main IIS service. Allows publishing websites through HTTP/HTTPS."
    },
    {
      "Name": "WAS",
      "Description": "Windows Process Activation Service. Required for IIS Application Pools."
    },
    {
      "Name": "MSSQLSERVER",
      "Description": "Main SQL Server engine for the default instance."
    },
    {
      "Name": "SQLSERVERAGENT",
      "Description": "Service that runs SQL Server jobs, maintenance tasks, and scheduled tasks."
    },
    {
      "Name": "Schedule",
      "Description": "Windows Task Scheduler service."
    },
    {
      "Name": "WinRM",
      "Description": "Remote administration service through Windows Remote Management."
    }
  ],
  "Urls": [
    "https://example-site-1.com/Login.aspx",
    "https://example-site-2.com/Login.aspx"
  ],
  "Ports": [
    {
      "Port": 80,
      "Name": "HTTP",
      "Description": "Port used for unencrypted web traffic."
    },
    {
      "Port": 443,
      "Name": "HTTPS",
      "Description": "Port used for secure web traffic through SSL/TLS."
    },
    {
      "Port": 3389,
      "Name": "RDP",
      "Description": "Port used for Remote Desktop connections."
    },
    {
      "Port": 1433,
      "Name": "SQL Server",
      "Description": "Common port used by Microsoft SQL Server."
    }
  ],
  "ScheduledTasks": {
    "Mode": "ConfiguredOnly",
    "IncludePaths": [
      "\\Guatemala\\",
      "\\Honduras\\"
    ],
    "IncludeTaskNames": [],
    "MaxResults": 50
  },
  "IIS": {
    "CheckAllSites": false,
    "SitesToCheck": [
      "Default Web Site"
    ],
    "CheckAllAppPools": false,
    "AppPoolsToCheck": [
      "DefaultAppPool"
    ]
  }
}
```

---

## 🔐 Secure Email Configuration

The script should not store passwords in plain text.

To send email, it uses an encrypted credential generated with `Export-Clixml`.

The credential is tied to:

- The Windows user that generated it.
- The server where it was created.

This means that if the scheduled task runs under a different user, that user must generate its own SMTP credential.

---

## Create SMTP Credential

Create the following file:

```text
C:\Scripts\HealthCheck\Create-SmtpCredential.ps1
```

File content:

```powershell
$CredentialFolder = "C:\Scripts\HealthCheck\credentials"
$CredentialPath = "$CredentialFolder\smtp_credential.xml"

if (!(Test-Path $CredentialFolder)) {
    New-Item -ItemType Directory -Path $CredentialFolder -Force | Out-Null
}

$MailUser = "notifications@example.com"

Write-Host "Enter the password or app password for: $MailUser" -ForegroundColor Cyan

$Credential = Get-Credential -UserName $MailUser -Message "HealthCheck SMTP Credential"

$Credential | Export-Clixml -Path $CredentialPath

Write-Host ""
Write-Host "Credential saved at:" -ForegroundColor Green
Write-Host $CredentialPath -ForegroundColor Yellow
Write-Host ""
Write-Host "Important: only this Windows user on this server will be able to read it." -ForegroundColor Cyan
```

Run it:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\HealthCheck\Create-SmtpCredential.ps1"
```

Validate that the credential exists:

```powershell
Test-Path "C:\Scripts\HealthCheck\credentials\smtp_credential.xml"
```

Expected result:

```text
True
```

Validate credential reading:

```powershell
$Credential = Import-Clixml "C:\Scripts\HealthCheck\credentials\smtp_credential.xml"
$Credential.UserName
```

---

## 🎨 CSS Configuration

The CSS file must be stored at:

```text
C:\Scripts\HealthCheck\templates\report-style.css
```

Validate that it exists:

```powershell
Test-Path "C:\Scripts\HealthCheck\templates\report-style.css"
```

Read the first lines:

```powershell
Get-Content "C:\Scripts\HealthCheck\templates\report-style.css" -First 10
```

---

## ▶️ Manual Execution

Run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\HealthCheck\HealthCheck.ps1"
```

Expected output:

```text
Health Check completed.
Overall status: OK
HTML generated: C:\Scripts\HealthCheck\reports\html\HealthCheck_SERVER_DATE.html
PDF generated: C:\Scripts\HealthCheck\reports\pdf\HealthCheck_SERVER_DATE.pdf
JSON generated: C:\Scripts\HealthCheck\reports\json\HealthCheck_SERVER_DATE.json
LOG generated: C:\Scripts\HealthCheck\reports\logs\HealthCheck_SERVER_DATE.log
Email: Email sent successfully
```

---

## ✅ Validate Configuration

### Validate `config.json`

```powershell
$Config = Get-Content "C:\Scripts\HealthCheck\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$Config
```

### Validate email settings

```powershell
$Config.Mail
```

### Validate configured services

```powershell
$Config.Services
```

### Validate configured URLs

```powershell
$Config.Urls
```

### Validate configured ports

```powershell
$Config.Ports
```

---

## 🧪 Individual Tests

### Operating system and last boot time

```powershell
$OS = Get-CimInstance Win32_OperatingSystem

$OS.Caption
$OS.Version
$OS.LastBootUpTime
```

### Server uptime

```powershell
$OS = Get-CimInstance Win32_OperatingSystem
$Uptime = New-TimeSpan -Start $OS.LastBootUpTime -End (Get-Date)

"$($Uptime.Days) days, $($Uptime.Hours) hours, $($Uptime.Minutes) minutes"
```

### CPU

```powershell
$CpuData = Get-CimInstance Win32_Processor |
    Measure-Object -Property LoadPercentage -Average

[math]::Round($CpuData.Average, 2)
```

### CPU details

```powershell
Get-CimInstance Win32_Processor |
Select-Object Name, SocketDesignation, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, LoadPercentage
```

### RAM

```powershell
$OS = Get-CimInstance Win32_OperatingSystem

$RamUsage = [math]::Round(
    (($OS.TotalVisibleMemorySize - $OS.FreePhysicalMemory) / $OS.TotalVisibleMemorySize) * 100,
    2
)

$RamTotalGB = [math]::Round($OS.TotalVisibleMemorySize / 1MB, 2)
$RamFreeGB = [math]::Round($OS.FreePhysicalMemory / 1MB, 2)

$RamUsage
$RamTotalGB
$RamFreeGB
```

### Local disks

```powershell
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
Where-Object { $_.Size -ne $null -and $_.Size -gt 0 } |
Select-Object `
    DeviceID,
    VolumeName,
    FileSystem,
    @{Name="TotalGB";Expression={[math]::Round($_.Size / 1GB, 2)}},
    @{Name="FreeGB";Expression={[math]::Round($_.FreeSpace / 1GB, 2)}},
    @{Name="FreePercent";Expression={[math]::Round(($_.FreeSpace / $_.Size) * 100, 2)}}
```

### Critical services

```powershell
$Config = Get-Content "C:\Scripts\HealthCheck\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json

$Config.Services | ForEach-Object {
    $ServiceName = $_.Name
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($svc) {
        [PSCustomObject]@{
            Name = $ServiceName
            DisplayName = $svc.DisplayName
            Status = $svc.Status
            Description = $_.Description
        }
    }
    else {
        [PSCustomObject]@{
            Name = $ServiceName
            DisplayName = "Not found"
            Status = "Not found"
            Description = $_.Description
        }
    }
}
```

### IIS - Websites

```powershell
Import-Module WebAdministration

Get-Website |
Select-Object Name, State, PhysicalPath
```

### IIS - Application Pools

```powershell
Import-Module WebAdministration

Get-ChildItem IIS:\AppPools |
Select-Object Name, State, managedRuntimeVersion, managedPipelineMode
```

### URLs

```powershell
$Config = Get-Content "C:\Scripts\HealthCheck\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json

$Config.Urls | ForEach-Object {
    $Url = $_
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $Response = Invoke-WebRequest `
            -Uri $Url `
            -UseBasicParsing `
            -TimeoutSec 10 `
            -UserAgent $Config.UrlSettings.UserAgent `
            -ErrorAction Stop

        $Stopwatch.Stop()

        [PSCustomObject]@{
            Url = $Url
            Status = "OK"
            HttpCode = $Response.StatusCode
            ResponseMs = $Stopwatch.ElapsedMilliseconds
        }
    }
    catch {
        $Stopwatch.Stop()

        [PSCustomObject]@{
            Url = $Url
            Status = "ERROR"
            Error = $_.Exception.Message
            ResponseMs = $Stopwatch.ElapsedMilliseconds
        }
    }
}
```

### Ports

```powershell
$Config = Get-Content "C:\Scripts\HealthCheck\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json

$Config.Ports | ForEach-Object {
    $Port = $_.Port

    $Result = Test-NetConnection `
        -ComputerName "127.0.0.1" `
        -Port $Port `
        -InformationLevel Quiet `
        -WarningAction SilentlyContinue

    [PSCustomObject]@{
        Port = $Port
        Name = $_.Name
        Description = $_.Description
        Status = if ($Result) { "Open" } else { "Closed" }
    }
}
```

### Recent critical events and errors

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = "System"
    Level = 1,2
    StartTime = (Get-Date).AddDays(-1)
} |
Select-Object -First 10 TimeCreated, Id, ProviderName, LevelDisplayName
```

### Configured scheduled tasks

```powershell
$Config = Get-Content "C:\Scripts\HealthCheck\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json

$IncludePaths = @($Config.ScheduledTasks.IncludePaths)

Get-ScheduledTask |
Where-Object {
    $Task = $_
    $Match = $false

    foreach ($Path in $IncludePaths) {
        if ($Task.TaskPath -eq $Path -or $Task.TaskPath -like "$Path*") {
            $Match = $true
        }
    }

    $Match
} |
Select-Object TaskPath, TaskName, State
```

### Top processes by CPU

```powershell
Get-Process |
Sort-Object -Property CPU -Descending |
Select-Object -First 10 Name, Id, CPU, @{Name="RAM_MB";Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}}
```

---

## 📄 PDF Generation

The script uses Microsoft Edge in headless mode.

Possible paths:

```text
C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
C:\Program Files\Microsoft\Edge\Application\msedge.exe
```

Validate if Edge exists:

```powershell
$EdgePaths = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
)

$EdgeExe = $EdgePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

$EdgeExe
```

If it returns a path, Edge is available.

---

## 📧 Email Delivery Test

```powershell
$Config = Get-Content "C:\Scripts\HealthCheck\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$Credential = Import-Clixml -Path $Config.Mail.CredentialPath

Send-MailMessage `
    -From $Config.Mail.From `
    -To $Config.Mail.To `
    -Subject "HealthCheck SMTP Test" `
    -Body "Test email from HealthCheck." `
    -SmtpServer $Config.Mail.SmtpServer `
    -Port $Config.Mail.SmtpPort `
    -UseSsl `
    -Credential $Credential `
    -Encoding UTF8
```

---

## 🧠 Overall Status Rules

The overall status is calculated based on the findings generated during execution.

Example:

```json
"StatusRules": {
  "ReviewFindingsToReview": 1,
  "AlertFindingsToAlert": 1,
  "CriticalFindingsToCritical": 1,
  "IgnoreReviewForGeneralStatus": false
}
```

With this configuration:

| Condition | Result |
|---|---|
| 1 `REVIEW` finding | Overall status becomes `REVIEW` |
| 1 `ALERT` finding | Overall status becomes `ALERT` |
| 1 `CRITICAL` finding | Overall status becomes `CRITICAL` |

These rules allow you to adjust report sensitivity.

Examples:

- If `ReviewFindingsToReview` is `5`, the overall status will not change to `REVIEW` until there are 5 or more `REVIEW` findings.
- If `AlertFindingsToAlert` is `2`, the overall status will not change to `ALERT` until there are 2 or more `ALERT` findings.
- If `CriticalFindingsToCritical` is `1`, one single `CRITICAL` finding changes the overall status to `CRITICAL`.
- If `IgnoreReviewForGeneralStatus` is `true`, `REVIEW` findings will not affect the overall status, although they will still appear in the report details.

---

## ⏰ Schedule Execution with Task Scheduler

### Option 1: Create the task using the graphical interface

Open Task Scheduler:

```powershell
taskschd.msc
```

Go to:

```text
Task Scheduler Library
```

Create a new task with:

```text
Create Task
```

### General

Configure:

```text
Name: HealthCheck Local
Description: Automatic server HealthCheck execution
```

Select:

```text
Run whether user is logged on or not
Run with highest privileges
```

Configure the user that will run the task.

> Important: this user must have access to `C:\Scripts\HealthCheck\` and must be the same user that generated `smtp_credential.xml`.

### Triggers

Example for daily execution:

```text
Begin the task: On a schedule
Settings: Daily
Start: 08:00:00
Recur every: 1 days
Enabled: true
```

### Actions

Action:

```text
Start a program
```

Program/script:

```text
powershell.exe
```

Add arguments:

```powershell
-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\HealthCheck\HealthCheck.ps1"
```

Start in:

```text
C:\Scripts\HealthCheck
```

### Recommended settings

```text
Allow task to be run on demand
Run task as soon as possible after a scheduled start is missed
If the task fails, restart every: 5 minutes
Attempt to restart up to: 3 times
Stop the task if it runs longer than: 1 hour
```

---

## 🖱️ Create Scheduled Task by Command

Daily execution at 8:00 AM:

```powershell
schtasks /Create /TN "HealthCheck Local" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\HealthCheck\HealthCheck.ps1" /SC DAILY /ST 08:00 /RL HIGHEST /F
```

Specifying a user:

```powershell
schtasks /Create /TN "HealthCheck Local" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\HealthCheck\HealthCheck.ps1" /SC DAILY /ST 08:00 /RU "DOMAIN\User" /RL HIGHEST /F
```

---

## ▶️ Run Scheduled Task Manually

```powershell
schtasks /Run /TN "HealthCheck Local"
```

---

## 🔍 Check Scheduled Task Status

```powershell
schtasks /Query /TN "HealthCheck Local" /V /FO LIST
```

---

## 🗑️ Delete Scheduled Task

```powershell
schtasks /Delete /TN "HealthCheck Local" /F
```

---

## 📂 Review Generated Files

### Review latest log

```powershell
Get-ChildItem "C:\Scripts\HealthCheck\reports\logs" -Filter "*.log" |
Sort-Object LastWriteTime -Descending |
Select-Object -First 1 |
ForEach-Object { notepad $_.FullName }
```

### Review latest HTML report

```powershell
Get-ChildItem "C:\Scripts\HealthCheck\reports\html" -Filter "*.html" |
Sort-Object LastWriteTime -Descending |
Select-Object -First 1 |
ForEach-Object { Start-Process $_.FullName }
```

### Review latest PDF report

```powershell
Get-ChildItem "C:\Scripts\HealthCheck\reports\pdf" -Filter "*.pdf" |
Sort-Object LastWriteTime -Descending |
Select-Object -First 1 |
ForEach-Object { Start-Process $_.FullName }
```

### Review latest JSON file

```powershell
Get-ChildItem "C:\Scripts\HealthCheck\reports\json" -Filter "*.json" |
Sort-Object LastWriteTime -Descending |
Select-Object -First 1 |
ForEach-Object { notepad $_.FullName }
```

---

## ✅ Recommendations Before Enabling Automation

Before scheduling automatic execution:

1. Run the script manually.
2. Validate that the HTML report is generated.
3. Validate that the PDF report is generated.
4. Validate that the JSON file is generated.
5. Validate that the execution log is generated.
6. Validate that the email is delivered correctly.
7. Check that the Task Scheduler user has enough permissions.
8. Confirm that the SMTP credential was generated by the same user that will run the scheduled task.
9. Adjust services, URLs, ports, IIS settings, and scheduled tasks in `config.json`.
10. Run the task manually from Task Scheduler before leaving it automated.

---

## 🛠️ Common Issues

### Email is not sent

Validate that the credential exists:

```powershell
Test-Path "C:\Scripts\HealthCheck\credentials\smtp_credential.xml"
```

Validate that the user can read it:

```powershell
Import-Clixml "C:\Scripts\HealthCheck\credentials\smtp_credential.xml"
```

If it fails, generate the credential again with the same user that will run the scheduled task.

---

### PDF is not generated

Validate that Microsoft Edge exists:

```powershell
Test-Path "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
Test-Path "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
```

---

### IIS websites are not displayed

Validate the module:

```powershell
Get-Module -ListAvailable WebAdministration
```

Test manually:

```powershell
Import-Module WebAdministration
Get-Website
```

### Disks are not displayed

Test manually:

```powershell
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
```

If it works manually but not from the script, validate the permissions of the user running the scheduled task.

---

### Overall status looks incorrect

Review the execution log at:

```text
C:\Scripts\HealthCheck\reports\logs
```

Also validate the `StatusRules` section inside `config.json`.

---

## 🧾 Main Execution Command

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\HealthCheck\HealthCheck.ps1"
```

---

## 📝 Important Notes

- The `config.json` file controls most HealthCheck parameters.
- The SMTP credential should not be copied between servers or users.
- If the scheduled task user changes, the SMTP credential must be regenerated.
- Old reports can be automatically cleaned up based on the `KeepReportsDays` value.
- Services, ports, URLs, IIS websites, Application Pools, and scheduled tasks must be configured according to each server.
- The overall status should always be reviewed together with the detailed findings, not in isolation.
