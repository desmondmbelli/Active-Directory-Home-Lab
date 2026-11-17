# Active Directory and User Provisioning Lab

In this project I built a small company network from scratch in VirtualBox: a Windows Server 2025 domain controller, a Windows 11 workstation joined to the domain, and PowerShell scripts that onboard and offboard users from a CSV file. I then worked through the tasks a help desk handles every day: password resets, account lockouts and disabling leavers.

_**Inception State:**_ two empty virtual machines, two evaluation ISOs, and no network, domain, users or policies.

_**Completion State:**_ a working `lab.local` domain with a department OU structure, 15 users in role-based security groups, a domain-joined Windows 11 PC that domain users can sign in to, an account lockout policy enforced by Group Policy, and tested scripts for onboarding and offboarding.

---

<img width="900" alt="Domain user signed in on CLIENT01" src="screenshots/28-domain-user-logged-in.png">

_Olivia Carter, created by the provisioning script from one line of a CSV, signed in on the domain-joined workstation. Authenticated by DC01 and placed in the Sales security group automatically._

# Technology Utilized
- Oracle VirtualBox 7.2 (NAT Network)
- Windows Server 2025 Standard Evaluation (Active Directory Domain Services, DNS, Group Policy)
- Windows 11 Enterprise Evaluation
- PowerShell (ActiveDirectory module)
- DISM, diskpart, bcdboot and bootsect for manual Windows deployment

