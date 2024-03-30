<#
.SYNOPSIS
Deploys an OVA file with custom user-data and hostname configurations, and sets the network adapter connection type.

.DESCRIPTION
This cmdlet takes an OVA file, user-data and metadata template files, a hostname, a network configuration, and a set of variables as input. It generates the final user-data and metadata files based on the provided templates and variables, encodes the user-data file content to Base64, and then uses the ovftool utility to deploy the OVA with the specified hostname, encoded user-data, and network configuration. After deployment, it updates the VMX file to set the network adapter connection type to the specified value.

.PARAMETER OvaPath
The path to the OVA file to be deployed.

.PARAMETER UserDataTemplatePath
The path to the user-data template file (e.g., cloud-init configuration template).

.PARAMETER MetadataTemplatePath
The path to the metadata template file (e.g., cloud-init network config template).

.PARAMETER Hostname
The desired hostname for the deployed virtual machine.

.PARAMETER OutputPath
The path to the directory where the deployed virtual machine files will be extracted.

.PARAMETER ConnectionType
The desired connection type for the network adapter (e.g., "VMnet0" for bridged networking).

.PARAMETER Variables
A hashtable containing the variables to be replaced in the user-data and metadata template files.

.EXAMPLE
# Retrieve secrets from 1Password
$sshHostRsaPrivateKey = op read "op://Dev/billy_ssh/private key"
$sshHostRsaPublicKey = op read "op://Dev/billy_ssh/public key"
$adminSshPublicKey = op read "op://Dev/matt ssh/public key"
$rootSshPublicKey = op read "op://Dev/matt ssh/public key"

# Define variables
$variables = @{
    "fqdn" = "billy.shamsway.net"
    "hostname" = "billy"
    "ssh_host_rsa_private_key" = $sshHostRsaPrivateKey
    "ssh_host_rsa_public_key" = $sshHostRsaPublicKey
    "admin_username" = "matt"
    "admin_ssh_authorized_key" = $adminSshPublicKey
    "root_ssh_authorized_key" = $rootSshPublicKey
    "instance_id" = "billy"
    "ip_address" = "192.168.252.8"
    "subnet_mask" = "24"
    "gateway" = "192.168.252.1"
    "dns_search_suffixes" = "shamsway.net"
    "dns_resolvers" = "192.168.252.1"
}

Deploy-OvaWithUserData -OvaPath "path/to/ova" -UserDataTemplatePath "path/to/user-data-template.yml" -MetadataTemplatePath "path/to/metadata-template.yml" -Hostname "billy.shamsway.net" -OutputPath "path/to/output" -ConnectionType "VMnet0" -Variables $variables

This example deploys the OVA file located at "path/to/ova" with the user-data and metadata generated from the templates at "path/to/user-data-template.yml" and "path/to/metadata-template.yml", respectively. The templates are populated with the values from the $variables hashtable, which includes secrets retrieved from 1Password using the 'op read' command. The resulting virtual machine is set to have the hostname "billy.shamsway.net", and its files are extracted to the "path/to/output" directory. The network adapter connection type is set to "VMnet0".
#>
function Deploy-OvaWithUserData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OvaPath,

        [Parameter(Mandatory = $true)]
        [string]$UserDataPath,

        [Parameter(Mandatory = $true)]
        [string]$MetadataPath,

        [Parameter(Mandatory = $true)]
        [string]$Hostname,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [string]$ConnectionType

        [Parameter(Mandatory = $true)]
        [string]$UserDataTemplatePath,

        [Parameter(Mandatory = $true)]
        [string]$MetadataTemplatePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Variables        
    )

# Check if the output directory for the deployed VM exists and delete it
    $vmOutputPath = Join-Path -Path $OutputPath -ChildPath $Hostname
    if (Test-Path $vmOutputPath) {
        Write-Host "Deleting existing output directory: $vmOutputPath"
        Remove-Item -Path $vmOutputPath -Recurse -Force
    }
    # Encode the user-data file content to Base64
    # $encodedUserData = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path $UserDataPath -Raw)))

    # Encode the Metadata configuration file content to Base64
    # $encodedMetadata = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path $MetadataPath -Raw)))

    # Generate the user-data and metadata files
    $userDataPath = Join-Path -Path $env:TEMP -ChildPath "user-data.yml"
    $metadataPath = Join-Path -Path $env:TEMP -ChildPath "metadata.yml"
    New-CloudInitConfig -UserDataTemplatePath $UserDataTemplatePath -MetadataTemplatePath $MetadataTemplatePath -OutputUserDataPath $userDataPath -OutputMetadataPath $metadataPath -Variables $Variables    

    # Construct the ovftool command
    $ovftoolCommand = "ovftool --name=""$Hostname"" --allowExtraConfig --extraConfig:guestinfo.hostname=""$Hostname"" --extraConfig:guestinfo.userdata=""$encodedUserData"" --extraConfig:guestinfo.userdata.encoding=""base64"" --extraConfig:guestinfo.metadata=""$encodedMetadata"" --extraConfig:guestinfo.metadata.encoding=""base64"" ""$OvaPath"" ""$OutputPath"""

    # Execute the ovftool command
    Write-Host "Executing: $ovftoolCommand"
    Invoke-Expression $ovftoolCommand

    # Set the network adapter connection type
    Write-Host "Modifying VMX network settings"    
    $vmxPath = Join-Path -Path $OutputPath -ChildPath "$Hostname\\$Hostname.vmx"
    (Get-Content $vmxPath) -replace 'ethernet0.connectionType = ".*"', "ethernet0.connectionType = ""$ConnectionType""" | Set-Content $vmxPath
}

