# Nomad Operations

## Links
- https://storiesfromtheherd.com/nomad-tips-and-tricks-766878dfebf4
- Running Linux Containers on WSL using Nomad: https://dev.to/ggmueller/running-linux-containers-on-wsl-using-nomad-80o

## Update shares available to Nomad
- Edit inventory/groups.yml
- Add the new volume(s) to volumes: group
- Run configure-mounts.yml playbook
  - All hosts: 'ansible-playbook configure-mounts.yml -i inventory/groups.yml'
  - Single host: 'ansible-playbook configure-mounts.yml -i inventory/groups.yml -l [hostname]'
- Run update-nomad.yml playbook, one host at a time. This playbook drains the host, updates the Nomad configuration, and restarts the Nomad agent.
  - Single host: 'ansible-playbook update-nomad.yml -i inventory/groups.yml -l [hostname]'

## Troubleshooting

Look at all consul and nomad logs
`journalctl -u consul -u nomad -u nomad-root --since "$(date -d '-5 minutes' '+%Y-%m-%d %H:%M:%S')" -f | grep -i "register\|deregister\|threadfin"`

Get local node status
`nomad node status -self -verbose`

Get remote/root node status
`nomad node status -address=http://127.0.0.1:5646 -verbose`

List CSI plugins
`nomad operator api /v1/plugins?type=csi | jq`

### Errors

`Failed to parse job: input.hcl:146,5-6: Invalid character; This character is not used within the language.` - Check for template blocks and remove any whitespace trailing the `<<EOH` line

## Running multiple Nomad agents

Yes, it is possible to run multiple Nomad agents on a single server. This can be useful in scenarios where you want to have separate Nomad environments or handle different types of workloads with different configurations.

To run multiple Nomad agents on a single server, you need to ensure that each agent has its own unique configuration and uses different ports and directories to avoid conflicts. Here's a general approach to setting up multiple Nomad agents:

1. Create separate configuration files for each Nomad agent. For example, you can have `client1.hcl` and `client2.hcl` for two different agents.

2. In each configuration file, specify unique values for the following parameters:
   - `data_dir`: Set different data directories for each agent to store their state and data.
   - `bind_addr`: Use different IP addresses or ports for each agent to bind to.
   - `advertise`: Configure different advertise addresses or ports for each agent.
   - `ports`: Assign different port ranges for each agent to avoid conflicts.

   Here's an example of how you can differentiate the configurations:

   ```hcl
   # client1.hcl
   data_dir = "/path/to/data/dir1"
   bind_addr = "0.0.0.0"
   advertise {
     http = "127.0.0.1:4646"
     rpc  = "127.0.0.1:4647"
     serf = "127.0.0.1:4648"
   }
   ports {
     http = 4646
     rpc  = 4647
     serf = 4648
   }

   # client2.hcl
   data_dir = "/path/to/data/dir2"
   bind_addr = "0.0.0.0"
   advertise {
     http = "127.0.0.1:5646"
     rpc  = "127.0.0.1:5647"
     serf = "127.0.0.1:5648"
   }
   ports {
     http = 5646
     rpc  = 5647
     serf = 5648
   }
   ```

3. Start each Nomad agent with its respective configuration file. You can use different terminal sessions or create systemd unit files for each agent.

   ```shell
   # Start the first agent
   nomad agent -config=client1.hcl

   # Start the second agent
   nomad agent -config=client2.hcl
   ```

4. If you want to run one of the agents with root privileges (e.g., for Docker), you can start that agent using sudo or as the root user.

   ```shell
   # Start the agent with root privileges
   sudo nomad agent -config=client1.hcl
   ```

   Make sure to configure the necessary permissions and security measures when running an agent with elevated privileges.

5. Interact with each Nomad agent using their respective addresses and ports. You can use the `nomad` CLI tool or API endpoints to submit jobs, query agent information, and perform other operations.

   ```shell
   # Interact with the first agent
   nomad agent-info -address=http://127.0.0.1:4646

   # Interact with the second agent
   nomad agent-info -address=http://127.0.0.1:5646
   ```

By running multiple Nomad agents on a single server, you can have one agent running with root privileges to handle workloads that require elevated permissions (e.g., Docker), while another agent runs under a non-root user for other types of workloads.

However, keep in mind that running multiple agents on the same server may impact resource utilization and isolation. Make sure to allocate sufficient resources to each agent and consider the security implications of running an agent with elevated privileges.

If you have any further questions or need assistance with setting up multiple Nomad agents, please let me know!