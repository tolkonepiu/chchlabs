---
apiVersion: v1alpha1
kind: LinkAliasConfig
name: ethSel0
selector:
  match: glob("{{ .Node.Data.macAddr }}", mac(link.hardware_addr))

---
apiVersion: v1alpha1
kind: BondConfig
name: bond0
links:
  - ethSel0
bondMode: active-backup
mtu: {{ .Node.Data.mtu }}

# Public network.
---
apiVersion: v1alpha1
kind: DHCPv4Config
name: bond0
routeMetric: 1024
ignoreHostname: true

# Private network.
---
apiVersion: v1alpha1
kind: VLANConfig
name: bond0.{{ .Node.Data.vlanTag }}
parent: bond0
vlanID: {{ .Node.Data.vlanTag }}
mtu: {{ .Node.Data.mtu }}
addresses:
  - address: "{{ .Node.Data.nodeAddress }}/22"
