cluster:
  etcd:
    extraArgs:
      listen-metrics-urls: http://{{ .Node.Data.nodeAddress }}:2381
    advertisedSubnets:
      - 172.16.4.0/22
---
# Allow scheduling on control-plane nodes
apiVersion: v1alpha1
kind: KubeNodeConfig
taints:
  node-role.kubernetes.io/control-plane:
    $patch: delete
---
apiVersion: v1alpha1
kind: KubeAdmissionControlConfig
name: PodSecurity
$patch: delete
---
apiVersion: v1alpha1
kind: KubeAPIServerConfig
certExtraSANs:
  - "127.0.0.1"
extraArgs:
  # https://kubernetes.io/docs/tasks/extend-kubernetes/configure-aggregation-layer/
  enable-aggregator-routing: "true"
---
apiVersion: v1alpha1
kind: KubeControllerManagerConfig
---
apiVersion: v1alpha1
kind: KubeCoreDNSConfig
enabled: false
---
# Disable built-in CNI and kube-proxy to use Cilium
apiVersion: v1alpha1
kind: KubeFlannelCNIConfig
$patch: delete
---
apiVersion: v1alpha1
kind: KubeProxyConfig
enabled: false
---
apiVersion: v1alpha1
kind: KubeSchedulerConfig
config:
  profiles:
    - schedulerName: default-scheduler
      pluginConfig:
        - name: PodTopologySpread
          args:
            defaultingType: List
            defaultConstraints:
              - maxSkew: 1
                topologyKey: kubernetes.io/hostname
                whenUnsatisfiable: ScheduleAnyway
---
apiVersion: v1alpha1
kind: KubeTalosAPIAccessConfig
allowedRoles:
  - os:admin
allowedKubernetesNamespaces:
  - system-upgrade
