Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Ansible.Changed = $false

function Write-ProvisionProgress($message) {
    "$(Get-Date -UFormat "%Y-%m-%dT%T%Z") $message"
}

Write-ProvisionProgress 'Waiting for previous provision-sysprep-oobe to finish...'
$provisionSysprepCompletedPath = 'C:\Windows\System32\Sysprep\provision-sysprep.txt'
while (!(Test-Path $provisionSysprepCompletedPath)) {
    Start-Sleep -Seconds 5
}
Start-Sleep -Seconds 5

$Ansible.Changed = $true
