# Nomad Operations

## Nomad Variables

Job-related variables
```
Variable	Description
NOMAD_ALLOC_DIR	        The path to the shared alloc/ directory. See the Runtime Task Directories documentation for more information.
NOMAD_TASK_DIR	        The path to the task local/ directory. See the Runtime Task Directories documentation for more information.
NOMAD_SECRETS_DIR	    Path to the task's secrets/ directory. See the Runtime Task Directories documentation for more information.
NOMAD_MEMORY_LIMIT	    Memory limit in MB for the task
NOMAD_MEMORY_MAX_LIMIT	The maximum memory limit the task may use if client has excess memory capacity, in MB. Omitted if task isn't configured with memory oversubscription.
NOMAD_CPU_LIMIT	        CPU limit in MHz for the task
NOMAD_CPU_CORES	        The specific CPU cores reserved for the task in cpuset list notation. Omitted if the task does not request CPU cores. For example, 0-2,7,12-14
NOMAD_ALLOC_ID	        Allocation ID of the task
NOMAD_SHORT_ALLOC_ID	The first 8 characters of the allocation ID of the task
NOMAD_ALLOC_NAME	    Allocation name of the task. This is derived from the job name, task group name, and allocation index.
NOMAD_ALLOC_INDEX	    Allocation index; useful to distinguish instances of task groups. From 0 to (count - 1). For system jobs and sysbatch jobs, this value will always be 0. The index is unique within a given version of a job, but canaries or failed tasks in a deployment may reuse the index.
NOMAD_TASK_NAME	        Task's name
NOMAD_GROUP_NAME	    Group's name
NOMAD_JOB_ID	        Job's ID, which is equal to the Job name when submitted through the command-line tool but can be different when using the API
NOMAD_JOB_NAME	        Job's name
NOMAD_JOB_PARENT_ID	    ID of the Job's parent if it has one
NOMAD_DC	            Datacenter in which the allocation is running
NOMAD_PARENT_CGROUP     The parent cgroup used to contain task cgroups (Linux only)
NOMAD_NAMESPACE	Namespace in which the allocation is running
NOMAD_REGION	Region in which the allocation is running
NOMAD_META_<key>	The metadata value given by key on the task's metadata. Any character in a key other than [A-Za-z0-9_.] will be converted to _. (Note: this is different from ${meta.<key>} which are keys in the node's metadata.)
VAULT_TOKEN	The task's Vault token. See the Vault Integration documentation for more details
```

Network-related variables
```
Network-related Variables
Variable	                        Description
NOMAD_IP_<label>	                Host IP for the given port label. See the network block documentation for more information.
NOMAD_PORT_<label>	                Port for the given port label. Driver-specified port when a port map is used, otherwise the host's static or dynamic port allocation. Services should bind to this port. See the network block documentation for more information.
NOMAD_ADDR_<label>	                Host IP:Port pair for the given port label.
NOMAD_HOST_PORT_<label>	            Port on the host for the port label. See the Mapped Ports section of the network block documentation for more information.
NOMAD_UPSTREAM_IP_<service>	        IP for the given service when defined as a Consul service mesh upstream.
NOMAD_UPSTREAM_PORT_<service>	    Port for the given service when defined as a Consul service mesh upstream.
NOMAD_UPSTREAM_ADDR_<service>	    Host IP:Port for the given service when defined as a Consul service mesh upstream.
NOMAD_ENVOY_ADMIN_ADDR_<service>	Local address 127.0.0.2:Port for the admin port of the envoy sidecar for the given service when defined as a Consul service mesh enabled service. Envoy runs inside the group network namespace unless configured for host networking.
NOMAD_ENVOY_READY_ADDR_<service>	Local address 127.0.0.1:Port for the ready port of the envoy sidecar for the given service when defined as a Consul service mesh enabled service. Envoy runs inside the group network namespace unless configured for host networking.
```

Node Attributes
```
${node.unique.id}	36 character unique client identifier
${node.region}	    Client's region	global
${node.datacenter}	Client's datacenter	dc1
${node.unique.name}	Client's name (ex: nomad-client-10-1-2-4)
${node.class}	    Client's class (ex: linux-64bit)
${node.pool}	    Client's node pool	prod
${attr.<property>}	Property given by property on the client
${meta.<key>}	    Metadata value given by key on the client
```

Common Node Properties
```
Property	                                        Description
${attr.cpu.arch}	                                CPU architecture of the client (e.g. amd64, 386)
${attr.cpu.numcores}	                            Number of CPU cores on the client. May differ from how many cores are available for reservation due to OS or configuration. See cpu.reservablecores.
${attr.cpu.reservablecores}	                        Number of CPU cores on the client available for scheduling. Number of cores used by the scheduler when placing work with resources.cores set.
${attr.cpu.totalcompute}	                        cpu.frequency × cpu.numcores but may be overridden by client.cpu_total_compute
${attr.consul.datacenter}	                        The Consul datacenter of the client (if Consul is found)
${attr.driver.<property>}	                        See the task drivers for property documentation
${attr.unique.hostname}	                            Hostname of the client
${attr.unique.network.ip-address}	                The IP address fingerprinted by the client and from which task ports are allocated
${attr.kernel.arch}	                                Kernel architecture of the client (e.g. x86_64, aarch64)
${attr.kernel.name}	                                Kernel of the client (e.g. linux, darwin)
${attr.kernel.version}	                            Version of the client kernel (e.g. 3.19.0-25-generic, 15.0.0)
${attr.platform.aws.ami-id}	                        AMI ID of the client (if on AWS EC2)
${attr.platform.aws.instance-life-cycle}	        Instance lifecycle (e.g. spot, on-demand) of the client (if on AWS EC2)
${attr.platform.aws.instance-type}	                Instance type of the client (if on AWS EC2)
${attr.platform.aws.placement.availability-zone}	Availability Zone of the client (if on AWS EC2)
${attr.os.name}	                                    Operating system of the client (e.g. ubuntu, windows, darwin)
${attr.os.version}	                                Version of the client OS
${attr.os.build}	                                Build number (e.g 14393.5501) of the client OS (if on Windows)
```

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

It is possible to run multiple Nomad agents on a single server. This can be useful in scenarios where you want to have separate Nomad environments or handle different types of workloads with different configurations.

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