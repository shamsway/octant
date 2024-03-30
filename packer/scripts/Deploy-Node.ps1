Import-Module H:/git/octant-private/packer/scripts/DeployOvaUtils -Force

# Retrieve secrets from 1Password and store them in variables
$sshHostRsaPublicKey = op read "op://Dev/jerry_ssh/public key"
$adminSshPublicKey = op read "op://Dev/matt ssh/public key"
$rootSshPublicKey = op read "op://Dev/matt ssh/public key"

# Write the private key to a temporary file
$privateKeyFile = Join-Path -Path $env:TEMP -ChildPath "ssh_host_rsa_private_key.pem"
op read --out-file $privateKeyFile "op://Dev/jerry_ssh/private key"

# Read the private key from the file
$sshHostRsaPrivateKey = Get-Content -Path $privateKeyFile -Raw

$variables = @{
    "fqdn" = "jerry.shamsway.net"
    "hostname" = "jerry"
    "ssh_host_rsa_private_key" = $sshHostRsaPrivateKey
    "ssh_host_rsa_public_key" = $sshHostRsaPublicKey
    "admin_username" = "matt"
    "admin_ssh_authorized_key" = $adminSshPublicKey
    "root_ssh_authorized_key" = $rootSshPublicKey
    "instance_id" = "jerry"
    "ip_address" = "192.168.252.6"
    "subnet_mask" = "24"
    "gateway" = "192.168.252.1"
    "dns_search_suffixes" = "shamsway.net"
    "dns_resolvers" = "192.168.252.1"
}

Deploy-OvaWithUserData -OvaPath "output-octantnode/octantnode.ova" -UserDataTemplatePath "templates/user-data-template.yml" -MetadataTemplatePath "templates/metadata-template.yml" -Hostname "jerry.shamsway.net" -OutputPath "H:\VMs" -ConnectionType "bridged" -Variables $variables

# Remove the temporary private key file
Remove-Item -Path $privateKeyFile -Force

Start-WorkstationVm -VmxPath "H:\VMs\jerry.shamsway.net\jerry.shamsway.net.vmx" -LaunchGui
Stop-WorkstationVm -VmxPath "H:\VMs\jerry.shamsway.net\jerry.shamsway.net.vmx"