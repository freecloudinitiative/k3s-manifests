# FILES — Where Code Live

## Root

```
README.md                                     What this repo does and how to use it.
APPS.md                                       What each app does and its key config.
ARCHITECTURE.md                               How apps connect. Traffic, secrets, storage, sync order.
CHARTS.md                                     Chart-authoring contract: charts/<service>/, tests/, YAML-only rule.
FILES.md                                      This file.
Makefile                                      Local validation: yamllint, helm lint/template, kubeconform, helm unittest.
.gitignore                                    Git ignore rules.
.vscode/settings.json                         YAML schema associations for editor autocomplete.

```

---

## infrastructure/

Platform-level tools. All deployed by ArgoCD.

```
infrastructure/README.md                      Notes on infrastructure apps.

infrastructure/namespaces/
  authentik.yaml                              Namespace: authentik
  cert-manager.yaml                           Namespace: cert-manager
  cloudflared.yaml                            Namespace: cloudflared
  cnpg-system.yaml                            Namespace: cnpg-system (CloudNativePG operator)
  frontend.yaml                               Namespace: frontend
  garage.yaml                                 Namespace: garage
  kyverno.yaml                                Namespace: kyverno
  longhorn-system.yaml                        Namespace: longhorn-system
  metallb-system.yaml                         Namespace: metallb-system
  monitoring.yaml                             Namespace: monitoring
  platform-database.yaml                      Namespace: platform-database (Postgres cluster)
  traefik.yaml                                Namespace: traefik
  valkey.yaml                                 Namespace: valkey
  zot-registry.yaml                           Namespace: zot-registry

infrastructure/metallb/
  app.yaml                                    ArgoCD Application for MetalLB Helm chart.
  app-config.yaml                             ArgoCD Application for MetalLB config resources.
  config.yaml                                 IPAddressPool (192.168.1.100-120) + L2Advertisement.
  values.yaml                                 MetalLB Helm values.

infrastructure/cert-manager/
  app.yaml                                    ArgoCD Application for cert-manager Helm chart.
  app-config.yaml                             ArgoCD Application for cert-manager issuers/certs.
  certificate-selfsigned-ca.yaml              Self-signed root CA certificate (bootstrap).
  cluster-issuer-selfsigned.yaml              ClusterIssuer: self-signed (used only to create root CA).
  cluster-issuer-ca.yaml                      ClusterIssuer: private CA (signs internal certs).
  cluster-issuer-letsencrypt.yaml             ClusterIssuer: Let's Encrypt production (public certs).
  service.yaml                                ExposedService for cert-manager webhook.
  values.yaml                                 cert-manager Helm values.

infrastructure/longhorn/
  app.yaml                                    ArgoCD Application for Longhorn Helm chart.
  storageclasses.yaml                         Two StorageClasses: longhorn-platform (2 replicas) + longhorn-local (1 replica).
  values.yaml                                 Longhorn Helm values.

infrastructure/traefik/
  app.yaml                                    ArgoCD Application for Traefik Helm chart.
  values.yaml                                 Traefik config: DaemonSet, hostPort 80/443, master-only nodeSelector.
  ingress-routes.yaml                         Ingress + IngressRoute for all internal paths (Grafana, ArgoCD, Alloy, etc.).
  middleware-chain.yaml                       Middleware chain: security-headers → rate-limit.
  middleware-ratelimit.yaml                   Rate-limit middleware config.
  middleware-transform.yaml                   Header transformation middleware.

infrastructure/external-secrets/
  app.yaml                                    ArgoCD Application for External Secrets Operator.
  cluster-store.yaml                          ClusterSecretStore pointing to OpenBao (Kubernetes auth).
  service-account.yaml                        ServiceAccount for External Secrets to auth with OpenBao.
  rbac.yaml                                   RBAC for External Secrets service account.
  values.yaml                                 External Secrets Helm values.
  external-secret-authentik.yaml              Syncs Authentik credentials from OpenBao.
  external-secret-cloudflared.yaml            Syncs Cloudflare tunnel token from OpenBao.
  external-secret-gateway.yaml                Syncs API gateway signing keys from OpenBao.
  external-secret-grafana.yaml                Syncs Grafana admin credentials from OpenBao.
  external-secret-storage.yaml                Syncs storage service S3 credentials from OpenBao.
  external-secret-terminal.yaml               Syncs terminal gateway signing keys from OpenBao.
  external-secret-valkey.yaml                 Syncs Valkey ACL password from OpenBao.

infrastructure/kyverno/
  app.yaml                                    ArgoCD Application for Kyverno Helm chart.
  values.yaml                                 Kyverno Helm values.

infrastructure/kyverno-policies/
  app.yaml                                    ArgoCD Application for Kyverno policy CRs.
  disallow-latest-tag.yaml                    Policy: images must have explicit tag (not latest).
  require-requests-limits.yaml                Policy: all containers must declare CPU/memory limits.
  require-run-as-non-root.yaml                Policy: all containers must run as non-root.
  restrict-image-registries.yaml              Policy: images must come from approved registries.

infrastructure/platform-postgresql/
  app.yaml                                    ArgoCD Application for CNPG Postgres cluster resources.
  cluster.yaml                                CNPG Cluster: 3 instances, TLS, scram-sha-256, 20 Gi.
  certificate.yaml                            TLS certificate for Postgres (private CA).
  database.yaml                               CNPG Database CRs for each service's database.
  database-role.yaml                          CNPG DatabaseRole CRs — one role per service.
  networkpolicy.yaml                          NetworkPolicy: restrict Postgres ingress to backend only.

infrastructure/valkey/
  app.yaml                                    ArgoCD Application for Valkey Helm chart.
  certificate.yaml                            TLS certificate for Valkey (private CA).
  values.yaml                                 Valkey config: TLS, ACL, maxmemory 192mb, allkeys-lfu, no persistence.

infrastructure/garage/
  app.yaml                                    ArgoCD Application for Garage Helm chart.
  values.yaml                                 Garage config: 3 replicas, replicationFactor 3, longhorn-local PVCs.
  networkpolicy.yaml                          NetworkPolicy: restrict Garage to cluster-internal only.
  rpc-secret.yaml                             Placeholder/reference for Garage RPC secret (value from OpenBao).

infrastructure/authentik/
  app.yaml                                    ArgoCD Application for Authentik Helm chart.
  values.yaml                                 Authentik config: 2 server + 2 worker, Postgres, Let's Encrypt TLS.
  blueprint.yaml                              Authentik Blueprint CR for OIDC client setup.
  certificate.yaml                            TLS certificate for Authentik (Let's Encrypt via cert-manager annotation).
  networkpolicy.yaml                          NetworkPolicy for Authentik namespaced traffic.
  service-account.yaml                        ServiceAccount for Authentik runtime.

infrastructure/cloudflared/
  app.yaml                                    ArgoCD Application for cloudflared inline Helm chart.
  Chart.yaml                                  Inline Helm chart descriptor.
  values.yaml                                 cloudflared config: 2 replicas, tunnel token from Secret.
  templates/
    deployment.yaml                           cloudflared Deployment template.

infrastructure/zot-registry/
  app.yaml                                    ArgoCD Application for Zot Registry Helm chart.
  values.yaml                                 Zot config: Garage S3 backend, Let's Encrypt TLS, Prometheus metrics.
  external-secrets.yaml                       ExternalSecret for Zot S3 credentials.
  middleware.yaml                             Traefik Middleware for registry authentication.
  networkpolicy.yaml                          NetworkPolicy for Zot registry.
  service-account.yaml                        ServiceAccount for Zot registry.

infrastructure/argocd/
  app-config.yaml                             ArgoCD Application to manage ArgoCD's own config (self-management).
  argocd-cm.yaml                              ArgoCD ConfigMap: resource health checks, exclusions.
  argocd-cmd-params-cm.yaml                   ArgoCD server command flags.

infrastructure/kube-prometheus-stack/
  app.yaml                                    ArgoCD Application for kube-prometheus-stack Helm chart.
  values.yaml                                 Prometheus + Grafana config: retention, PVC sizes, datasources.
  service-grafana.yaml                        ExposedService for Grafana (routed by Traefik).
  service-prometheus.yaml                     ExposedService for Prometheus.

infrastructure/loki/
  app.yaml                                    ArgoCD Application for Loki Helm chart.
  values.yaml                                 Loki config: single binary, filesystem storage, 10 Gi PVC.
  service.yaml                                ExposedService for Loki (used by OTel Collector and Grafana).

infrastructure/tempo/
  app.yaml                                    ArgoCD Application for Tempo Helm chart.
  values.yaml                                 Tempo config: single binary, OTLP gRPC receiver.
  service.yaml                                ExposedService for Tempo (used by OTel Collector and Grafana).

infrastructure/opentelemetry/
  app.yaml                                    ArgoCD Application for OTel Collector Helm chart.
  values.yaml                                 OTel config: OTLP receivers, batch processor, Tempo + Loki exporters.
  service.yaml                                ExposedService for OTel Collector (4317 gRPC, 4318 HTTP).

infrastructure/alloy/
  app.yaml                                    ArgoCD Application for Grafana Alloy Helm chart.
  values.yaml                                 Alloy config: log scraping, metric forwarding.
  service.yaml                                ExposedService for Alloy UI (routed by Traefik at /alloy).
```

