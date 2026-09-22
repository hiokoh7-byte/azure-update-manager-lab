# Azure Update Manager Lab

Building a complete patch management pipeline from zero using modular Terraform: policy-based enrollment, a maintenance window, on-demand assessment, and a structured compliance report, the same workflow a cloud operations team runs in production.

![Terraform](https://img.shields.io/badge/IaC-Terraform_(Modular)-844FBA?logo=terraform&logoColor=white)
![Azure](https://img.shields.io/badge/Azure-Update_Manager-0078D4?logo=microsoftazure&logoColor=white)
![Cost](https://img.shields.io/badge/Cost-~%240.17%2Fhr-yellow)
![Status](https://img.shields.io/badge/Status-Complete-success)

## 🎥 Watch Me Live
[Watch me build this lab live →](PASTE_YOUR_LINK_HERE)

## Overview

| Field | Value |
|---|---|
| VMs | DC01 (Domain Controller) · WS01 (Member Server) · WS02 (Member Server) |
| OS | Windows Server 2022 on all three VMs, domain: aumlab.local |
| Relationship to other labs | Fully standalone, independent from Lab 1 and Lab 2. Do this first, last, or by itself |
| Deploy time | 15 to 20 minutes, DC01 domain promotion is the longest step |
| Cost | ~$0.17/hr total (~$4/day), always run `terraform destroy` when finished |
| Tools used | Terraform (modular), Azure Update Manager, Azure Policy, PowerShell 7 |
| Career relevance | Cloud Systems Administrator, Cloud Operations Engineer, Junior DevOps |

This lab is fully self-contained. Every Terraform module and PowerShell script needed to reproduce it is included below.

## The Problem This Lab Solves

Unpatched systems are one of the most common root causes of security incidents. A Windows Server missing current Critical and Security patches is a known vulnerability. The challenge at scale isn't applying patches to one server, it's knowing which machines across an entire environment are missing which patches, enforcing a consistent schedule, and producing documentation that proves compliance to auditors.

In traditional on-premises environments this was handled by WSUS, a server you had to run, maintain, and keep updated yourself. Azure Update Manager is the cloud-native replacement. It's agentless for Azure VMs, integrates with Azure Policy for automatic enrollment, maintains a compliance record per machine, and supports both scheduled patching and manual approval workflows.

This lab builds a complete patch management pipeline from zero: infrastructure deployment, policy-based enrollment, maintenance window configuration, on-demand assessment, compliance validation, and structured report export. Every step maps directly to what a cloud operations team does in production.

## The Real-World Scenario

A new CVE is disclosed with a CVSS score of 9.8. The security team asks: which of our servers are missing the patch that addresses it? The ops engineer triggers an on-demand assessment across all VMs and pulls the compliance report within 15 minutes. Affected machines are identified. An emergency maintenance window is created targeting Critical updates. Patching runs, machines reboot as required, and a new compliance report confirms all machines are now compliant. The entire workflow is automated, documented, and auditable. That's what this lab teaches.

## What You Learn Building This

| Skill | Why it matters in a real environment |
|---|---|
| Build modular Terraform infrastructure | Module-based Terraform is the professional standard beyond a few resources. Each module has a single responsibility, is independently testable, and is reusable across environments. This is the pattern used in real engineering teams |
| Use Azure Policy for automatic enrollment | Policy-based enrollment means you define the rule once and every VM that matches is automatically enrolled, including VMs created in the future. Without policy, each VM must be enrolled manually |
| Configure a maintenance window | A maintenance window is a contract with the business: patches are applied during this window, with this reboot behavior, targeting these update classifications. Without a defined window, patches either never get applied or get applied at unpredictable times |
| Understand assessment vs patching | Assessment tells you what's missing. Patching applies the fixes. A machine can be enrolled in assessment without being linked to a maintenance window, it shows compliance data but never receives automated patches |
| Trigger on-demand patch assessment | Scheduled assessments run on a cadence. On-demand assessment lets you immediately surface compliance state after a new deployment or a newly disclosed vulnerability |
| Write a compliance validation script that exports structured data | The `validate-lab.ps1` pattern, query state, print human-readable output, export machine-readable JSON, is the foundation for feeding compliance data into SIEMs, ticketing systems, and executive dashboards |

## Security Note

The lab's own documentation is upfront that the DSRM (Directory Services Restore Mode) password used during domain promotion is hardcoded in the Terraform config as a lab-only shortcut, never to be done in production. Worth being equally direct about a second instance of the same pattern: the domain admin password used for the WS01/WS02 join command is interpolated directly into the `CustomScriptExtension`'s regular `settings` block rather than `protected_settings`. Azure does not encrypt or hide `settings` the way it does `protected_settings`, so that password is visible in plaintext through the Azure portal or `Get-AzVMExtension`.

This doesn't break the lab, but it's worth naming rather than glossing over, since it's the same category of risk the Key Vault module in this same lab is specifically designed to prevent. In a production deployment, both the DSRM password and the domain join credential would be passed through `protected_settings` at minimum, or better, pulled from Key Vault at runtime the same way the VM admin password already is.

## Architecture

Azure Policy auto-enrolls every VM in the resource group into periodic patch assessment. The Maintenance Configuration defines the weekly schedule and patch classifications. Three maintenance assignments link that schedule to each individual VM. `validate-lab.ps1` queries compliance state per VM and exports a JSON report. DC01 is the domain controller; WS01 and WS02 simulate production workloads.

```
Resource Group: rg-aumlab
┌───────────────────────────────────────────────────────────────────┐
│                                                                     │
│   Azure Policy (59efceea)                                          │
│   Auto-enrolls all VMs → periodic patch assessment                 │
│         │                                                          │
│         ▼                                                          │
│   DC01 ──────┐   WS01 ──────┐   WS02 ──────┐                       │
│   Domain     │   Member     │   Member     │                       │
│   Controller │   Server     │   Server     │                       │
│         │    │        │     │        │     │                       │
│         └────┴────────┴─────┴────────┘                             │
│                        │                                            │
│                        ▼                                            │
│         Maintenance Configuration (aum-weekly-patches)              │
│         Weekly window · Critical/Security/UpdateRollup · IfRequired │
│                        │                                            │
│         3 Maintenance Assignments (one per VM)                      │
│                        │                                            │
│                        ▼                                            │
│              validate-lab.ps1 → compliance JSON report              │
└───────────────────────────────────────────────────────────────────┘
```

## Why Each Component Exists

| Component | What it does | Why it's needed and how it works |
|---|---|---|
| Modular Terraform (4 modules) | Networking, keyvault, compute, and update-manager are separate, independently managed units | Each module owns exactly one concern. Changing the VM size means editing `modules/compute/main.tf` without touching networking or update-manager, mirroring how production Terraform is organized in real engineering teams |
| `modules/networking` | VNet, subnet, NSG, subnet-NSG association | Creates the private network all three VMs attach to. The NSG restricts inbound RDP to your IP only. The subnet-NSG association is separate because Terraform manages it independently, without it the NSG exists but applies to nothing |
| `modules/keyvault` | Key Vault with RBAC model, admin password secret | Stores the VM admin password securely. `enable_rbac_authorization = true` activates the RBAC model. Without it, role assignments on the vault are silently ignored and every secret operation returns 403 |
| `modules/compute` | Three VMs, domain promotion extension, domain join extensions | DC01 gets a static private IP (10.0.1.4) so WS01 and WS02 can point DNS at a stable address. WS01 and WS02 use `depends_on` to wait for DC01's promotion extension, preventing the most common deployment failure where workstations try to join before the domain exists |
| `modules/update-manager` | Azure Policy assignment, Maintenance Configuration, three Maintenance Assignments | Policy handles enrollment (which VMs get assessed), Maintenance Configuration handles the schedule (when and what to patch), Maintenance Assignments link the schedule to each VM (who gets patched on that schedule) |
| Azure Policy assignment (policy 59efceea) | Auto-enrolls all VMs in rg-aumlab into periodic patch assessment | Without this policy, each VM must be individually enrolled. With it, any VM added to the resource group is automatically enrolled, on a schedule set by Microsoft, roughly every 24 hours |
| `azurerm_maintenance_configuration` | Defines WHEN patches run, WHICH classifications to include, and reboot behavior | `scope = InGuestPatch` applies patches inside the guest OS, not the hypervisor. `classifications_to_include` limits to Critical, Security, and UpdateRollup, not every available patch |
| `azurerm_maintenance_assignment_virtual_machine` (x3) | Links the maintenance schedule to each individual VM | Assessment and patching are separate. A VM can show compliance data without ever being patched if it's not assigned to a maintenance window. These three resources connect WS01, WS02, and DC01 to the weekly patch window |
| Static IP on DC01 (10.0.1.4) | DC01 always has the same private IP | WS01 and WS02 point their DNS here during domain join. If DC01's IP changed after a restart, DNS resolution for aumlab.local would break and the join would fail |
| `depends_on` on WS01/WS02 extensions | Enforces ordering: DC01 promotion must finish before WS01/WS02 attempt domain join | Terraform's default parallel execution would start all extensions simultaneously. `depends_on` creates an explicit ordering, domain join can't begin until `setup_dc` succeeds |
| `validate-lab.ps1` JSON export | Produces a machine-readable compliance artifact in addition to console output | JSON can be ingested by a SIEM, parsed by a ServiceNow integration, or stored in Blob Storage for historical tracking. Console output is readable by a human, JSON is consumable by downstream systems, a real compliance program needs both |

## Prerequisites

```bash
terraform -version   # Must be >= 1.5.0
az version           # Azure CLI, any recent version
pwsh --version        # PowerShell 7+
Install-Module Az -Scope CurrentUser -Force   # Az PowerShell module for validate-lab.ps1

# Confirm correct subscription
az account show

# Register Azure resource providers.
# Microsoft.Maintenance is needed for azurerm_maintenance_configuration.
# Microsoft.GuestConfiguration is needed for in-guest patching.
# Both must show Registered before terraform apply.
az provider register --namespace Microsoft.Maintenance
az provider register --namespace Microsoft.GuestConfiguration
az provider show --namespace Microsoft.Maintenance --query registrationState -o tsv
az provider show --namespace Microsoft.GuestConfiguration --query registrationState -o tsv
# Both must show: Registered
```

## Step 1 — Project Folder Structure

```powershell
New-Item -ItemType Directory -Path "$HOME\azure-update-manager-lab"
cd "$HOME\azure-update-manager-lab"
New-Item -ItemType Directory -Path modules/networking
New-Item -ItemType Directory -Path modules/keyvault
New-Item -ItemType Directory -Path modules/compute
New-Item -ItemType Directory -Path modules/update-manager
New-Item -ItemType Directory -Path scripts
```

```
azure-update-manager-lab/
├── backend.tf                     ← remote state configuration
├── versions.tf                    ← provider version requirements
├── variables.tf                   ← all input variables
├── main.tf                        ← root module wiring all 4 child modules
├── outputs.tf                     ← VM public IPs and Key Vault name
├── terraform.tfvars.example       ← safe template, commit this
├── terraform.tfvars               ← your real values, never commit this
├── .gitignore
├── modules/
│   ├── networking/main.tf         ← VNet, subnet, NSG, NSG-subnet association
│   ├── keyvault/main.tf           ← Key Vault with RBAC model + admin password secret
│   ├── compute/main.tf            ← 3 VMs, domain promotion, domain join
│   └── update-manager/main.tf     ← Azure Policy + Maintenance Config + 3 Assignments
└── scripts/
    └── validate-lab.ps1           ← compliance validation + JSON report export
```

## Step 2 — Root Terraform Files

### `backend.tf`

Already have a state storage account from Lab 1 or Lab 2? Reuse it, just update the name below. The key `aum-lab.tfstate` is unique to this lab and won't conflict with `ntfs-lab` or `rbac-lab` state files.

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "RG-TerraformState"
    storage_account_name = "REPLACE_WITH_YOUR_STORAGE_ACCOUNT_NAME"
    container_name       = "tfstate"
    key                  = "aum-lab.tfstate"
    # Separate from ntfs-lab.terraform.tfstate and rbac-lab.terraform.tfstate
    # All three labs share the same container without affecting each other
  }
}
```

First time using remote state, create the storage account now:

```bash
az group create --name RG-TerraformState --location eastus
# Name must be globally unique, 3-24 chars, lowercase and numbers only
az storage account create --name REPLACE_WITH_UNIQUE_NAME \
    --resource-group RG-TerraformState --sku Standard_LRS
az storage container create --name tfstate --account-name REPLACE_WITH_UNIQUE_NAME
# Then update backend.tf with that name before running terraform init
```

### `versions.tf`

azurerm 3.100+ is required for `azurerm_maintenance_configuration`. The random provider generates the Key Vault suffix.

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.100" }
    random  = { source = "hashicorp/random"  version = "~> 3.6"   }
  }
}
provider "azurerm" { features {} }
```

### `variables.tf`

`admin_password` is marked sensitive, Terraform never prints it in plan or apply output. Set it as an environment variable, never in a file.

```hcl
variable "location"            { type=string default="eastus" }
variable "resource_group_name" { type=string default="rg-aumlab" }
variable "admin_username"      { type=string default="labadmin" }
variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Set as TF_VAR_admin_password env var — never in a file. Min 12 chars, upper+lower+number+symbol."
}
variable "allowed_rdp_ip" {
  type        = string
  description = "Your public IP in CIDR format — e.g. 1.2.3.4/32. Find at whatismyip.com"
}
variable "domain_name"    { type=string default="aumlab.local" }
variable "domain_netbios" { type=string default="AUMLAB" }
```

### `main.tf`

Root module that calls all four child modules. The order matters: networking must exist before compute can attach to it, Key Vault must exist before compute can reference credentials, and Update Manager must run after compute because it needs the VM IDs to create maintenance assignments.

```hcl
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

module "networking" {
  source              = "./modules/networking"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allowed_rdp_ip      = var.allowed_rdp_ip
}

module "keyvault" {
  source              = "./modules/keyvault"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  admin_password      = var.admin_password
}

module "compute" {
  source              = "./modules/compute"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.networking.subnet_id
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  domain_name         = var.domain_name
  domain_netbios      = var.domain_netbios
}

# update_manager depends on compute outputs (dc01_id, ws01_id, ws02_id)
# Terraform infers this dependency automatically from the variable references
module "update_manager" {
  source              = "./modules/update-manager"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  resource_group_id   = azurerm_resource_group.main.id
  dc01_id             = module.compute.dc01_id
  ws01_id             = module.compute.ws01_id
  ws02_id             = module.compute.ws02_id
}
```

### `outputs.tf`

```hcl
output "dc01_public_ip" { value = module.compute.dc01_public_ip }
output "ws01_public_ip" { value = module.compute.ws01_public_ip }
output "ws02_public_ip" { value = module.compute.ws02_public_ip }
output "key_vault_name" { value = module.keyvault.key_vault_name }
output "resource_group" { value = azurerm_resource_group.main.name }
```

### `terraform.tfvars.example`

```hcl
location            = "eastus"
resource_group_name = "rg-aumlab"
admin_username      = "labadmin"
allowed_rdp_ip      = "YOUR_PUBLIC_IP/32"   # find at whatismyip.com — format: 1.2.3.4/32
domain_name         = "aumlab.local"
domain_netbios      = "AUMLAB"

# admin_password is NOT set here:
#   PowerShell: $env:TF_VAR_admin_password = "YourPassword123!"
#   Bash:       export TF_VAR_admin_password="YourPassword123!"
# Min 12 chars, upper + lower + number + symbol.
```

### `.gitignore`

```
terraform.tfvars
*.tfvars
!terraform.tfvars.example
terraform.tfstate
terraform.tfstate.backup
*.tfstate
.terraform/
.terraform.lock.hcl
*.tfplan
aum-compliance-report.json
```

## Step 3 — Module Files

Each module folder contains one `main.tf` file. The folder names must match exactly what's referenced in the root `main.tf` source paths.

### `modules/networking/main.tf`

Creates the VNet, subnet, NSG, and the explicit subnet-NSG association. The NSG only permits inbound RDP from your specific IP, everything else is denied by Azure's default deny-all.

```hcl
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "allowed_rdp_ip"      { type = string }

resource "azurerm_virtual_network" "main" {
  name                = "vnet-aumlab"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "main" {
  name                 = "snet-aumlab"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "main" {
  name                = "nsg-aumlab"
  location            = var.location
  resource_group_name = var.resource_group_name
  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.allowed_rdp_ip
    destination_address_prefix = "*"
  }
}

# Without this association, the NSG exists but does not protect anything
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

output "subnet_id" { value = azurerm_subnet.main.id }
```

### `modules/keyvault/main.tf`

Creates a Key Vault and stores the admin password as a secret. `enable_rbac_authorization = true` switches the vault from the legacy access policy model to the RBAC model, without it, the role assignment granting the deploying identity permission to write secrets is silently ignored, and the write fails with 403 Forbidden.

```hcl
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "admin_password"      { type = string sensitive = true }

data "azurerm_client_config" "current" {}
# random_string generates an 8-char suffix — Key Vault names must be globally unique across all of Azure
resource "random_string" "kv_suffix" { length=8 special=false upper=false }

resource "azurerm_key_vault" "main" {
  name                       = "kv-aum-${random_string.kv_suffix.result}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true   # REQUIRED — without this, 403 on all secret operations
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

# Grant the identity running terraform apply write access to secrets.
resource "azurerm_role_assignment" "kv_deployer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# depends_on ensures the role assignment propagates before Terraform
# tries to write — without this the write fails with 403
resource "azurerm_key_vault_secret" "admin_password" {
  name         = "vm-admin-password"
  value        = var.admin_password
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.kv_deployer]
}

output "key_vault_name" { value = azurerm_key_vault.main.name }
output "key_vault_id"   { value = azurerm_key_vault.main.id }
```

### `modules/compute/main.tf`

All three VMs. DC01 gets a `CustomScriptExtension` that installs AD DS and promotes to Domain Controller. WS01 and WS02 get a join extension that points DNS at 10.0.1.4, waits for `aumlab.local` to resolve, then runs `Add-Computer`. `depends_on` on both join extensions forces them to wait for DC01's promotion to finish.

```hcl
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id"           { type = string }
variable "admin_username"      { type = string }
variable "admin_password"      { type = string sensitive = true }
variable "domain_name"         { type = string }
variable "domain_netbios"      { type = string }

# Public IPs — Static so addresses are reserved immediately and do not change
resource "azurerm_public_ip" "dc01" { name="pip-dc01" location=var.location resource_group_name=var.resource_group_name allocation_method="Static" sku="Standard" }
resource "azurerm_public_ip" "ws01" { name="pip-ws01" location=var.location resource_group_name=var.resource_group_name allocation_method="Static" sku="Standard" }
resource "azurerm_public_ip" "ws02" { name="pip-ws02" location=var.location resource_group_name=var.resource_group_name allocation_method="Static" sku="Standard" }

# DC01 NIC — STATIC IP 10.0.1.4 so WS01/WS02 DNS pointing here never breaks
resource "azurerm_network_interface" "dc01" {
  name="nic-dc01" location=var.location resource_group_name=var.resource_group_name
  ip_configuration {
    name="internal" subnet_id=var.subnet_id
    private_ip_address_allocation="Static" private_ip_address="10.0.1.4"
    public_ip_address_id=azurerm_public_ip.dc01.id
  }
}
# WS01 and WS02 NICs — Dynamic IPs are fine, these VMs do not need to be a DNS target
resource "azurerm_network_interface" "ws01" {
  name="nic-ws01" location=var.location resource_group_name=var.resource_group_name
  ip_configuration { name="internal" subnet_id=var.subnet_id private_ip_address_allocation="Dynamic" public_ip_address_id=azurerm_public_ip.ws01.id }
}
resource "azurerm_network_interface" "ws02" {
  name="nic-ws02" location=var.location resource_group_name=var.resource_group_name
  ip_configuration { name="internal" subnet_id=var.subnet_id private_ip_address_allocation="Dynamic" public_ip_address_id=azurerm_public_ip.ws02.id }
}

locals {
  img = { pub="MicrosoftWindowsServer" offer="WindowsServer" sku="2022-Datacenter" ver="latest" }
}

# All three VMs use Windows Server 2022 Datacenter, Standard_B2s size
resource "azurerm_windows_virtual_machine" "dc01" {
  name="DC01" location=var.location resource_group_name=var.resource_group_name
  size="Standard_B2s" admin_username=var.admin_username admin_password=var.admin_password
  network_interface_ids=[azurerm_network_interface.dc01.id]
  os_disk { caching="ReadWrite" storage_account_type="Standard_LRS" }
  source_image_reference { publisher=local.img.pub offer=local.img.offer sku=local.img.sku version=local.img.ver }
}
resource "azurerm_windows_virtual_machine" "ws01" {
  name="WS01" location=var.location resource_group_name=var.resource_group_name
  size="Standard_B2s" admin_username=var.admin_username admin_password=var.admin_password
  network_interface_ids=[azurerm_network_interface.ws01.id]
  os_disk { caching="ReadWrite" storage_account_type="Standard_LRS" }
  source_image_reference { publisher=local.img.pub offer=local.img.offer sku=local.img.sku version=local.img.ver }
}
resource "azurerm_windows_virtual_machine" "ws02" {
  name="WS02" location=var.location resource_group_name=var.resource_group_name
  size="Standard_B2s" admin_username=var.admin_username admin_password=var.admin_password
  network_interface_ids=[azurerm_network_interface.ws02.id]
  os_disk { caching="ReadWrite" storage_account_type="Standard_LRS" }
  source_image_reference { publisher=local.img.pub offer=local.img.offer sku=local.img.sku version=local.img.ver }
}

# DC01: promote to Domain Controller via CustomScriptExtension.
# LAB ONLY: DSRM password is hardcoded. Never do this in production.
resource "azurerm_virtual_machine_extension" "setup_dc" {
  name                 = "SetupDC"
  virtual_machine_id   = azurerm_windows_virtual_machine.dc01.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  settings = jsonencode({ commandToExecute = join(" ", [
    "powershell -ExecutionPolicy Unrestricted -Command",
    "\"Install-WindowsFeature AD-Domain-Services -IncludeManagementTools;",
    "Import-Module ADDSDeployment;",
    "Install-ADDSForest -DomainName '${var.domain_name}'",
    "-DomainNetBiosName '${var.domain_netbios}'",
    "-SafeModeAdministratorPassword (ConvertTo-SecureString 'P@ssw0rd123!' -AsPlainText -Force)",
    "-InstallDns -Force\""
  ])})
}

# WS01 and WS02 join extensions.
# depends_on = [setup_dc] means these CANNOT start until DC01 promotion succeeds.
locals {
  join_cmd = join(" ", [
    "powershell -ExecutionPolicy Unrestricted -Command",
    "\"$a=Get-NetAdapter|?{$_.Status -eq 'Up'}|Select -First 1;",
    "Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ServerAddresses '10.0.1.4';",
    "do{Start-Sleep 15}until([bool](Resolve-DnsName '${var.domain_name}' -ErrorAction SilentlyContinue));",
    "Add-Computer -DomainName '${var.domain_name}'",
    "-Credential (New-Object PSCredential('${var.domain_netbios}\\${var.admin_username}',",
    "(ConvertTo-SecureString '${var.admin_password}' -AsPlainText -Force)))",
    "-Restart -Force\""
  ])
}
resource "azurerm_virtual_machine_extension" "join_ws01" {
  name="JoinDomain" virtual_machine_id=azurerm_windows_virtual_machine.ws01.id
  publisher="Microsoft.Compute" type="CustomScriptExtension" type_handler_version="1.10"
  settings    = jsonencode({ commandToExecute = local.join_cmd })
  depends_on = [azurerm_virtual_machine_extension.setup_dc]
}
resource "azurerm_virtual_machine_extension" "join_ws02" {
  name="JoinDomain" virtual_machine_id=azurerm_windows_virtual_machine.ws02.id
  publisher="Microsoft.Compute" type="CustomScriptExtension" type_handler_version="1.10"
  settings    = jsonencode({ commandToExecute = local.join_cmd })
  depends_on = [azurerm_virtual_machine_extension.setup_dc]
}

output "dc01_id"        { value = azurerm_windows_virtual_machine.dc01.id }
output "ws01_id"        { value = azurerm_windows_virtual_machine.ws01.id }
output "ws02_id"        { value = azurerm_windows_virtual_machine.ws02.id }
output "dc01_public_ip" { value = azurerm_public_ip.dc01.ip_address }
output "ws01_public_ip" { value = azurerm_public_ip.ws01.ip_address }
output "ws02_public_ip" { value = azurerm_public_ip.ws02.ip_address }
```

> **See the Security Note above** for the credential exposure risk in this module's `settings` blocks, both here and in the DC promotion extension above it.

### `modules/update-manager/main.tf`

Three distinct operations: Policy (auto-enrollment for assessment), Maintenance Configuration (the patch schedule), and Maintenance Assignments (link the schedule to each VM). Update `start_date_time` to a future date before deploying.

```hcl
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "resource_group_id"   { type = string }
variable "dc01_id"             { type = string }
variable "ws01_id"             { type = string }
variable "ws02_id"             { type = string }

# Azure Policy: auto-enroll ALL VMs in this resource group into periodic assessment.
# Policy 59efceea = built-in "Configure periodic checking for missing system updates on Azure VMs"
# This runs assessment only — it does not apply patches.
resource "azurerm_resource_group_policy_assignment" "aum_assessment" {
  name                 = "aum-periodic-assessment"
  resource_group_id    = var.resource_group_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/59efceea-0c96-497e-a4a1-4eb2290dac15"
}

# Maintenance Configuration: WHEN to patch and WHAT to patch.
# scope = InGuestPatch: patches run inside the guest OS, not at the hypervisor.
# in_guest_user_patch_mode = User: this Terraform config owns the schedule.
# classifications: Critical, Security, UpdateRollup — not all available patches.
# reboot = IfRequired: only reboots if a patch requires it.
# IMPORTANT: Update start_date_time to a future date before running terraform apply.
resource "azurerm_maintenance_configuration" "weekly" {
  name                     = "aum-weekly-patches"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  scope                    = "InGuestPatch"
  in_guest_user_patch_mode = "User"
  window {
    start_date_time = "2026-08-01 02:00"    # Update to a future date before deploying
    time_zone       = "Eastern Standard Time"
    duration        = "03:00"
    recur_every     = "Week"
  }
  install_patches {
    windows { classifications_to_include = ["Critical","Security","UpdateRollup"] }
    reboot = "IfRequired"
  }
}

# Maintenance Assignments: link the weekly schedule to each VM.
# Without these, VMs are assessed (via policy) but never automatically patched.
resource "azurerm_maintenance_assignment_virtual_machine" "dc01" {
  location                     = var.location
  maintenance_configuration_id = azurerm_maintenance_configuration.weekly.id
  virtual_machine_id           = var.dc01_id
}
resource "azurerm_maintenance_assignment_virtual_machine" "ws01" {
  location                     = var.location
  maintenance_configuration_id = azurerm_maintenance_configuration.weekly.id
  virtual_machine_id           = var.ws01_id
}
resource "azurerm_maintenance_assignment_virtual_machine" "ws02" {
  location                     = var.location
  maintenance_configuration_id = azurerm_maintenance_configuration.weekly.id
  virtual_machine_id           = var.ws02_id
}
```

## Step 4 — Validation Script

### `scripts/validate-lab.ps1`

Authenticates to Azure, queries Update Manager for patch assessment results on each VM, prints PASS/FAIL per machine, and exports `aum-compliance-report.json`. A PASS means the assessment completed successfully and no Critical or Security patches are missing. Run this after triggering assessments in Step 6.

```powershell
param([string]$ResourceGroup="rg-aumlab", [string]$SubscriptionId)

Connect-AzAccount -SubscriptionId $SubscriptionId

$vms     = @("DC01","WS01","WS02")
$results = @()
$allPass = $true

Write-Host "`n=== Azure Update Manager Compliance Validation ===" -ForegroundColor Cyan

foreach ($vm in $vms) {
    $assessment = Get-AzVMPatchAssessmentResult `
        -ResourceGroupName $ResourceGroup `
        -VMName $vm `
        -ErrorAction SilentlyContinue

    # PASS = assessment ran successfully AND no Critical/Security patches are missing.
    # A brand-new VM will often FAIL this check — it has patches outstanding.
    # This is the correct and expected result: the lab is working as designed.
    $compliant = $assessment.Status -eq "Succeeded" -and $assessment.CriticalAndSecurityPatchCount -eq 0
    $status    = if ($compliant) { "PASS" } else { "FAIL" }
    if (-not $compliant) { $allPass = $false }

    Write-Host "[$status] $vm -- Critical missing: $($assessment.CriticalAndSecurityPatchCount) | Status: $($assessment.Status)"

    $results += [PSCustomObject]@{
        VMName                   = $vm
        AssessmentStatus         = $assessment.Status
        CriticalAndSecurityCount = $assessment.CriticalAndSecurityPatchCount
        OtherPatchCount          = $assessment.OtherPatchCount
        LastAssessmentTime       = $assessment.StartDateTime
        Compliant                = $compliant
        Result                   = $status
    }
}

Write-Host ""
Write-Host "Overall: $(if ($allPass){"ALL PASS"}else{"FAILURES DETECTED"})" `
    -ForegroundColor $(if ($allPass){"Green"}else{"Red"})

# Export JSON — feeds SIEM, ServiceNow, or compliance dashboard in production
$report = @{
    GeneratedAt   = (Get-Date -Format "o")
    ResourceGroup = $ResourceGroup
    VMs           = $results
}
$report | ConvertTo-Json -Depth 5 | Out-File "./aum-compliance-report.json" -Encoding UTF8
Write-Host "Report exported: aum-compliance-report.json" -ForegroundColor Cyan
```

## Step 5 — Configure Variables and Deploy

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars:
#   allowed_rdp_ip = your current public IP from whatismyip.com in format 1.2.3.4/32

# Edit modules/update-manager/main.tf:
#   Update start_date_time to any future date — if this date is in the past, terraform plan fails

# Edit backend.tf:
#   Replace REPLACE_WITH_YOUR_STORAGE_ACCOUNT_NAME with your actual storage account name

# Set admin password as environment variable
$env:TF_VAR_admin_password = "YourStrongPassword123!"
echo $env:TF_VAR_admin_password   # If nothing prints, set it again before apply

az login && az account show
terraform init
terraform plan -out=aum-lab.tfplan
# Review — expect: 3 VMs, 1 VNet+NSG+subnet+association, 1 Key Vault,
# 1 Maintenance Configuration, 3 Maintenance Assignments, 1 Policy Assignment

terraform apply aum-lab.tfplan
# Takes 15–20 minutes — DC01 domain promotion is the longest step
```

## Step 6 — Trigger Assessment and Validate

After deployment, trigger an on-demand assessment on each VM immediately. Azure Policy will run assessments on its own schedule, but triggering manually surfaces compliance data right now.

```powershell
$subId = az account show --query id -o tsv

# Trigger on-demand assessment via the Azure REST API.
# This is the same operation the portal uses when you click "Assess Now".
# Each assessment takes 5-10 minutes per VM to complete.
foreach ($vm in @("DC01","WS01","WS02")) {
    az rest --method POST `
        --url "https://management.azure.com/subscriptions/$subId/resourceGroups/rg-aumlab/providers/Microsoft.Compute/virtualMachines/$vm/assessPatches?api-version=2022-03-01"
    Write-Host "Assessment triggered: $vm"
}

# Wait 5-10 minutes, then validate
pwsh ./scripts/validate-lab.ps1 -ResourceGroup "rg-aumlab" -SubscriptionId $subId
```

> If `validate-lab.ps1` shows FAIL with Critical missing > 0: this is expected on a brand-new VM, the machine has patches outstanding. It proves the assessment is working correctly. Apply patches via the maintenance window to resolve it, then re-run validation to confirm.

## Portal Verification Checklist

- Azure Update Manager → Machines → all 3 VMs show as Assessed
- Maintenance Configurations → aum-weekly-patches → all 3 VMs are linked
- Policy → Assignments → periodic assessment policy shows Applied on rg-aumlab

## Teardown

Always destroy when finished. ~$0.17/hr = ~$4/day = ~$28/week if left running.

```bash
terraform destroy -auto-approve

# Verify everything is removed
az group show --name rg-aumlab 2>&1
# Expected: ResourceGroupNotFound
```

## Troubleshooting

| Problem | Cause | Solution |
|---|---|---|
| Provider registration error during apply | Microsoft.Maintenance or Microsoft.GuestConfiguration not Registered | Run `az provider show` for each namespace. Wait until both show Registered, then re-apply |
| 403 on Key Vault secret during apply | `enable_rbac_authorization` missing or RBAC propagation delay | Confirm `enable_rbac_authorization=true` is in the keyvault module. Re-run `terraform apply`, it resumes from the failed resource |
| DC01 extension fails or times out | AD promotion failure or Azure timeout on extension | Re-run `terraform apply`, Terraform skips resources that already succeeded and only retries what failed. Check Azure portal → DC01 → Extensions for detailed error output |
| WS01/WS02 domain join fails, DNS not resolving | DC01 took longer than 3 minutes to finish promotion | Re-run `terraform apply`. The join extension retries, and the join script itself waits up to 3 minutes for aumlab.local DNS to resolve before attempting `Add-Computer` |
| `validate-lab.ps1` shows Status: null | Assessment was triggered but not yet complete | Wait 5 to 10 minutes and re-run the script |
| `validate-lab.ps1` shows Critical missing > 0 | Expected on a fresh VM, patches are outstanding | This is correct behavior. Trigger the maintenance window to apply patches, then re-validate |
| `start_date_time` error during plan | The date in `update-manager/main.tf` is in the past | Update `start_date_time` to any future date, e.g. next month, and re-run plan |
| `terraform apply` changes nothing after a failed run | Resources were partially created | Re-run `terraform apply`, Terraform reads current state and only creates what's missing |

## How This Lab Fits Into a Series

| Lab | What it deploys | Relationship |
|---|---|---|
| Lab 1 — NTFS File Server | DC01, FS01, CLIENT01, VNet, NSG, Key Vault in RG-FileServerLab | Standalone, creates all infrastructure from scratch |
| Lab 2 — Azure RBAC | 3 role assignments on FS01 only, no new VMs | Depends on Lab 1, reads Lab 1 resources via data sources and reuses its storage account |
| **AUM Lab — Azure Update Manager** (this lab) | DC01, WS01, WS02, VNet, Key Vault in rg-aumlab | Standalone, fully independent from Lab 1 and Lab 2 |

## Related Labs

- **Lab 1** — NTFS File Server
- **Lab 2** — Azure RBAC Access Control
- **Lab 3** — Splunk SIEM & Log Analysis
- **Lab 4** — ServiceNow ITSM
- **Lab 5** — Nessus Vulnerability Scanning
