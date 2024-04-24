# Nomad Network Block and Traefik Integration

When configuring a Nomad job to work with Traefik for automatic SSL/TLS termination, it's important to understand the `network` block in the Nomad job specification and how it interacts with Traefik. This document provides an overview of the `network` block, port configuration, and the best practices for integrating Nomad with Traefik.

## Nomad Network Block

The `network` block in a Nomad job specification is used to define the networking requirements for the task. It allows you to specify the network mode, port mappings, and other network-related settings. Here's an example of a `network` block:

```hcl
network {
  mode = "bridge"
  port "http" {
    static = 8080
    to     = 8080
  }
}
```

- `mode`: Specifies the network mode for the task. Common values are `"bridge"` (default) and `"host"`.
- `port`: Defines a port mapping for the task. You can specify multiple `port` blocks within the `network` block.

## Port Configuration

Within the `port` block, you can configure the port mapping for the task. The `static` and `to` parameters are used to specify the port numbers:

- `static`: Specifies the static port number on the host that will be mapped to the task's port. If not specified, Nomad will dynamically allocate a port.
- `to`: Specifies the port number inside the task that the `static` port should be mapped to. If not specified, it defaults to the same value as `static`.

For example, `static = 8080` and `to = 8080` means that port 8080 on the host will be mapped to port 8080 inside the task.

## Best Practices for Traefik Integration

When integrating Nomad with Traefik for automatic SSL/TLS termination, consider the following best practices:

1. **Service Registration**: Ensure that your Nomad job is properly registered as a service with Consul or another service discovery mechanism that Traefik can integrate with. This allows Traefik to automatically discover and route traffic to your Nomad services.

2. **Port Configuration**: Configure the `port` block in your Nomad job to expose the necessary ports for your service. For example, if your service listens on port 8080, set `static = 8080` and `to = 8080` in the `port` block.

3. **Traefik Configuration**: In your Traefik configuration file (e.g., `traefik.toml`), enable the necessary providers and entrypoints. For example, enable the Consul provider to discover services from Consul and configure the HTTP and HTTPS entrypoints.

4. **Let's Encrypt Configuration**: Configure Traefik to use Let's Encrypt for automatic SSL/TLS certificate generation. Specify the Let's Encrypt configuration in the Traefik configuration file, including the email address, challenge type (e.g., HTTP or DNS), and any other required settings.

## Traffic Flow

Here's the typical traffic flow for a non-HTTPS Nomad job using Traefik with automatic SSL/TLS:

1. A client sends an HTTP request to the Traefik entrypoint (e.g., port 80).
2. Traefik receives the request and checks its configuration to determine the appropriate service to route the request to.
3. Traefik discovers the Nomad service through Consul (or another configured provider) and obtains the service's IP address and port.
4. Traefik initiates an HTTPS connection to the client using the automatically generated SSL/TLS certificate from Let's Encrypt.
5. Traefik forwards the request to the Nomad service over HTTP (since the Nomad job is non-HTTPS) using the IP address and port obtained from Consul.
6. The Nomad service processes the request and sends the response back to Traefik.
7. Traefik receives the response from the Nomad service and forwards it back to the client over the HTTPS connection.

By following these best practices and understanding the traffic flow, you can effectively integrate Nomad with Traefik for automatic SSL/TLS termination, enabling secure communication between clients and your Nomad services.

# Dynamic Ports and Traefik Routing

When using dynamic ports in Nomad, Traefik can automatically discover and route traffic to the appropriate services based on the configured tags. This document explains how dynamic ports are handled and the typical Traefik tags used for routing and SSL/TLS configuration.

## Dynamic Ports in Nomad

Dynamic ports in Nomad allow you to let Nomad automatically allocate ports for your services. Instead of specifying a static port, you can use the `to` parameter in the `port` block to define the port number inside the task. Nomad will then dynamically allocate a host port and map it to the specified `to` port.

Here's an example of a `network` block with dynamic ports:

```hcl
network {
  mode = "bridge"
  port "http" {
    to = 8080
  }
}
```

In this example, Nomad will allocate a dynamic host port and map it to port 8080 inside the task.

## Traefik Tags for Routing and SSL/TLS

To configure Traefik to route traffic to your Nomad services and handle SSL/TLS termination, you need to specify the appropriate tags in your Nomad job specification. Here's an explanation of the typical Traefik tags used:

- `traefik.enable=true`: Enables Traefik for the service.
- `traefik.http.routers.<router-name>.rule`: Specifies the routing rule for the service. In your example, `Host(\`nginx.shamsway.net\`)` is used to route requests based on the hostname.
- `traefik.http.routers.<router-name>.entrypoints`: Specifies the entrypoints for the router. In your example, `web` and `websecure` are used, indicating that the service should be accessible via both HTTP and HTTPS.
- `traefik.http.routers.<router-name>.tls.certresolver`: Specifies the certificate resolver to use for SSL/TLS termination. In your example, `cloudflare` is used, which means Traefik will use the Cloudflare certificate resolver to obtain and manage SSL/TLS certificates.
- `traefik.http.routers.<router-name>.middlewares`: Specifies any middlewares to apply to the router. In your example, `redirect-web-to-websecure@internal` is used, which redirects HTTP traffic to HTTPS.

