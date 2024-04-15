# Policy-based route for Wireguard on VyOS

set interfaces wireguard wg1 address 10.2.0.2/32
set interfaces wireguard wg1 listen-port 51821
set interfaces wireguard wg1 mtu 1420
set interfaces wireguard wg1 peer /HvEnSU5JaswyBC/YFs74eGLXqLdzsaFeVT8SD1KYAc= allowed-ips 0.0.0.0/0
set interfaces wireguard wg1 peer /HvEnSU5JaswyBC/YFs74eGLXqLdzsaFeVT8SD1KYAc= description Proton
set interfaces wireguard wg1 peer /HvEnSU5JaswyBC/YFs74eGLXqLdzsaFeVT8SD1KYAc= endpoint '205.142.240.210:51820'
set interfaces wireguard wg1 private-key 6Mw9L0yYYyQ/927KqeQLTse12ZtUGPG7Q8sgV6peiHU=
set interfaces wireguard wg1 route-allowed-ips false

# Set MSS Clamping
set firewall options mss-clamp interface-type wg
set firewall options mss-clamp mss 1380

# Create a new routing table for the WireGuard traffic
set protocols static table 10 description 'table to force wg1:proton'
set protocols static table 10 interface-route 0.0.0.0/0 next-hop-interface wg1

# Create address group
set firewall group address-group WG-CLIENTS description 'Wireguard traffic'
set firewall group address-group WG-CLIENTS address 192.168.252.173

set firewall group network-group LOCAL description 'All other traffic'
set firewall group network-group LOCAL network 192.168.252.0/24

# Create firewall modify/routing policy
set firewall modify WG-TRAFFIC rule 10 description 'Wireguard traffic'
set firewall modify WG-TRAFFIC rule 10 source group address-group WG-CLIENTS
set firewall modify WG-TRAFFIC rule 10 modify table 10
set firewall modify WG-TRAFFIC rule 20 description 'Default routing, no VPN'
set firewall modify WG-TRAFFIC rule 20 accept

# Configure interface for policy routing
set interfaces switch switch0 firewall in modify WG-TRAFFIC
[delete interfaces switch switch0 firewall in modify WG-TRAFFIC]

# NAT configuration
set service nat rule 5100 outbound-interface 'wg1'
set service nat rule 5100 source group address-group WG-CLIENTS
set service nat rule 5100 type masquerade

# Update ZBF
set zone-policy zone WG-PROTON interface wg1
set zone-policy zone LAN from WG-PROTON firewall name inet-in
set zone-policy zone WG-PROTON from LAN firewall name allow-all
set zone-policy zone WG-PROTON default-action drop
