# Bootstrapping a Consul CA and Generating Certificates

This document provides the necessary commands to bootstrap a Consul CA and generate individual certificates using Consul's built-in CA functionality. CA private keys should be removed from disk and stored in a safe place after bootstrapping. Any remaining private keys should be secured with `chmod 600`.

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
   chown hashi:root [agent cert]
   chown hashi:root [agent key]
   ```

Example:

- Servers
`consul tls cert create -server -dc=shamsway -additional-dnsname=consul.shamsway.net -additional-dnsname=jerry.shamsway.net -additional-dnsname=bobby.shamsway.net -additional-dnsname=billy.shamsway.net -additional-ipaddress 192.168.252.6 -additional-ipaddress 192.168.252.7 -additional-ipaddress 192.168.252.8`
- Agents
`consul tls cert create -client -dc=shamsway -additional-dnsname=consul.shamsway.net -additional-dnsname=jerry-agent.shamsway.net -additional-dnsname=bobby-agent.shamsway.net -additional-dnsname=billy-agent.shamsway.net -additional-ipaddress 192.168.252.6 -additional-ipaddress 192.168.252.7 -additional-ipaddress 192.168.252.8`
- Root Agents
`consul tls cert create -client -dc=shamsway -additional-dnsname=consul.shamsway.net -additional-dnsname=jerry-agent-root.shamsway.net -additional-dnsname=bobby-agent-root.shamsway.net -additional-dnsname=billy-agent-root.shamsway.net -additional-ipaddress 192.168.252.6 -additional-ipaddress 192.168.252.7 -additional-ipaddress 192.168.252.8`
- CLI
`consul tls cert create -cli -dc=shamsway -additional-dnsname=consul.shamsway.net -additional-dnsname=jerry.shamsway.net -additional-dnsname=bobby.shamsway.net -additional-dnsname=billy.shamsway.net -additional-ipaddress 192.168.252.6 -additional-ipaddress 192.168.252.7 -additional-ipaddress 192.168.252.8`
- Set permissions
```bash
chown hashi:root [agent cert]
chown hashi:root [agent key]
```

 1. (Optional) verify certificate fino
    ```bash
    openssl x509 -in [cert] -text -noout
    ```
* Consul TLS Configuration: https://developer.hashicorp.com/consul/tutorials/archive/tls-encryption-secure-existing-datacenter
* Config block: https://developer.hashicorp.com/consul/commands/tls/ca
* Gossip Key Encryption guide: https://mpolinowski.github.io/docs/DevOps/Hashicorp/2021-08-14--hashicorp-consul-tls-encryption/2021-08-14/

### Generating Nomad Certs

Docs say to create a separate root CA for Nomad, but we have an existing Consul CA. These commands generate the necessary Nomad certs using the Consul CA.

- Servers
`nomad tls cert create -server -ca=consul-agent-ca.pem -key=consul-agent-ca-key.pem -region=home -additional-dnsname=nomad.shamsway.net -additional-dnsname=jerry.shamsway.net -additional-dnsname=bobby.shamsway.net -additional-dnsname=billy.shamsway.net -additional-ipaddress 192.168.252.6 -additional-ipaddress 192.168.252.7 -additional-ipaddress 192.168.252.8`
- Agents
`nomad tls cert create -client -ca=consul-agent-ca.pem -key=consul-agent-ca-key.pem -region=home -additional-dnsname=nomad.shamsway.net -additional-dnsname=jerry-agent.shamsway.net -additional-dnsname=bobby-agent.shamsway.net -additional-dnsname=billy-agent.shamsway.net -additional-ipaddress 192.168.252.6 -additional-ipaddress 192.168.252.7 -additional-ipaddress 192.168.252.8`
<!-- - Root Agents
`nomad tls cert create -client -ca=consul-agent-ca.pem -key=consul-agent-ca-key.pem -region=home -additional-dnsname=nomad.shamsway.net -additional-dnsname=jerry-agent-root.shamsway.net -additional-dnsname=bobby-agent-root.shamsway.net -additional-dnsname=billy-agent-root.shamsway.net -additional-ipaddress 192.168.252.6 -additional-ipaddress 192.168.252.7 -additional-ipaddress 192.168.252.8` -->
- CLI
`nomad tls cert create -cli -ca=consul-agent-ca.pem -key=consul-agent-ca-key.pem -region=home -additional-dnsname=nomad.shamsway.net -additional-dnsname=jerry.shamsway.net -additional-dnsname=bobby.shamsway.net -additional-dnsname=billy.shamsway.net -additional-ipaddress 192.168.252.6 -additional-ipaddress 192.168.252.7 -additional-ipaddress 192.168.252.8`
- Set permissions
```bash
chown hashi:root [agent cert]
chown hashi:root [agent key]
```

* Nomad TLS docs: https://developer.hashicorp.com/nomad/tutorials/transport-security/security-enable-tls
  * Pay attention to the "Switching an existing cluster to TLS" if your cluster is already running
* Nomad Gossip Encryption docs: https://developer.hashicorp.com/nomad/tutorials/transport-security/security-gossip-encryption
* Nomad/Consul Blog: https://admantium.medium.com/encrypt-status-communication-messages-in-consul-and-nomad-ef3944bb4eba

### Generate Traefik Cert

- Create Server and Client Keys:
`consul tls cert create -server -dc <datacenter> -days <validity_days> -node <node_name>`
`consul tls cert create -client -dc <datacenter> -days <validity_days> -node <node_name>`

- Example:
```bash
consul tls cert create -server -ca=consul-agent-ca.pem -key=consul-agent-ca-key.pem -dc shamsway -days 1460 -node traefik -additional-dnsname=traefik.shamsway.net
mv shamsway-server-consul-1.pem shamsway-server-traefik-1.pem
mv shamsway-server-consul-1-key.pem shamsway-server-traefik-1-key.pem
```
```bash
consul tls cert create -client -ca=consul-agent-ca.pem -key=consul-agent-ca-key.pem -days 1460 -dc shamsway -additional-dnsname=traefik.shamsway.net
mv shamsway-client-consul-2.pem shamsway-client-traefik-1.pem
mv shamsway-client-consul-2-key.pem shamsway-client-traefik-1-key.pem
```

- Copy certs to Traefik persistent storage
```bash
cat consul-agent-ca.pem >> shamsway-server-traefik-1.pem
cp shamsway-client-traefik* /mnt/services/traefik/
cp shamsway-server-traefik* /mnt/services/traefik/
chown hashi:hashi /mnt/services/traefik/*.pem
```

## Consul Connect CA config

- View Consul Connect CA certificates
`curl http://127.0.0.1:8500/v1/connect/ca/roots | jq`

- View Consul Connect config
`consul connect ca get-config`

- Create Consul Connect CA payload
`./create-consul-connect-ca-payload.sh`

- Set Consul Connect config
`consul connect ca set-config -config-file=[file.json]`

- Check for and fix missing proxy defaults (bug?)
`curl http://localhost:8500/v1/config/proxy-defaults/global`
Error? Run this curl command
```bash
curl --location --request PUT 'http://localhost:8500/v1/config' \
--header 'Content-Type: application/json' \
--data '{ "Kind": "proxy-defaults", "Name": "global", "Protocol":"http" }'
```
- Verify cert
`curl http://127.0.0.1:8500/v1/agent/connect/ca/leaf/web | jq`

Consul Connect CA docs: https://developer.hashicorp.com/consul/docs/connect/ca
Consul Connect CA commands: https://developer.hashicorp.com/consul/commands/connect/ca
Consul Connect API docs: https://developer.hashicorp.com/consul/api-docs/connect/ca#update-ca-configuration

### Permissive mTLS

Allow outgoing non-mTLS traffic
```hcl
Kind = "mesh"

TransparentProxy {
  MeshDestinationsOnly = false
}
```

Allow permissive mTLS modes for incoming traffic
```hcl
Kind = "mesh"

AllowEnablingPermissiveMutualTLS = true
TransparentProxy {
  MeshDestinationsOnly = false
}
```

## Generating Individual Certificates

Once the Consul CA is bootstrapped, you can generate individual certificates for your services or nodes using the following commands:

1. Generate a certificate for a service:
   ```bash
   consul tls cert create -server -dc <datacenter> -days <validity_days> -service <service_name>
   ```
   Replace `<datacenter>` with the desired datacenter name, `<validity_days>` with the number of days the certificate should be valid for, and `<service_name>` with the name of the service.

   Example:
   ```bash
   consul tls cert create -server -dc shamsway -days 1460 -service nomad
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