```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.nginx.rule=Host(`nginx.shamsway.net`)",
  "traefik.http.routers.nginx.entrypoints=web,websecure",
  "traefik.http.routers.nginx.tls.certresolver=cloudflare",
  "traefik.http.routers.nginx.middlewares=redirect-web-to-websecure@internal",
  "traefik.http.services.nginx.loadbalancer.server.port=${NOMAD_PORT_http}",
]
```

The additional tag `traefik.http.services.nginx.loadbalancer.server.port=${NOMAD_PORT_http}` is added to specify the port that Traefik should use to communicate with the Nomad service. `${NOMAD_PORT_http}` is a Nomad variable that represents the dynamically allocated host port for the `http` port defined in the `network` block.

With these tags, Traefik will:
1. Enable routing for the service.
2. Route requests based on the specified hostname (`nginx.shamsway.net`).
3. Handle incoming requests on both HTTP (`web`) and HTTPS (`websecure`) entrypoints.
4. Use the Cloudflare certificate resolver to obtain and manage SSL/TLS certificates.
5. Redirect HTTP traffic to HTTPS using the specified middleware.
6. Forward requests to the dynamically allocated host port of the Nomad service.

This configuration accomplishes the goal of providing a secure TLS connection fronted by Traefik for your Nomad service. Make sure to adjust the tags based on your specific requirements, such as the router name, hostname, entrypoints, certificate resolver, and middleware.

## Defining services

When deciding whether to define services at the group level or the task level in a Nomad job, consider the following factors:

1. Service Granularity:
   - If you have multiple tasks within a group that represent different components or microservices, it's often better to define services at the task level.
   - This allows you to have fine-grained control over the service registration, health checks, and routing for each individual task.
   - Defining services at the task level provides better isolation and flexibility, as each task can have its own set of service-specific configurations.

2. Shared Service:
   - If multiple tasks within a group share the same service and expose the same set of functionalities, you can consider defining the service at the group level.
   - This is particularly useful when you have multiple instances of the same task running, and they all contribute to the same service.
   - By defining the service at the group level, you can have a single service registration that encompasses all the tasks within the group.

3. Service Discovery and Load Balancing:
   - If you need to discover and load balance traffic across multiple tasks within a group, defining services at the task level is often preferred.
   - Each task can have its own service registration, allowing service discovery mechanisms like Consul to identify and route traffic to individual task instances.
   - This enables better distribution of traffic and allows for more granular health checks and routing configurations.

4. Simplicity and Maintainability:
   - Consider the complexity and maintainability of your job configuration when deciding between group-level and task-level services.
   - If your job has a simple structure and all tasks within a group serve the same purpose, defining services at the group level can simplify your configuration.
   - However, if your job has complex requirements and each task needs specific service configurations, defining services at the task level can provide better clarity and maintainability.

Rule of Thumb:
- If tasks within a group represent different microservices or components with distinct functionalities, define services at the task level.
- If tasks within a group are identical and contribute to the same service, consider defining the service at the group level.
- If you require fine-grained control over service registration, health checks, and routing for individual tasks, define services at the task level.
- If simplicity and maintainability are a priority and all tasks within a group serve the same purpose, defining services at the group level can be sufficient.

Ultimately, the decision to define services at the group level or the task level depends on your specific use case, architecture, and requirements. It's important to assess the needs of your application and choose the approach that provides the right balance of granularity, flexibility, and simplicity for your Nomad job configuration.

## Multiple tasks in a job

When there are multiple tasks in a Nomad job, Traefik uses a combination of the task name and the port labels to determine the connectivity to the specific task. Traefik relies on the service discovery mechanism (e.g., Consul) to obtain information about the available services and their associated tasks.

To properly configure Traefik to connect to the desired task in a multi-task job, you need to use the appropriate Traefik tags in the task's configuration. Here's how Traefik determines the connectivity:

1. Service Name:
   - By default, Traefik uses the job name as the service name.
   - You can override the service name using the `traefik.http.services.<service-name>` tag.
   - For example: `traefik.http.services.my-service.loadbalancer.server.port=${NOMAD_PORT_http}`

2. Task Name:
   - Traefik uses the task name to differentiate between multiple tasks within a job.
   - The task name is automatically appended to the service name to create a unique identifier.
   - For example, if you have a job named `my-job` with tasks `task1` and `task2`, Traefik will create services named `my-job-task1` and `my-job-task2`.

3. Port Labels:
   - Traefik uses the port labels defined in the task's `network` block to determine the port to connect to.
   - You can specify the port using the `${NOMAD_PORT_<label>}` syntax in the Traefik tags.
   - For example: `traefik.http.services.<service-name>.loadbalancer.server.port=${NOMAD_PORT_http}`

