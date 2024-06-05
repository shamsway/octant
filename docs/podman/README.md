# Podman

## Nomad Plugin

GitHub repo: https://github.com/hashicorp/nomad-driver-podman
Example jobs: https://github.com/hashicorp/nomad-driver-podman/tree/main/examples/jobs

entrypoint - (Optional) A string list overriding the image's entrypoint. Defaults to the entrypoint set in the image. Ex:
```hcl
config {
  entrypoint = [
    "/bin/bash",
    "-c"
  ]
}
```

command - (Optional) The command to run when starting the container. Ex:
```hcl
config {
  command = "some-command"
}
```

args - (Optional) A list of arguments to the optional command. If no command is specified, the arguments are passed directly to the container. Ex:
```hcl
config {
  args = [
    "arg1",
    "arg2",
  ]
}
```

userns - (Optional) Set the user namespace mode for the container. Ex:
```hcl
config {
  userns = "keep-id:uid=200,gid=210"
}
```
Set the user namespace mode for the container. It defaults to the PODMAN_USERNS environment variable. An empty value (“”) means user namespaces are disabled unless an explicit mapping is set with the --uidmap and --gidmap options.

This option is incompatible with --gidmap, --uidmap, --subuidname and --subgidname.

Rootless user --userns=Key mappings:

|Key|Host User|Container User|
|--- |--- |--- |
|“”|$UID|0 (Default User account mapped to root user in container.)|
|keep-id|$UID|$UID (Map user account to same UID within container.)|
|keep-id:uid=200,gid=210|$UID|200:210 (Map user account to specified uid, gid value within container.)|
|auto|$UID|nil (Host User UID is not mapped into container.)|
|nomap|$UID|nil (Host User UID is not mapped into container.)|

The `--userns=auto` flag requires that the user name containers be specified in the /etc/subuid and /etc/subgid files, with an unused range of subordinate user IDs that Podman containers are allowed to allocate. See subuid(5).

Example: `containers:2147483647:2147483648`.

Podman allocates unique ranges of UIDs and GIDs from the containers subordinate user ids. The size of the ranges is based on the number of UIDs required in the image. The number of UIDs and GIDs can be overridden with the size option.

The rootless option `--userns=keep-id` uses all the subuids and subgids of the user. Using `--userns=auto` when starting new containers will not work as long as any containers exist that were started with `--userns=keep-id`.

**Valid auto options:**

* *gidmapping*=CONTAINER_GID:HOST_GID:SIZE: to force a GID mapping to be present in the user namespace.
* *size*=SIZE: to specify an explicit size for the automatic user namespace. e.g. --userns=auto:size=8192. If size is not specified, auto will estimate a size for the user namespace.
* *uidmapping*=CONTAINER_UID:HOST_UID:SIZE: to force a UID mapping to be present in the user namespace.

- `container:id`: join the user namespace of the specified container.
- `host`: run in the user namespace of the caller. The processes running in the container will have the same privileges on the host as any other process launched by the calling user (default).
- `keep-id`: creates a user namespace where the current rootless user’s UID:GID are mapped to the same values in the container. This option is not allowed for containers created by the root user.

**Valid keep-id options:**

* *uid*=UID: override the UID inside the container that will be used to map the current rootless user to.
* *gid*=GID: override the GID inside the container that will be used to map the current rootless user to.

`nomap`: creates a user namespace where the current rootless user’s UID:GID are not mapped into the container. This option is not allowed for containers created by the root user.
`ns:namespace`: run the <<container|pod>> in the given existing user namespace.


network_mode - Set the network mode for the container.
By default the task uses the network stack defined in the task group, see network Stanza. If the groups network behavior is also undefined, it will fallback to bridge in rootful mode or slirp4netns for rootless containers.

bridge: create a network stack on the default podman bridge.
none: no networking
host: use the Podman host network stack. Note: the host mode gives the container full access to local system services such as D-bus and is therefore considered insecure
slirp4netns: use slirp4netns to create a user network stack. This is the default for rootless containers. Podman currently does not support it for root containers issue.
container:id: reuse another podman containers network stack
task:name-of-other-task: join the network of another task in the same allocation.

Ex:
```hcl
config {
  network_mode = "bridge"
}
```

## Maintenance

To automate the cleanup process, you can create a scheduled task or a cron job that runs the above commands periodically. For example, you can set up a daily or weekly task to remove unused containers, images, and volumes using the prune commands.
Here's an example cron job that runs the cleanup commands every day at 2 AM:
```
0 2 * * * /usr/bin/podman container prune -f; /usr/bin/podman image prune -a -f; /usr/bin/podman volume prune -f; /usr/bin/podman system prune -a -f
```
Make sure to adjust the commands and schedule according to your specific requirements.
Additionally, you can consider the following best practices to minimize storage usage:

