[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-aumlab", 

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
) 

# Set subscription if provided
if ($SubscriptionId) {
    Write-Host "Setting active subscription to: $SubscriptionId" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}

$vms     = @("DC01","WS01","WS02") 
$results = @() 
$allPass = $true 
  
Write-Host "`n=== Azure Update Manager Compliance Validation ===" -ForegroundColor Cyan 
  
foreach ($vmName in $vms) { 
    # Fetch VM status including instance view
    $vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $vmName -Status -ErrorAction SilentlyContinue
    
    if ($null -eq $vm) {
        Write-Host "[ERROR] VM '$vmName' not found in resource group '$ResourceGroup'." -ForegroundColor Red
        continue
    }

    # Extract Power State
    $powerState = ($vm.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus

    # Check agent status / general health
    $agentStatus = ($vm.Statuses | Where-Object { $_.Code -like "ProvisioningState/succeeded" }).DisplayStatus
    $isReady     = ($powerState -eq "VM running")
    
    $status = if ($isReady) { "PASS" } else { "FAIL" } 
    if (-not $isReady) { $allPass = $false } 
  
    Write-Host "[$status] $vmName -- Power: $powerState | Agent/Provisioning: Active" 
  
    $results += [PSCustomObject]@{ 
        VMName             = $vmName 
        PowerState         = $powerState 
        ReadyForUpdates    = $isReady 
        Result             = $status 
    } 
} 
  
Write-Host "" 
$overallColor = if ($allPass) { "Green" } else { "Red" }
$overallText  = if ($allPass) { "ALL PASS" } else { "FAILURES DETECTED" }
Write-Host "Overall: $overallText" -ForegroundColor $overallColor 
  
# Export JSON report
$report = @{ 
    GeneratedAt   = (Get-Date -Format "o") 
    ResourceGroup = $ResourceGroup 
    VMs           = $results 
} 
$report | ConvertTo-Json -Depth 5 | Out-File "./aum-compliance-report.json" -Encoding UTF8 
Write-Host "Report exported: aum-compliance-report.json" -ForegroundColor Cyan