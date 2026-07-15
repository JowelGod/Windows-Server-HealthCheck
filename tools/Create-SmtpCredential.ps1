# ==========================================
# Crear credencial SMTP segura
# Ejecutar manualmente una sola vez
# ==========================================

$CredentialFolder = "C:\Scripts\HealthCheck\credentials"
$CredentialPath = "$CredentialFolder\smtp_credential.xml"

if (!(Test-Path $CredentialFolder)) {
    New-Item -ItemType Directory -Path $CredentialFolder -Force | Out-Null
}

$MailUser = "notificaciones@mccollect.com.mx"

Write-Host "Ingresa la contraseña o app password para: $MailUser" -ForegroundColor Cyan

$Credential = Get-Credential -UserName $MailUser -Message "Credencial SMTP HealthCheck"

$Credential | Export-Clixml -Path $CredentialPath

Write-Host ""
Write-Host "Credencial guardada de forma segura en:" -ForegroundColor Green
Write-Host $CredentialPath -ForegroundColor Yellow
Write-Host ""
Write-Host "Importante: solo este usuario de Windows en este servidor podrá leerla." -ForegroundColor Cyan