$sshHostRsaPrivateKey = op read "op://Dev/jerry_ssh/private key"
$sshHostRsaPublicKey = op read "op://Dev/jerry_ssh/public key"
$adminSshPublicKey = op read "op://Dev/matt ssh/public key"
$rootSshPublicKey = op read "op://Dev/matt ssh/public key"

# Define variables
$variables = @{
    "fqdn" = "jerry.shamsway.net"
    "hostname" = "jerry"
    "ssh_host_rsa_private_key" = $sshHostRsaPrivateKey
    "ssh_host_rsa_public_key" = $sshHostRsaPublicKey
    "admin_username" = "matt"
    "admin_ssh_authorized_key" = $adminSshPublicKey
    "root_ssh_authorized_key" = $rootSshPublicKey
    "instance_id" = "jerry"
    "ip_address" = "192.168.252.8"
    "subnet_mask" = "24"
    "gateway" = "192.168.252.1"
    "dns_search_suffixes" = "shamsway.net"
    "dns_resolvers" = "192.168.252.1"
}

Deploy-OvaWithUserData -OvaPath "output-octantnode/octantnode.ova" -UserDataTemplatePath "user-data-template.yml" -MetadataTemplatePath "metadata-template.yml" -Hostname "jerry.shamsway.net" -OutputPath "H:\VMs" -ConnectionType "VMnet0" -Variables $variables