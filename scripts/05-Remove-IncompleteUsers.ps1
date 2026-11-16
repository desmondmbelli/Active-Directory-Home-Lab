#
# 05-Remove-IncompleteUsers.ps1
# Cleans up accounts left half-created by a failed provisioning run.
#
# Background: the first version of 03-New-ADUsersFromCSV.ps1 created each account
# before setting its password. When the password was rejected by the domain policy,
# the accounts were left behind disabled, with no password and no group membership,
# and later runs skipped them as "already exists". 03 now validates the password
# first and rolls back on failure; this script removes the leftovers.
#
# It only removes users that are listed in users.csv AND are still disabled AND
# have never signed in, inside OU=<Department>,OU=Users,OU=_CORP.
#
# Usage (on DC01 as LAB\Administrator):
#   .\05-Remove-IncompleteUsers.ps1 -WhatIf    # preview what would be removed
#   .\05-Remove-IncompleteUsers.ps1            # remove them
#

#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CsvPath = (Join-Path $PSScriptRoot 'users.csv')
)

Import-Module ActiveDirectory

$DomainDN = (Get-ADDomain).DistinguishedName
$removed  = 0

foreach ($r in Import-Csv $CsvPath) {
    $name = "$($r.FirstName.Trim()) $($r.LastName.Trim())"
    $ou   = "OU=$($r.Department.Trim()),OU=Users,OU=_CORP,$DomainDN"

    $user = Get-ADUser -Filter "Name -eq '$name'" -SearchBase $ou -Properties LastLogonDate -ErrorAction SilentlyContinue
    if (-not $user) { continue }

    if (-not $user.Enabled -and -not $user.LastLogonDate) {
        if ($PSCmdlet.ShouldProcess("$name ($($user.SamAccountName))", 'Remove incomplete account')) {
            Remove-ADUser -Identity $user -Confirm:$false
            Write-Host "  removed  $name ($($user.SamAccountName))" -ForegroundColor Yellow
            $removed++
        }
    } else {
        Write-Host "  kept     $name (enabled or has signed in)" -ForegroundColor DarkGray
    }
}

Write-Host "`n$removed incomplete account(s) removed.`n" -ForegroundColor Cyan
