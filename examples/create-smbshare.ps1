#New-Item -ItemType Directory -Path "C:\SharedFolder"
New-SmbShare -Name "Recordings" -Path "H:\Recordings" -FullAccess "Everyone"
New-NetFirewallRule -DisplayName "SMB Inbound" -Direction Inbound -LocalPort 445 -Protocol TCP -Action Allow
Set-NetFirewallRule -DisplayGroup "File and Printer Sharing" -Enabled True

Get-SmbShare

New-LocalUser -Name "smbuser" -Password (ConvertTo-SecureString -AsPlainText "uGgKWn-dz6rZP.vc" -Force) -Description "File Share User"
Add-LocalGroupMember -Group "Users" -Member "smbuser"

$acl = Get-Acl -Path "H:\Recordings"
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("smbuser", "ReadAndExecute, Write, Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
$acl.SetAccessRule($accessRule)
Set-Acl -Path "H:\Recordings" -AclObject $acl

New-SmbShare -Name "Recordings" -Path "H:\Recordings" -FullAccess "smbuser"