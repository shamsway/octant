<#
.SYNOPSIS
Deploys an OVA file to VMware Workstation with custom user-data and hostname configurations.

.DESCRIPTION
This cmdlet takes an OVA file, a user-data file, and a hostname as input. It encodes the user-data file content to Base64 and then uses the ovftool utility to deploy the OVA with the specified hostname, encoded user-data, and network configuration.

.PARAMETER OvaPath
The path to the OVA file to be deployed.

.PARAMETER UserDataPath
The path to the user-data file (e.g., cloud-init configuration).

.PARAMETER Hostname
The desired hostname for the deployed virtual machine.

.PARAMETER Network
The network configuration for the deployed virtual machine (e.g., "VMnet0" for bridged networking).

.PARAMETER OutputPath
The path to the directory where the deployed virtual machine files will be extracted.

.EXAMPLE
Deploy-OvaWithUserData -OvaPath "H:\git\octant-private\packer\output-octantnode\octantnode.ova" -UserDataPath "user-data.yml" -Hostname "billy.shamsway.net" -Network "VMnet0" -OutputPath "H:\VMs"

This example deploys the "octantnode.ova" file with the user-data from "user-data.yml", sets the hostname to "billy.shamsway.net", configures the network to "VMnet0", and extracts the virtual machine files to the "H:\VMs" directory.
#>
function Deploy-OvaWithUserData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OvaPath,

        [Parameter(Mandatory = $true)]
        [string]$UserDataPath,

        [Parameter(Mandatory = $true)]
        [string]$Hostname,

        [Parameter(Mandatory = $true)]
        [string]$Network,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    # Encode the user-data file content to Base64
    $encodedUserData = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path $UserDataPath -Raw)))

    # Construct the ovftool command
    $ovftoolCommand = "ovftool --network=""$Network"" --name=""$Hostname"" --allowExtraConfig --extraConfig:guestinfo.hostname=""$Hostname"" --extraConfig:guestinfo.userdata=""$encodedUserData"" --extraConfig:guestinfo.userdata.encoding=""base64"" ""$OvaPath"" ""$OutputPath"""

    # Execute the ovftool command
    Write-Host "Executing: $ovftoolCommand"
    Invoke-Expression $ovftoolCommand
}