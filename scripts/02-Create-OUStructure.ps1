#
# 02-Create-OUStructure.ps1
# Builds the company OU structure and department security groups in lab.local.
#
#   lab.local
#   └── _CORP
#       ├── Users
#       │   ├── IT
#       │   ├── HR
#       │   ├── Finance
#       │   ├── Sales
#       │   └── Marketing
#       ├── Groups          (GG_IT, GG_HR, GG_Finance, GG_Sales, GG_Marketing)
#       ├── Workstations    (domain-joined client PCs go here)
#       └── Disabled Users  (offboarded accounts)
#
# Safe to run more than once: anything that already exists is skipped.
# Run on DC01 as LAB\Administrator.
#

#Requires -Modules ActiveDirectory
Import-Module ActiveDirectory

$DomainDN    = (Get-ADDomain).DistinguishedName
$Departments = @('IT', 'HR', 'Finance', 'Sales', 'Marketing')

function New-OUIfMissing {
    param([string]$Name, [string]$Path)
    $dn = "OU=$Name,$Path"
    if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue) {
        Write-Host "  exists   OU  $dn" -ForegroundColor DarkGray
    } else {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
        Write-Host "  created  OU  $dn" -ForegroundColor Green
    }
    return $dn
}

Write-Host "`nCreating OU structure in $DomainDN" -ForegroundColor Cyan

$CorpOU     = New-OUIfMissing -Name '_CORP'          -Path $DomainDN
$UsersOU    = New-OUIfMissing -Name 'Users'          -Path $CorpOU
$GroupsOU   = New-OUIfMissing -Name 'Groups'         -Path $CorpOU
$null       = New-OUIfMissing -Name 'Workstations'   -Path $CorpOU
$null       = New-OUIfMissing -Name 'Disabled Users' -Path $CorpOU

foreach ($dept in $Departments) {
    $null = New-OUIfMissing -Name $dept -Path $UsersOU
}

Write-Host "`nCreating department security groups in $GroupsOU" -ForegroundColor Cyan

foreach ($dept in $Departments) {
    $groupName = "GG_$dept"
    if (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue) {
        Write-Host "  exists   GRP $groupName" -ForegroundColor DarkGray
    } else {
        New-ADGroup -Name $groupName -SamAccountName $groupName `
            -GroupCategory Security -GroupScope Global `
            -Path $GroupsOU -Description "All $dept department staff"
        Write-Host "  created  GRP $groupName" -ForegroundColor Green
    }
}

Write-Host "`nDone. Refresh Active Directory Users and Computers (F5) to see _CORP.`n" -ForegroundColor Cyan
