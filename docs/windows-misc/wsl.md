# WSL Config

- Configure WSL network bridge. Link: https://develmonk.com/2021/06/05/easiest-wsl2-bridge-network-without-hyper-v-virtual-network-manager/
```bash
ip addr flush dev eth0
ip addr add 192.168.252.10/24 dev eth0
ip addr show dev eth0
ip link set eth0 up
ip route add default via 192.168.252.1 dev eth0

ip route show
ping 192.168.252.1
ping google.com

echo 'nameserver 192.168.252.1' > /etc/resolv.conf
```

- Install things

```bash
sudo apt install debian-goodies openssh-server net-tools gpg
sudo wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
sudo echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com bookworm main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt install consul nomad
```
- Configure `sudo` and Install OpenSSH server

```bash
sudo sh -c "echo '${USER} ALL=(root) NOPASSWD: ALL' >/etc/sudoers.d/matt"
sudo apt install openssh-server
sudo sed -i -E 's,^#PasswordAuthentication.*$,PasswordAuthentication yes,' /etc/ssh/sshd_config
sudo sed -i -E 's,^#?Port.*$,Port 2022,' /etc/ssh/sshd_config
sudo service ssh start
```

- Configure inbound SSH for WSL2

```pwsh
New-NetFirewallRule -DisplayName "WSL Linux SSH tcp/2022" -Direction Inbound -LocalPort 2022 -Protocol TCP -Action Allow
```

NOTE: connect with `ssh -p 2022 user@ip`