Regularly remove unnecessary containers, images, and volumes.
Use minimal base images whenever possible.
Utilize multi-stage builds to reduce the final image size.
Share layers between images by using a common base image.
Avoid storing data in containers; use volumes or bind mounts instead.

By following these steps and best practices, you can effectively manage the storage usage of your rootless Podman setup and prevent the accumulation of unused container data.

## Notes
- Use `podman top` to determine the UID of a user inside a container. Example:

```bash
hashi@host:~$ podman top -l user huser group hgroup
USER        HUSER       GROUP       HGROUP
opuser      100998      opuser      100998
```

The `HUSER` value is the UID of the running user, which can be used with the `userns = "keep-id:uid={uid},gid={gid}"` config to map the system rootless user to this UID.

- Use `podman cp` to copy files in/out of a container. Useful to ensure templates are being properly written. Example:
`podman cp [container id]:[filepath] [local file]`

- Use `podman inspect` to view environment variables in a running container. Example:
`podman inspect --format='{{json .Config.Env}}' [container id] | jq`

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
## Relocating container images

Moving the container images and file system to a Ceph cluster is a good idea to free up space on your root directory. Here's a step-by-step guide along with bash commands to help you with the process. Note that this example uses cephfs, which is not a good choice to store container images/filesystems. See ceph README.md for an example of setting up an rbd volume instead.

1. Stop the running containers and the Podman service:
```bash
podman stop $(podman ps -q)
systemctl stop podman
```

1. Create a new directory in your Ceph file system to store the container data. For example:
```bash
mkdir /mnt/cephfs/podman-data
```

1. Mount the Ceph file system directory to a local directory on your server. Update the `<mon-ip>` and `<secret-key>` placeholders with your Ceph cluster's monitor IP and secret key, respectively:
```bash
sudo mount -t ceph <mon-ip>:6789:/ /mnt/cephfs -o name=admin,secret=<secret-key>
```

1. Copy the existing container data to the Ceph file system directory:
```bash
sudo rsync -avP ~/.local/share/containers/storage /mnt/services/podman/[node]/storage
```

1. Remove the old container data directory:
```bash
rm -rf ~/.local/share/containers/storage
```

1. Create a symbolic link from the Ceph file system directory to the original location:
```bash
ln -s /mnt/services/podman/[node]/storage ~/.local/share/containers/
```

1. Start the Podman service:
```bash
systemctl start podman
```

1. Verify that the containers are running correctly:
```bash
podman ps
```

Concerns and issues to consider:

1. Performance: Accessing container data over the network from the Ceph cluster might have a slight performance impact compared to local storage. However, this should be minimal for most use cases.
2. Network dependency: Ensure that your network connection between the server and the Ceph cluster is stable and has sufficient bandwidth to handle the container data access.
3. Data consistency: Make sure that the Ceph cluster is properly configured for data replication and fault tolerance to protect against data loss.
4. Mounting on boot: To ensure that the Ceph file system is mounted on boot, you need to add an entry to the `/etc/fstab` file. Add the following line to `/etc/fstab`:
```
<mon-ip>:6789:/     /mnt/cephfs    ceph    name=admin,secret=<secret-key>,noauto,x-systemd.automount 0 0
```
Replace `<mon-ip>` and `<secret-key>` with your Ceph cluster's monitor IP and secret key, respectively.

By following these steps and considering the mentioned concerns, you should be able to successfully move your container images and file system to the Ceph cluster and ensure that everything works smoothly when the server boots.

## Overlayfs for rootless containers

Debian uses `vfs` by default for rootless podman, but `overlayfs` is supported and more performant. Use these steps to migrate from `vfs` to `overlayfs`:

- Drain Nomad agent
- As the `hashi` user:

```bash
systemctl stop --user podman.service podman.socket
rm -rf /run/user/2000/containers/*
rm ~/.local/share/containers/cache/*
sudo rm -rf /opt/homelab/data/home/.local/share/containers/storage/*
/usr/bin/podman container prune -f; /usr/bin/podman image prune -a -f; /usr/bin/podman volume prune -f; /usr/bin/podman system prune -a -f
podman system reset
```

- Create `/opt/homelab/data/home/.config/containers/storage.conf`:

```ini
[storage]
driver = "overlay"
```

- Restart podman and run some smoke tests 
```bash
systemctl start --user podman.service podman.socket
podman run --rm hello-world
podman info
```

- Mark the node as elligible