# Table of Contents
- [Lab Design](#lab-design)
- [Step 1) Building the Virtual Network and Domain Controller VM](#step-1-building-the-virtual-network-and-domain-controller-vm)
- [Step 2) Preparing the Server: Name, Static IP and Time Zone](#step-2-preparing-the-server-name-static-ip-and-time-zone)
- [Step 3) Installing AD DS and Creating the lab.local Forest](#step-3-installing-ad-ds-and-creating-the-lablocal-forest)
- [Step 4) Building the OU Structure and Security Groups](#step-4-building-the-ou-structure-and-security-groups)
- [Step 5) Provisioning Users: Manually and from a CSV](#step-5-provisioning-users-manually-and-from-a-csv)
- [Step 6) Deploying the Windows 11 Workstation](#step-6-deploying-the-windows-11-workstation)
- [Step 7) Joining CLIENT01 to the Domain](#step-7-joining-client01-to-the-domain)
- [Step 8) Signing In as a Domain User](#step-8-signing-in-as-a-domain-user)
- [Step 9) Help Desk Tasks: Password Reset, Lockout Policy and Unlock](#step-9-help-desk-tasks-password-reset-lockout-policy-and-unlock)
- [Step 10) Offboarding a Leaver with PowerShell](#step-10-offboarding-a-leaver-with-powershell)
- [Troubleshooting](#troubleshooting)
- [Lab Outcome Summary](#lab-outcome-summary)
- [Scripts](#scripts)
- [Next Steps](#next-steps)

---

### Lab Design

```mermaid
flowchart LR
    subgraph host["Host PC (Windows 11, VirtualBox 7.2)"]
        subgraph net["NAT Network: ADLab 10.0.10.0/24 (VirtualBox DHCP off)"]
            DC01["DC01<br/>Windows Server 2025<br/>10.0.10.10<br/>AD DS + DNS"]
            CLIENT01["CLIENT01<br/>Windows 11 Enterprise<br/>10.0.10.20<br/>DNS → 10.0.10.10"]
        end
    end
    CLIENT01 -- "domain join, Kerberos sign-in, DNS" --> DC01
    net -- "gateway 10.0.10.1" --> Internet((Internet))
```

| | DC01 | CLIENT01 |
|---|---|---|
| OS | Windows Server 2025 Standard Evaluation (Desktop Experience) | Windows 11 Enterprise Evaluation |
| Role | Domain controller and DNS for `lab.local` | Domain-joined workstation |
| RAM / CPU | 4 GB / 1 vCPU | 6 GB / 2 vCPU |
| Disk | 60 GB | 72 GB |
| Firmware | UEFI | BIOS (see [Troubleshooting](#troubleshooting)) |
| IP | 10.0.10.10 (static) | 10.0.10.20 (static) |

```
lab.local
└── _CORP
    ├── Users
    │   ├── IT          Amara Okafor, Daniel Reyes, Priya Nair, Test Admin
    │   ├── HR          Marcus Bennett, Sofia Lindqvist
    │   ├── Finance     James Whitfield, Grace Mensah, Kenji Watanabe
    │   ├── Sales       Olivia Carter, Fatima Haddad
    │   └── Marketing   Lucas Moreau, Chloe Adeyemi, Daniel Rivera
    ├── Groups          GG_IT, GG_HR, GG_Finance, GG_Sales, GG_Marketing
    ├── Workstations    CLIENT01
    └── Disabled Users  Ethan Brooks (offboarded)
```

All user names are fictional.

---

### Step 1) Building the Virtual Network and Domain Controller VM

I created both VMs and a VirtualBox NAT Network called `ADLab` (10.0.10.0/24) with VirtualBox's own DHCP turned off. In a real domain the server, not the hypervisor, decides how clients find their DNS.

<img width="700" alt="VirtualBox Manager with both VMs" src="screenshots/01-virtualbox-vms.png">

I installed Windows Server 2025 manually with Desktop Experience. I skipped VirtualBox's unattended install so I could choose the edition and set the Administrator password myself.

<img width="700" alt="Installing Windows Server" src="screenshots/04-server-installing.webp">

<img width="700" alt="Server Manager first login" src="screenshots/05-server-manager-first-login.webp">

### Step 2) Preparing the Server: Name, Static IP and Time Zone

A domain controller needs a permanent name and address before it's promoted. I:
- matched the time zone to the host, because Kerberos authentication fails if clocks drift too far apart
- set a static IP of 10.0.10.10 with DNS pointing at itself (127.0.0.1), since the DC will be the domain's DNS server
- renamed the server from its random `WIN-…` name to `DC01`

<img width="420" alt="Static IP settings" src="screenshots/07-static-ip-settings.png">

| Before | After |
|---|---|
| <img width="450" alt="Before" src="screenshots/06-local-server-before-config.webp"> | <img width="450" alt="After" src="screenshots/08-local-server-after-config.webp"> |

### Step 3) Installing AD DS and Creating the lab.local Forest

I added the Active Directory Domain Services role with its management tools, then promoted DC01 to the first domain controller of a new forest, `lab.local`.

<img width="450" alt="Add AD DS role" src="screenshots/09-add-adds-role.png">

<img width="700" alt="AD DS installed" src="screenshots/10-adds-install-succeeded.png">

<img width="700" alt="New forest lab.local" src="screenshots/11-new-forest-lab-local.png">

<img width="700" alt="Domain controller options" src="screenshots/11b-domain-controller-options.png">

On the Review Options page I exported the PowerShell the wizard runs. It's saved as [`01-Install-ADDSForest.ps1`](scripts/01-Install-ADDSForest.ps1), so the same deployment can be repeated without the GUI.

<img width="500" alt="Deployment script" src="screenshots/11c-adds-deployment-script.png">

The only prerequisite warning was about DNS delegation, which is expected for a `.local` domain with no parent zone.

<img width="700" alt="Prerequisites passed" src="screenshots/12-prereq-check-passed.png">

<img width="900" alt="DC01 now a member of lab.local" src="screenshots/13-dc01-domain-lab-local-aduc.webp">

### Step 4) Building the OU Structure and Security Groups

[`02-Create-OUStructure.ps1`](scripts/02-Create-OUStructure.ps1) builds a `_CORP` OU with sub-OUs for each department, a Groups OU, a Workstations OU and a Disabled Users OU, plus one global security group per department (`GG_IT`, `GG_Sales` and so on). The script checks for each object first, so it can be run again safely.

<img width="800" alt="OU script output" src="screenshots/15-script-ou-structure.webp">

<img width="700" alt="OU tree in ADUC" src="screenshots/16-aduc-ou-structure.png">

<img width="700" alt="Department security groups" src="screenshots/16b-aduc-groups.png">

### Step 5) Provisioning Users: Manually and from a CSV

I created one user by hand first, to show the manual process the script replaces, and added them to their department group through the Member Of tab.

<img width="450" alt="Manual user creation" src="screenshots/17-manual-user-create.png">

<img width="420" alt="Group membership" src="screenshots/17b-manual-user-memberof.png">

Then [`03-New-ADUsersFromCSV.ps1`](scripts/03-New-ADUsersFromCSV.ps1) created the other 14 users from [`users.csv`](scripts/users.csv) in one run. For each row it:
- generates a username from first initial + last name (numbered if already taken)
- creates the account in the matching department OU with title, department and company filled in
- sets a temporary password and forces a change at first sign-in
- adds the user to their department group
- writes a log of the result to [`scripts/logs`](scripts/logs)

The temporary password is typed at run time and checked against the domain password policy before anything is created. No passwords are stored in the repo.

<img width="800" alt="Bulk provisioning output" src="screenshots/18-script-bulk-users.webp">

### Step 6) Deploying the Windows 11 Workstation

This step took the most work, because Windows 11 Setup refused to install on this VM (details in [Troubleshooting](#troubleshooting)). I deployed it the way IT teams image machines instead: from the installer's command prompt I partitioned the disk with `diskpart`, applied the Windows image with `dism /apply-image`, and wrote boot files with `bcdboot`.

<img width="700" alt="DISM apply complete" src="screenshots/20f-dism-apply-complete.png">

<img width="700" alt="Windows 11 desktop" src="screenshots/21-client01-desktop.webp">

The client got a static IP with **DC01 as its only DNS server**. Domain members find their domain controller through DNS, so this is the setting that makes everything else work.

<img width="700" alt="Client IP configuration" src="screenshots/22a-client01-ip-config.png">

<img width="600" alt="DNS resolves lab.local" src="screenshots/22b-client01-dns-test.png">

With DNS working through DC01, the client could reach the internet and activate its evaluation licence.

<img width="700" alt="Activation" src="screenshots/23-client01-activation.png">

### Step 7) Joining CLIENT01 to the Domain

One command renames the PC and joins it to the domain using domain admin credentials:

```powershell
Add-Computer -DomainName lab.local -NewName CLIENT01 -Credential LAB\Administrator -Restart
```

<img width="800" alt="Domain join command" src="screenshots/24-domain-join-command.png">

New computers land in the default `Computers` container. That's a container, not an OU, so Group Policy can't be linked to it. I moved CLIENT01 into `_CORP\Workstations`.

<img width="700" alt="CLIENT01 in Computers" src="screenshots/25-aduc-client01-in-computers.png">

<img width="700" alt="CLIENT01 in Workstations OU" src="screenshots/26-client01-in-workstations-ou.png">

### Step 8) Signing In as a Domain User

Olivia Carter signed in on CLIENT01 with the temporary password and Windows made her change it straight away, as the script had set.

<img width="800" alt="Forced password change" src="screenshots/27-forced-password-change.webp">

Once she was in, `whoami` and `$env:LOGONSERVER` confirmed she was authenticated by DC01 and was a member of `GG_Sales`.

<img width="800" alt="Domain user signed in" src="screenshots/28-domain-user-logged-in.png">

### Step 9) Help Desk Tasks: Password Reset, Lockout Policy and Unlock

**Password reset.** I reset Grace Mensah's password from ADUC and required a change at next logon.

<img width="600" alt="Password reset" src="screenshots/29-helpdesk-password-reset.png">

**Account lockout policy.** A new domain has no lockout policy, so unlimited password guesses are allowed. In the Default Domain Policy I set accounts to lock after 5 failed attempts for 10 minutes. Windows Server 2025 also suggested allowing lockout of the built-in Administrator account, which protects it against password guessing, so I accepted that too.

<img width="600" alt="Lockout policy values" src="screenshots/30a-gpo-lockout-suggested-values.png">

<img width="700" alt="gpupdate" src="screenshots/30c-gpupdate-force.png">

**Lockout and unlock.** I locked Fatima Haddad's account on purpose with wrong passwords, then unlocked it from ADUC.

<img width="800" alt="Account locked out" src="screenshots/31-account-locked-out.webp">

<img width="600" alt="Unlocking the account" src="screenshots/32-helpdesk-account-unlock.png">

### Step 10) Offboarding a Leaver with PowerShell

[`04-Disable-ADUserOffboarding.ps1`](scripts/04-Disable-ADUserOffboarding.ps1) offboarded Ethan Brooks. I ran it with `-WhatIf` first to preview the changes, then for real. It disabled the account, recorded and removed his group memberships, stamped the description with the date and admin, moved the account to `Disabled Users`, and added a line to [`offboarding-log.csv`](scripts/logs/offboarding-log.csv). The account is kept rather than deleted, so it can be audited or restored.

<img width="800" alt="Offboarding script" src="screenshots/33-script-offboarding.png">

<img width="700" alt="Disabled Users OU" src="screenshots/34-aduc-disabled-users.png">

<img width="800" alt="Disabled user cannot sign in" src="screenshots/35-disabled-user-cannot-login.webp">

---

### Troubleshooting

#### Issue 1: The VMs froze on a black screen

DC01 showed a small black window and never booted. The VirtualBox log showed `VT-x is not available`: Windows' own hypervisor (Hyper-V, enabled through Memory Integrity / VBS) was holding the CPU's virtualization features, so VirtualBox fell back to running on top of it. In that mode the UEFI firmware hung at the multi-processor start-up stage (`DXE_AP`) whenever the VM had more than one CPU. Reducing DC01 to one vCPU fixed it.

<img width="700" alt="Frozen VM" src="screenshots/00-troubleshoot-dc01-black-screen.webp">

#### Issue 2: Windows 11 Setup refused to install

The one-CPU workaround broke Windows 11 Setup, which requires two cores.

<img width="600" alt="Two cores required" src="screenshots/20-win11-requirements-blocked.png">

I tested other firmware and CPU combinations with headless boots and found that legacy BIOS with two CPUs booted fine. BIOS mode has no Secure Boot and VirtualBox's TPM wasn't detected in it, so Setup failed on those checks instead. This build also ignored the usual `LabConfig` registry bypass and the `setup.exe /product server` workaround.

<img width="500" alt="setup.exe /product server attempt" src="screenshots/20b-win11-setup-server-mode.png">

<img width="600" alt="TPM and Secure Boot checks" src="screenshots/20d-win11-tpm-secureboot-blocked.png">

**Resolution:** I skipped Setup completely and applied the image with DISM (Step 6). Setup's hardware checks never ran.

#### Issue 3: "An operating system wasn't found"

After the DISM deployment the VM still wouldn't boot. `diskpart` showed the Windows partition without the "active" flag, which a BIOS needs to find the boot partition.

<img width="700" alt="No active partition" src="screenshots/20h-fix-diskpart-no-active-partition.png">

**Resolution:** I marked the partition active, rewrote the boot code with `bootsect /nt60 C: /mbr`, ran `bcdboot` again, and moved the hard disk ahead of the DVD drive in the boot order.

<img width="700" alt="Partition marked active" src="screenshots/20i-fix-partition-marked-active.png">

<img width="700" alt="bootsect and bcdboot" src="screenshots/20j-fix-bootsect-bcdboot.png">

#### Issue 4: The provisioning script left half-created accounts

The first version of the onboarding script created each account and set its password in a single `New-ADUser` call. My first temporary password didn't meet the domain complexity rules, and AD created all 14 accounts anyway: disabled, with no password and no group. A second run skipped them all as "already exists". The logs from both failed runs are kept in [`scripts/logs`](scripts/logs).

**Resolution:** I rewrote the script so it:
- asks for the password twice and checks it against `Get-ADDefaultDomainPasswordPolicy` before creating anything
- creates each account disabled, then sets the password, enables it and adds the group, deleting the account again if any step fails

I wrote [`05-Remove-IncompleteUsers.ps1`](scripts/05-Remove-IncompleteUsers.ps1) to clean up the leftovers. It only removes accounts that are in the CSV, disabled and have never signed in. The fixed script then created all 14 users with no errors.

#### Issue 5: The client couldn't resolve lab.local

`nslookup lab.local` timed out from CLIENT01 because DC01 was powered off. It's the only DNS server in the domain, so nothing on the client works without it. The lab now always starts DC01 first and shuts it down last.

---

### Lab Outcome Summary

| Item | Result |
|---|---|
| Domain | `lab.local` forest at Windows Server 2025 functional level |
| OUs created | 10 (by script) |
| Security groups | 5 department groups |
| Users provisioned | 15 (1 manual, 14 from CSV in a single run) |
| Workstations joined | 1 (CLIENT01, in `_CORP\Workstations`) |
| Group Policy | Account lockout: 5 attempts, 10-minute lockout, Administrator included |
| Help desk tasks tested | Password reset, forced change at logon, lockout and unlock |
| Offboarding | 1 user disabled, groups removed, moved and logged by script |
| Problems diagnosed and fixed | 5 |

---

### Scripts

| Script | Purpose |
|---|---|
| [`01-Install-ADDSForest.ps1`](scripts/01-Install-ADDSForest.ps1) | Promotes DC01 to the first DC of the `lab.local` forest (exported from the AD DS wizard) |
| [`02-Create-OUStructure.ps1`](scripts/02-Create-OUStructure.ps1) | Creates the `_CORP` OU tree and department security groups |
| [`03-New-ADUsersFromCSV.ps1`](scripts/03-New-ADUsersFromCSV.ps1) | Bulk onboarding from `users.csv` with password validation, rollback and logging |
| [`04-Disable-ADUserOffboarding.ps1`](scripts/04-Disable-ADUserOffboarding.ps1) | Offboarding: disable, remove groups, stamp, move, log. Supports `-WhatIf` |
| [`05-Remove-IncompleteUsers.ps1`](scripts/05-Remove-IncompleteUsers.ps1) | Cleanup for accounts left by a failed provisioning run. Supports `-WhatIf` |

Run them on DC01 as a domain admin, in order. Each one explains its usage in the comment block at the top.

### Next Steps

- Add a DHCP scope on DC01 so clients get IP and DNS settings automatically
- Create a file share with department folders, permissioned through the `GG_` groups and mapped with Group Policy
- Add a second domain controller for redundancy
- Schedule a report of accounts that haven't signed in for 90 days
