#
# 04-Disable-ADUserOffboarding.ps1
# Offboards a departing employee in lab.local.
#
# For the given username it:
#   1. Disables the account
#   2. Records the department groups it was in, then removes them
#      (Domain Users stays: it is the primary group and cannot be removed)
#   3. Stamps the Description with the date and who offboarded it
#   4. Moves the account to OU=Disabled Users,OU=_CORP
#   5. Appends the action to .\logs\offboarding-log.csv
#
# The account is kept, not deleted, so it can be restored or audited later.
#
# Usage (on DC01 as LAB\Administrator):
#   .\04-Disable-ADUserOffboarding.ps1 -SamAccountName ebrooks
#   .\04-Disable-ADUserOffboarding.ps1 -SamAccountName ebrooks -WhatIf   # preview only
#

#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SamAccountName
)

Import-Module ActiveDirectory

$DomainDN   = (Get-ADDomain).DistinguishedName
$DisabledOU = "OU=Disabled Users,OU=_CORP,$DomainDN"

$user = Get-ADUser -Identity $SamAccountName -Properties MemberOf, Description, Department
$groups = $user.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }

Write-Host "`nOffboarding $($user.Name) ($SamAccountName), $($user.Department)" -ForegroundColor Cyan
Write-Host "  Groups: $(if ($groups) { $groups -join ', ' } else { '(none besides Domain Users)' })"

if ($PSCmdlet.ShouldProcess($user.Name, 'Disable, remove groups, move to Disabled Users')) {
    Disable-ADAccount -Identity $user
    Write-Host "  disabled account" -ForegroundColor Green

    foreach ($g in $user.MemberOf) {
        Remove-ADGroupMember -Identity $g -Members $user -Confirm:$false
    }
    if ($groups) { Write-Host "  removed from: $($groups -join ', ')" -ForegroundColor Green }

    $stamp = "Disabled {0:yyyy-MM-dd} by {1}" -f (Get-Date), $env:USERNAME
    Set-ADUser -Identity $user -Description $stamp
    Write-Host "  description: $stamp" -ForegroundColor Green

    Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledOU
    Write-Host "  moved to $DisabledOU" -ForegroundColor Green

    $logDir = Join-Path $PSScriptRoot 'logs'
    New-Item -ItemType Directory -Force $logDir | Out-Null
    [pscustomobject]@{
        Date           = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Username       = $SamAccountName
        Name           = $user.Name
        Department     = $user.Department
        RemovedGroups  = $groups -join ';'
        OffboardedBy   = $env:USERNAME
    } | Export-Csv (Join-Path $logDir 'offboarding-log.csv') -NoTypeInformation -Append

    Write-Host "`nDone.`n" -ForegroundColor Cyan
}
