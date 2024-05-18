node_name = "joan-agent"
server = false
datacenter = "shamsway"
data_dir = "H:\hashi\consul\data\consul-agent"

connect {
  enabled = true
  ca_provider = "consul"
}

client_addr = "0.0.0.0"
bind_addr = "0.0.0.0"
advertise_addr = "192.168.252.5"

encrypt = "0qiTxBuYUykTs82uZz5keaNLMeoWI4CArQOEl1XwUfs="
encrypt_verify_incoming = true
encrypt_verify_outgoing = true

tls {
  defaults {
    ca_file = "H:\hashi\consul\tls\consul-agent-ca.pem"
    cert_file = "H:\hashi\consul\tls\shamsway-client-consul-0.pem"
    key_file = "H:\hashi\consul\tls\shamsway-client-consul-0-key.pem"
    verify_incoming = false
    verify_outgoing = true
    verify_server_hostname = true
  }
}

log_level = "INFO"
enable_syslog = true
enable_debug = true
leave_on_terminate = false
skip_leave_on_interrupt = true
rejoin_after_leave = true

# Use inventory hostnames for home, insert .ts before .shamsway.net for cloud-based servers

retry_join = [
"jerry.shamsway.net:8301", "bobby.shamsway.net:8301", "billy.shamsway.net:8301"]

ports {
  https = 8501
  grpc = 8502
  grpc_tls = 8503
}