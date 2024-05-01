# Consul Documentation for settings: 
- https://developer.hashicorp.com/consul/docs/connect/config-entries/proxy-defaults
- Proxy config options: https://developer.hashicorp.com/consul/docs/connect/proxies/envoy#proxy-config-options (values inside the Config {} block)
- https://developer.hashicorp.com/consul/docs/connect/config-entries/mesh
- https://developer.hashicorp.com/consul/docs/connect/proxies/proxy-config-reference
- 
# Nomad default Envoy config

```json
sidecar_task {
  name = "connect-proxy-<service>"
  #      "connect-gateway-<service>" when used as a gateway

  lifecycle { # absent when used as a gateway
    hook    = "prestart"
    sidecar = true
  }

  driver = "docker"

  config {
    image = "${meta.connect.sidecar_image}"
    #       "${meta.connect.gateway_image}" when used as a gateway

    args = [
      "-c",
      "${NOMAD_SECRETS_DIR}/envoy_bootstrap.json",
      "-l",
      "${meta.connect.log_level}",
      "--concurrency",
      "${meta.connect.proxy_concurrency}",
      "--disable-hot-restart"
    ]
  }

  logs {
    max_files     = 2
    max_file_size = 2 # MB
  }

  resources {
    cpu    = 250 # MHz
    memory = 128 # MB
  }

  shutdown_delay = "5s"
}
```

# Configured/example secrets/bootstrap_envoy.json

