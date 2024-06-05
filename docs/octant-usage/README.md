# Octant Setup and Useage

## Node deployment

### Without cloud-init

- Build VM via Packer and deploy
- Connect and login `root`/`packer`
- Set a static IP
- Copy `packer/scripts/debian-octant-config.sh` to /usr/local/bin, run `chmod +x debian-octant-config.sh`, then `./debian-octant-config.sh`
- Add admin user: `useradd -m -s /bin/bash -U -G sudo john`
- Allow passwordless sudo: `echo "john ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/john`
- Add ssh keys to `/home/[adminuser]/.ssh/authorized_keys` and `/root/.ssh/authorized_keys` and set permissions with `chmod 600 authorized_keys`
- Via console, remove any existing ssh host keys and regenerate. When prompted, keep the existing server config file. Remove public keys from `known_hosts` as needed.
```bash
rm /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server
systemctl restart sshd
```
- Add requirements role: `ROLE=requirements HOST=newhost.homelab.net make deploy-role-host`
- Copy `authorized_keys` to hashi user: 
```bash
su - hashi
mkdir .ssh
sudo cp /root/.ssh/authorized_keys .ssh/
sudo chown hashi:hashi .ssh/authorized_keys
```
- Copy SSH keys from an existing server for the `hashi` user to `/opt/homelab/data/home/.ssh`
- Secure private key: `chmod 600 id_rsa`
- Allow login for `hashi` user: `cat id_rsa.pub >> authorized_keys`
- If needed, configure ceph.
- Mount shared folders
- Add tailscale role: `ROLE=tailscale HOST=newhost.homelab.net make deploy-role-host`
- Add consul-agent role: `ROLE=consul-agent HOST=newhost.homelab.net make deploy-role-host`
- Add consul-agent-root role: `ROLE=consul-agent-root HOST=newhost.homelab.net make deploy-role-host`
- Add nomad-agent role: `ROLE=nomad-agent HOST=newhost.homelab.net make deploy-role-host`
- Add nomad-agent-root role: `ROLE=nomad-agent-root HOST=newhost.homelab.net make deploy-role-host`
## Running Ansible in check mode

ansible-playbook homelab.yml -i inventory/groups.yml --check --tags "$(ROLE)"

ansible-playbook homelab.yml -i inventory/groups.yml -l $(HOST) --check -vvv --tags "$(ROLE)"
ansible-playbook homelab.yml -i inventory/groups.yml -l jerry.shamsway.net --check -vvv --tags nomad-root

## Aliases

Add to .bashrc:

```bash
if [ -f /mnt/services/octant/bash_aliases ]; then
    source /mnt/services/octant/bash_aliases
fi
```