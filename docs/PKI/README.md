# Bootstrapping a Consul CA and Generating Certificates

This document provides the necessary commands to bootstrap a Consul CA and generate individual certificates using Consul's built-in CA functionality.

## Prerequisites

- Consul installed on your system
- Consul agent running with appropriate configuration

## Bootstrapping a Consul CA

To bootstrap a Consul CA, follow these steps:

1. Initialize the Consul CA:
   ```bash
   consul tls ca create
   ```
   This command initializes the Consul CA and generates a self-signed root certificate.

2. Generate server and client certificates
   ```bash
   consul tls cert create -server -dc=[datacenter]
   consul tls cert create -client -dc=[datacenter]
   consul tls cert create -cli -dc=[datacenter]
   ```

Docs: https://developer.hashicorp.com/consul/commands/tls/ca

## Generating Individual Certificates

Once the Consul CA is bootstrapped, you can generate individual certificates for your services or nodes using the following commands:

1. Generate a certificate for a service:
   ```bash
   consul tls cert create -server -dc <datacenter> -days <validity_days> -service <service_name>
   ```
   Replace `<datacenter>` with the desired datacenter name, `<validity_days>` with the number of days the certificate should be valid for, and `<service_name>` with the name of the service.

   Example:
   ```bash
   consul tls cert create -server -dc dc1 -days 365 -service web
   ```

2. Generate a certificate for a node:
   ```bash
   consul tls cert create -client -dc <datacenter> -days <validity_days> -node <node_name>
   ```
   Replace `<datacenter>` with the desired datacenter name, `<validity_days>` with the number of days the certificate should be valid for, and `<node_name>` with the name of the node.

   Example:
   ```bash
   consul tls cert create -client -dc dc1 -days 365 -node node1
   ```

3. Retrieve the generated certificate and key:
   ```bash
   consul tls cert get -client -dc <datacenter> -node <node_name>
   ```
   Replace `<datacenter>` with the datacenter name and `<node_name>` with the name of the node.

   Example:
   ```bash
   consul tls cert get -client -dc dc1 -node node1
   ```
   This command retrieves the generated certificate and key for the specified node. The output will include the certificate and key in PEM format.

## Additional Commands

Here are a few additional commands that you may find useful when working with Consul's CA:

- List all certificates:
  ```bash
  consul tls cert list
  ```
  This command lists all the certificates managed by Consul.

- Revoke a certificate:
  ```bash
  consul tls cert revoke -dc <datacenter> -serial <serial_number>
  ```
  Replace `<datacenter>` with the datacenter name and `<serial_number>` with the serial number of the certificate you want to revoke.

- Configure Consul agent to use TLS:
  ```bash
  consul agent -config-file consul.hcl
  ```
  Make sure to update the `consul.hcl` configuration file with the appropriate TLS settings, such as enabling TLS and specifying the paths to the CA certificate, agent certificate, and agent key.

Remember to store the generated certificates and keys securely and distribute them to the respective services or nodes as needed.

For more detailed information and additional options, refer to the official Consul documentation on TLS encryption and the `consul tls` command.

# Automating distribution of certs

1. Ansible playbook to add a chain of certificates or multiple certificates to the list of trusted CAs:

```yaml
- name: Add CA certificates to trusted list
  hosts: all
  become: yes

  tasks:
    - name: Copy CA certificates to the server
      copy:
        src: "{{ item }}"
        dest: "/usr/local/share/ca-certificates/"
        mode: 0644
      with_items:
        - ca-cert1.crt
        - ca-cert2.crt
        - ca-cert3.crt

    - name: Update CA certificates
      command: update-ca-certificates
```

This Ansible playbook copies the specified CA certificates (`ca-cert1.crt`, `ca-cert2.crt`, `ca-cert3.crt`) to the `/usr/local/share/ca-certificates/` directory on the target servers. It then runs the `update-ca-certificates` command to update the trusted CA list.

2. PowerShell commands to add a chain of certificates or multiple certificates to the list of trusted CAs:

```powershell
$certFiles = @("C:\path\to\ca-cert1.crt", "C:\path\to\ca-cert2.crt", "C:\path\to\ca-cert3.crt")

foreach ($certFile in $certFiles) {
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certFile)
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $store.Open("ReadWrite")
    $store.Add($cert)
    $store.Close()
}
```

This PowerShell script creates an array `$certFiles` containing the file paths of the CA certificates. It then iterates over each certificate file, creates an `X509Certificate2` object for each certificate, opens the "Root" certificate store on the local machine, adds the certificate to the store, and closes the store.

3. Bash commands to add a chain of certificates or multiple certificates to the list of trusted CAs on a Debian server:

```bash
sudo cp /path/to/ca-cert1.crt /usr/local/share/ca-certificates/
sudo cp /path/to/ca-cert2.crt /usr/local/share/ca-certificates/
sudo cp /path/to/ca-cert3.crt /usr/local/share/ca-certificates/

sudo update-ca-certificates
```

These Bash commands use `sudo` to copy the CA certificate files (`ca-cert1.crt`, `ca-cert2.crt`, `ca-cert3.crt`) to the `/usr/local/share/ca-certificates/` directory. After copying the files, it runs the `update-ca-certificates` command to update the trusted CA list.

4. Zsh commands to add a chain of certificates or multiple certificates to the list of trusted CAs on macOS:

```zsh
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /path/to/ca-cert1.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /path/to/ca-cert2.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /path/to/ca-cert3.crt
```

These Zsh commands use the `security` utility with `sudo` to add the CA certificates (`ca-cert1.crt`, `ca-cert2.crt`, `ca-cert3.crt`) to the system keychain (`/Library/Keychains/System.keychain`) on macOS. The `-d` flag specifies that the certificates are used as trusted root certificates, and the `-r trustRoot` flag indicates that the certificates are trusted for all purposes.

Remember to replace the file paths (`/path/to/ca-cert1.crt`, etc.) with the actual paths to your CA certificate files.

These examples demonstrate how to add multiple CA certificates to the trusted list using different tools and platforms. Make sure to run these commands with appropriate privileges (e.g., using `sudo` or running as an administrator) to modify the system's trusted CA list.