```json
{
  "admin": {
    "access_log": [
      {
        "name": "Consul Listener Filter Log",
        "typedConfig": {
          "@type": "type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog",
          "logFormat": {
            "jsonFormat": {
              "authority": "%REQ(:AUTHORITY)%",
              "bytes_received": "%BYTES_RECEIVED%",
              "bytes_sent": "%BYTES_SENT%",
              "connection_termination_details": "%CONNECTION_TERMINATION_DETAILS%",
              "downstream_local_address": "%DOWNSTREAM_LOCAL_ADDRESS%",
              "downstream_remote_address": "%DOWNSTREAM_REMOTE_ADDRESS%",
              "duration": "%DURATION%",
              "method": "%REQ(:METHOD)%",
              "path": "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%",
              "protocol": "%PROTOCOL%",
              "request_id": "%REQ(X-REQUEST-ID)%",
              "requested_server_name": "%REQUESTED_SERVER_NAME%",
              "response_code": "%RESPONSE_CODE%",
              "response_code_details": "%RESPONSE_CODE_DETAILS%",
              "response_flags": "%RESPONSE_FLAGS%",
              "route_name": "%ROUTE_NAME%",
              "start_time": "%START_TIME%",
              "upstream_cluster": "%UPSTREAM_CLUSTER%",
              "upstream_host": "%UPSTREAM_HOST%",
              "upstream_local_address": "%UPSTREAM_LOCAL_ADDRESS%",
              "upstream_service_time": "%RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)%",
              "upstream_transport_failure_reason": "%UPSTREAM_TRANSPORT_FAILURE_REASON%",
              "user_agent": "%REQ(USER-AGENT)%",
              "x_forwarded_for": "%REQ(X-FORWARDED-FOR)%"
            }
          }
        }
      }
    ],
    "address": {
      "socket_address": {
        "address": "127.0.0.2",
        "port_value": 19001
      }
    }
  },
  "node": {
    "cluster": "xteve",
    "id": "_nomad-task-09bbc355-d13d-40ac-3cda-139dc87ade32-group-m3u-tools-xteve-34400-sidecar-proxy",
    "metadata": {
      "namespace": "default",
      "partition": "default"
    }
  },
  "layered_runtime": {
    "layers": [
      {
        "name": "base",
        "static_layer": {
          "re2.max_program_size.error_level": 1048576
        }
      }
    ]
  },
  "static_resources": {
    "clusters": [
      {
        "name": "local_agent",
        "ignore_health_on_host_removal": false,
        "connect_timeout": "1s",
        "type": "STATIC",
        "transport_socket": {
          "name": "tls",
          "typed_config": {
            "@type": "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext",
            "common_tls_context": {
              "validation_context": {
                "trusted_ca": {
                  "inline_string": "-----BEGIN CERTIFICATE-----\nMIIC7TCCApOgAwIBAgIQTGkp6oD4imXGz1/Pq3o9SDAKBggqhkjOPQQDAjCBuTEL\nMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRYwFAYDVQQHEw1TYW4gRnJhbmNpc2Nv\nMRowGAYDVQQJExExMDEgU2Vjb25kIFN0cmVldDEOMAwGA1UEERMFOTQxMDUxFzAV\nBgNVBAoTDkhhc2hpQ29ycCBJbmMuMUAwPgYDVQQDEzdDb25zdWwgQWdlbnQgQ0Eg\nMTAxNTY3MzY5MDA3ODk4MDg5NzIyNDQ1NTc1OTk1NDkzMzM0MzQ0MB4XDTI0MDQy\nOTIzMzg0MVoXDTI5MDQyODIzMzg0MVowgbkxCzAJBgNVBAYTAlVTMQswCQYDVQQI\nEwJDQTEWMBQGA1UEBxMNU2FuIEZyYW5jaXNjbzEaMBgGA1UECRMRMTAxIFNlY29u\nZCBTdHJlZXQxDjAMBgNVBBETBTk0MTA1MRcwFQYDVQQKEw5IYXNoaUNvcnAgSW5j\nLjFAMD4GA1UEAxM3Q29uc3VsIEFnZW50IENBIDEwMTU2NzM2OTAwNzg5ODA4OTcy\nMjQ0NTU3NTk5NTQ5MzMzNDM0NDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABBcy\nkG7YHnOj6DISQLD2S0uZiq2Fp0nG0BypOkRKsJcOw6NmyGkdgqrbRDaknC4IWdOY\n//4Fxvim6mq7odMAgPCjezB5MA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTAD\nAQH/MCkGA1UdDgQiBCCErgv/wO1O/I6vOrqsXNL1SIGLVgBL+AI8//raUfuPFDAr\nBgNVHSMEJDAigCCErgv/wO1O/I6vOrqsXNL1SIGLVgBL+AI8//raUfuPFDAKBggq\nhkjOPQQDAgNIADBFAiB1Rq3W9drlxA81VfluFqJbaN2zVaWGiplMa/QZ+8vcPgIh\nALWsYbpxKO5g/qLIljoE6JH4f5aHUpSfDoUbqeHlkm3x\n-----END CERTIFICATE-----\n"
                }
              }
            }
          }
        },
        "typed_extension_protocol_options": {
          "envoy.extensions.upstreams.http.v3.HttpProtocolOptions": {
            "@type": "type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions",
            "explicit_http_config": {
              "http2_protocol_options": {}
            }
          }
        },
        "loadAssignment": {
          "clusterName": "local_agent",
          "endpoints": [
            {
              "lbEndpoints": [
                {
                  "endpoint": {
                    "address": {
                      "pipe": {
                        "path": "alloc/tmp/consul_grpc.sock"
                      }
                    }
                  }
                }
              ]
            }
          ]
        }
      },
      {
        "name": "self_admin",
        "ignore_health_on_host_removal": false,
        "connect_timeout": "5s",
        "type": "STATIC",
        "typed_extension_protocol_options": {
          "envoy.extensions.upstreams.http.v3.HttpProtocolOptions": {
            "@type": "type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions",
            "explicit_http_config": {
              "http_protocol_options": {}
            }
          }
        },
        "loadAssignment": {
          "clusterName": "self_admin",
          "endpoints": [
            {
              "lbEndpoints": [
                {
                  "endpoint": {
                    "address": {
                      "socket_address": {
                        "address": "127.0.0.2",
                        "port_value": 19001
                      }
                    }
                  }
                }
              ]
            }
          ]
        }
      }
    ],
    "listeners": [
      {
        "name": "envoy_prometheus_metrics_listener",
        "address": {
          "socket_address": {
            "address": "0.0.0.0",
            "port_value": 9102
          }
        },
        "filter_chains": [
          {
            "filters": [
              {
                "name": "envoy.filters.network.http_connection_manager",
                "typedConfig": {
                  "@type": "type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager",
                  "stat_prefix": "envoy_prometheus_metrics",
                  "codec_type": "HTTP1",
                  "route_config": {
                    "name": "self_admin_route",
                    "virtual_hosts": [
                      {
                        "name": "self_admin",
                        "domains": [
                          "*"
                        ],
                        "routes": [
                          {
                            "match": {
                              "path": "/metrics"
                            },
                            "route": {
                              "cluster": "self_admin",
                              "prefix_rewrite": "/stats/prometheus"
                            }
                          },
                          {
                            "match": {
                              "prefix": "/"
                            },
                            "direct_response": {
                              "status": 404
                            }
                          }
                        ]
                      }
                    ]
                  },
                  "http_filters": [
                    {
                      "name": "envoy.filters.http.router",
                      "typedConfig": {
                        "@type": "type.googleapis.com/envoy.extensions.filters.http.router.v3.Router"
                      }
                    }
                  ]
                }
              }
            ]
          }
        ]
      }
    ]
  },
  "stats_config": {
    "stats_tags": [
      {
        "tag_name": "nomad.alloc_id",
        "fixed_value": "09bbc355-d13d-40ac-3cda-139dc87ade32"
      },
      {
        "tag_name": "nomad.group",
        "fixed_value": "m3u-tools"
      },
      {
        "tag_name": "nomad.job",
        "fixed_value": "m3u-tools"
      },
      {
        "tag_name": "nomad.namespace",
        "fixed_value": "default"
      },
      {
        "regex": "^cluster\\.(?:passthrough~)?((?:([^.]+)~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.destination.custom_hash"
      },
      {
        "regex": "^cluster\\.(?:passthrough~)?((?:[^.]+~)?(?:([^.]+)\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.destination.service_subset"
      },
      {
        "regex": "^cluster\\.(?:passthrough~)?((?:[^.]+~)?(?:[^.]+\\.)?([^.]+)\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.destination.service"
      },
      {
        "regex": "^cluster\\.(?:passthrough~)?((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.([^.]+)\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.destination.namespace"
      },
      {
        "regex": "^cluster\\.(?:passthrough~)?((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:([^.]+)\\.)?[^.]+\\.internal[^.]*\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.destination.partition"
      },
      {
        "regex": "^cluster\\.(?:passthrough~)?((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?([^.]+)\\.internal[^.]*\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.destination.datacenter"
      },
      {
        "regex": "^cluster\\.([^.]+\\.(?:[^.]+\\.)?([^.]+)\\.external\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.destination.peer"
      },
      {
        "regex": "^cluster\\.(?:passthrough~)?((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.([^.]+)\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.destination.routing_type"
      },
      {
        "regex": "^cluster\\.(?:passthrough~)?((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.([^.]+)\\.consul\\.)",
        "tag_name": "consul.destination.trust_domain"
      },
      {
        "regex": "^cluster\\.(?:passthrough~)?(((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+)\\.[^.]+\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.destination.target"
      },
      {
        "regex": "^cluster\\.(?:passthrough~)?(((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.[^.]+)\\.consul\\.)",
        "tag_name": "consul.destination.full_target"
      },
      {
        "regex": "^(?:tcp|http)\\.upstream(?:_peered)?\\.(([^.]+)(?:\\.[^.]+)?(?:\\.[^.]+)?\\.[^.]+\\.)",
        "tag_name": "consul.upstream.service"
      },
      {
        "regex": "^(?:tcp|http)\\.upstream\\.([^.]+(?:\\.[^.]+)?(?:\\.[^.]+)?\\.([^.]+)\\.)",
        "tag_name": "consul.upstream.datacenter"
      },
      {
        "regex": "^(?:tcp|http)\\.upstream_peered\\.([^.]+(?:\\.[^.]+)?\\.([^.]+)\\.)",
        "tag_name": "consul.upstream.peer"
      },
      {
        "regex": "^(?:tcp|http)\\.upstream(?:_peered)?\\.([^.]+(?:\\.([^.]+))?(?:\\.[^.]+)?\\.[^.]+\\.)",
        "tag_name": "consul.upstream.namespace"
      },
      {
        "regex": "^(?:tcp|http)\\.upstream\\.([^.]+(?:\\.[^.]+)?(?:\\.([^.]+))?\\.[^.]+\\.)",
        "tag_name": "consul.upstream.partition"
      },
      {
        "regex": "^cluster\\.((?:([^.]+)~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.custom_hash"
      },
      {
        "regex": "^cluster\\.((?:[^.]+~)?(?:([^.]+)\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.service_subset"
      },
      {
        "regex": "^cluster\\.((?:[^.]+~)?(?:[^.]+\\.)?([^.]+)\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.service"
      },
      {
        "regex": "^cluster\\.((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.([^.]+)\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.namespace"
      },
      {
        "regex": "^cluster\\.((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?([^.]+)\\.internal[^.]*\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.datacenter"
      },
      {
        "regex": "^cluster\\.((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.([^.]+)\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.routing_type"
      },
      {
        "regex": "^cluster\\.((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.([^.]+)\\.consul\\.)",
        "tag_name": "consul.trust_domain"
      },
      {
        "regex": "^cluster\\.(((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+)\\.[^.]+\\.[^.]+\\.consul\\.)",
        "tag_name": "consul.target"
      },
      {
        "regex": "^cluster\\.(((?:[^.]+~)?(?:[^.]+\\.)?[^.]+\\.[^.]+\\.(?:[^.]+\\.)?[^.]+\\.[^.]+\\.[^.]+)\\.consul\\.)",
        "tag_name": "consul.full_target"
      },
      {
        "tag_name": "local_cluster",
        "fixed_value": "xteve"
      },
      {
        "tag_name": "consul.source.service",
        "fixed_value": "xteve"
      },
      {
        "tag_name": "consul.source.namespace",
        "fixed_value": "default"
      },
      {
        "tag_name": "consul.source.partition",
        "fixed_value": "default"
      },
      {
        "tag_name": "consul.source.datacenter",
        "fixed_value": "shamsway"
      }
    ],
    "use_all_default_tags": true
  },
  "dynamic_resources": {
    "lds_config": {
      "ads": {},
      "initial_fetch_timeout": "0s",
      "resource_api_version": "V3"
    },
    "cds_config": {
      "ads": {},
      "initial_fetch_timeout": "0s",
      "resource_api_version": "V3"
    },
    "ads_config": {
      "api_type": "DELTA_GRPC",
      "transport_api_version": "V3",
      "grpc_services": {
        "initial_metadata": [
          {
            "key": "x-consul-token",
            "value": ""
          }
        ],
        "envoy_grpc": {
          "cluster_name": "local_agent"
        }
      }
    }
  }
}
```