<#
.SYNOPSIS
Starts a VMware Workstation virtual machine.

.DESCRIPTION
This cmdlet starts a VMware Workstation virtual machine using the vmrun utility. It accepts the path to the VMX file and an optional switch to launch the virtual machine's GUI.

.PARAMETER VmxPath
The path to the VMX file of the virtual machine.

.PARAMETER LaunchGui
Switch to launch the virtual machine's GUI. If not specified, the virtual machine will start in the background.

.EXAMPLE
Start-WorkstationVm -VmxPath "H:\VMs\billy.shamsway.net\billy.shamsway.net.vmx" -LaunchGui

This example starts the virtual machine located at "H:\VMs\billy.shamsway.net\billy.shamsway.net.vmx" and launches its GUI.
#>
function Start-WorkstationVm {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$VmxPath,

        [Parameter(Mandatory = $false)]
        [switch]$LaunchGui
    )

    $vmrunPath = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun"
    $arguments = @("-T", "ws", "start", "`"$VmxPath`"")

    if ($LaunchGui) {
        $arguments += "gui"
    }

    & $vmrunPath $arguments
}

<#
.SYNOPSIS
Stops a VMware Workstation virtual machine.

.DESCRIPTION
This cmdlet stops a VMware Workstation virtual machine using the vmrun utility. It accepts the path to the VMX file of the virtual machine.

.PARAMETER VmxPath
The path to the VMX file of the virtual machine.

.EXAMPLE
Stop-WorkstationVm -VmxPath "H:\VMs\billy.shamsway.net\billy.shamsway.net.vmx"

This example stops the virtual machine located at "H:\VMs\billy.shamsway.net\billy.shamsway.net.vmx".
#>
function Stop-WorkstationVm {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$VmxPath
    )

    $vmrunPath = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun"
    $arguments = @("-T", "ws", "stop", "`"$VmxPath`"")

    & $vmrunPath $arguments
}

<#
.SYNOPSIS
Gets the guest IP address of a VMware Workstation virtual machine.

.DESCRIPTION
This cmdlet retrieves the guest IP address of a VMware Workstation virtual machine using the vmrun utility. It accepts the folder path and hostname of the virtual machine to construct the path to the VMX file.

.PARAMETER VMFolderPath
The path to the folder containing the virtual machine files.

.PARAMETER Hostname
The hostname of the virtual machine.

.EXAMPLE
Get-WorkstationVmGuestIpAddress -VMFolderPath "H:\VMs" -Hostname "billy.shamsway.net"

This example retrieves the guest IP address of the virtual machine located at "H:\VMs\billy.shamsway.net\billy.shamsway.net.vmx".
#>
function Get-WorkstationVmGuestIpAddress {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$VMFolderPath,

        [Parameter(Mandatory = $true)]
        [string]$Hostname
    )

    $vmrunPath = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun"
    $vmxPath = Join-Path -Path (Join-Path -Path $VMFolderPath -ChildPath $Hostname) -ChildPath "$Hostname.vmx"
    $arguments = "-T ws getGuestIPAddress ""$vmxPath"" -wait"

    $ipAddress = & $vmrunPath $arguments | Select-String -Pattern "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"

    if ($ipAddress) {
        Write-Output $ipAddress.Matches.Value
    } else {
        Write-Warning "Could not retrieve guest IP address for $vmxPath"
    }
}

function New-CloudInitConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserDataTemplatePath,

        [Parameter(Mandatory = $true)]
        [string]$MetadataTemplatePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputUserDataPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputMetadataPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Variables
    )

    $userDataTemplate = Get-Content -Path $UserDataTemplatePath -Raw
    $metadataTemplate = Get-Content -Path $MetadataTemplatePath -Raw

    foreach ($key in $Variables.Keys) {
        $userDataTemplate = $userDataTemplate.Replace('${' + $key + '}', $Variables[$key])
        $metadataTemplate = $metadataTemplate.Replace('${' + $key + '}', $Variables[$key])
    }

    $userDataTemplate | Set-Content -Path $OutputUserDataPath
    $metadataTemplate | Set-Content -Path $OutputMetadataPath
}