Here's an example of a Nomad job with multiple tasks and their corresponding Traefik tags:

```hcl
job "my-job" {
  datacenters = ["dc1"]

  group "my-group" {
    task "task1" {
      driver = "docker"
      config {
        image = "my-image1"
      }
      
      network {
        port "http" {
          to = 8080
        }
      }
      
      service {
        name = "task1"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.task1.rule=Host(`task1.example.com`)",
          "traefik.http.services.task1.loadbalancer.server.port=${NOMAD_PORT_http}",
        ]
      }
    }
    
    task "task2" {
      driver = "docker"
      config {
        image = "my-image2"
      }
      
      network {
        port "http" {
          to = 9090
        }
      }
      
      service {
        name = "task2"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.task2.rule=Host(`task2.example.com`)",
          "traefik.http.services.task2.loadbalancer.server.port=${NOMAD_PORT_http}",
        ]
      }
    }
  }
}
```

In this example, we have two tasks: `task1` and `task2`. Each task has its own set of Traefik tags:
- `task1` is accessible via `task1.example.com` and connects to the port labeled `http` (8080) within the task.
- `task2` is accessible via `task2.example.com` and connects to the port labeled `http` (9090) within the task.

Traefik uses the combination of the service name (derived from the task name) and the port labels to determine the connectivity to each specific task.

By following this approach and providing the appropriate Traefik tags for each task, Traefik will be able to accurately route requests to the desired task within a multi-task Nomad job.

# Consul Connect

## Prompt

Assume this scenario in my home lab. I need your help figuring out how to do some advanced networking use cases with containers. 

- nomad servers running across three hosts
- 2 nomad agents per server, 1 running as root, 1 running rootless
- podman used for container runtime
- consul servers running across three hosts
- 2 consul agents per server, 1 running as root (serving nomad root agent), 1 running rootless (serving nomad rootless agent)
- traefik providing reverse proxy, let's encrypt TLS certificates

I want to run a container named "gluetun" that provides wireguard VPN connectivity. this needs to run as root to be able to build a wireguard tunnel. I want to run a second container, threadfin. this container should:
- expose a web interface I can access
- run in a separate job in a rootless manner
- otherwise, route or proxy all traffic through the gluetun container

## Links

- (watch) https://www.youtube.com/watch?v=wTA5HxB_uuk - Understanding Nomad Networking Patterns
- https://github.com/hashicorp/nomad-connect-examples/tree/main
- https://www.hashicorp.com/blog/consul-connect-native-tasks-in-hashicorp-nomad-0-12
- https://www.mattmoriarity.com/2021-02-21-scraping-prometheus-metrics-with-nomad-and-consul-connect/
- https://andydote.co.uk/2020/05/04/service-mesh-consul-connect/
- Consul Connect with Traefik: 
  - https://storiesfromtheherd.com/traefik-in-nomad-using-consul-and-tls-5be0007794ee (super long)
  - https://gist.github.com/apollo13/857ae4c5e18de619815c2628212449e1
- Docs
  - https://developer.hashicorp.com/nomad/docs/job-specification/sidecar_service
  - https://developer.hashicorp.com/nomad/docs/job-specification/sidecar_task



### Consul Docs & Background info

Tutorials: https://developer.hashicorp.com/tutorials/library?query=connect&product=consul

- https://developer.hashicorp.com/consul/tutorials/get-started-vms/virtual-machine-gs-service-discovery
- https://developer.hashicorp.com/consul/tutorials/get-started-vms/virtual-machine-gs-service-mesh
- https://developer.hashicorp.com/consul/docs/connect/observability/ui-visualization
- https://developer.hashicorp.com/consul/tutorials/get-started-vms/virtual-machine-gs-service-mesh-access
- https://developer.hashicorp.com/consul/tutorials/get-started-vms/virtual-machine-gs-monitoring
- https://developer.hashicorp.com/consul/tutorials/archive/service-mesh-gateways
- https://developer.hashicorp.com/consul/tutorials/secure-services/secure-services-intentions

- https://developer.hashicorp.com/consul/docs/connect/proxies
- https://developer.hashicorp.com/consul/docs/connect/proxies/proxy-config-reference
- https://developer.hashicorp.com/consul/docs/connect/gateways

- https://medium.com/navin-nair/practical-hashicorp-nomad-and-consul-a-little-more-than-hello-world-part-1-991d2a54fd64
- https://medium.com/@arunlogo.kct/practical-hashicorp-nomad-and-consul-ci-cd-pipeline-to-deploy-the-api-and-webapp-part-2-c07117bbb27d
- https://medium.com/@jawaharsbs/practical-hashicorp-nomad-and-consul-monitoring-autoscaling-using-prometheus-grafana-part-3-8e032fbf1357
- https://srivastavaankita080.medium.com/practical-hashicorp-nomad-and-consul-part-4-consul-kv-store-ef837e0e4ffc
- 