---

## applications/

FCI product services. Each is an ArgoCD Application pointing to the service's own repo.

```
applications/README.md                        Notes on application apps.

applications/api-gateway/
  app.yaml                                    ArgoCD Application for api-gateway Helm chart.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  rules/api-gateway.yaml                      Prometheus alert rules (loaded via .Files.Get).
  templates/                                  10 Kubernetes templates.

applications/compute-service/
  app.yaml                                    ArgoCD Application: compute-service repo → deploy/ → backend namespace.

applications/database-service/
  app.yaml                                    ArgoCD Application for database-service Helm chart.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  rules/database-service.yaml                 Prometheus alert rules (loaded via .Files.Get).
  templates/                                  11 Kubernetes templates.

applications/iam-service/
  app.yaml                                    ArgoCD Application: iam-service repo → deploy/ → backend namespace.

applications/storage-service/
  app.yaml                                    ArgoCD Application for storage-service Helm chart.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  templates/                                  11 Kubernetes templates.

applications/terminal-gateway/
  app.yaml                                    ArgoCD Application for terminal-gateway Helm chart.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  templates/                                  12 Kubernetes templates.

applications/frontend/
  app.yaml                                    ArgoCD Application for frontend Helm chart.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  templates/                                  8 Kubernetes templates.
```
