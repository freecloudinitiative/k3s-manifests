# FILES — Where Code Live

## Root

```
README.md                                     What this repo does and how to use it.
APPS.md                                       What each app does and its key config.
ARCHITECTURE.md                               How apps connect. Traffic, secrets, storage, sync order.
CHARTS.md                                     Chart-authoring contract: applications/<service>/, tests/, YAML-only rule.
FILES.md                                      This file.
Makefile                                      Local validation: yamllint, helm lint/template, kubeconform, helm unittest.
```

---

## infrastructure/

Platform-level tools. All deployed by ArgoCD.

```
infrastructure/README.md                      Notes on infrastructure apps.

infrastructure/namespaces/
  authentik.yaml                              Namespace: authentik
  backend.yaml                                Namespace: backend (api-gateway, compute-service, database-service, iam-service, storage-service, terminal-gateway)
  cert-manager.yaml                           Namespace: cert-manager
  cloudflared.yaml                            Namespace: cloudflared
  cnpg-system.yaml                            Namespace: cnpg-system (CloudNativePG operator)
  frontend.yaml                               Namespace: frontend
  garage.yaml                                 Namespace: garage
  kyverno.yaml                                Namespace: kyverno
  longhorn-system.yaml                        Namespace: longhorn-system
  metallb-system.yaml                         Namespace: metallb-system
  monitoring.yaml                             Namespace: monitoring
  openbao.yaml                                Namespace: openbao
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
  cluster-issuer-selfsigned.yaml              ClusterIssuer: selfsigned-cluster-issuer.
  cluster-issuer-ca.yaml                      ClusterIssuer: ca-cluster-issuer (private CA).
  cluster-issuer-letsencrypt.yaml             ClusterIssuer: letsencrypt-production.
  service.yaml                                ExposedService for cert-manager webhook.
  values.yaml                                 cert-manager Helm values.

infrastructure/longhorn/
  app.yaml                                    ArgoCD Application for Longhorn Helm chart.
  storageclasses.yaml                         StorageClasses: longhorn-platform (2 replicas) + longhorn-local (1 replica).
  values.yaml                                 Longhorn Helm values.

infrastructure/traefik/
  app.yaml                                    ArgoCD Application for Traefik Helm chart.
  values.yaml                                 Traefik config: DaemonSet, hostPort 80/443, control-plane nodeSelector.
  ingress-routes.yaml                         Ingress + IngressRoute for UI subdomains (Grafana, ArgoCD, Alloy, etc.).
  middleware-chain.yaml                       Middleware chain: security-headers → rate-limit.
  middleware-ratelimit.yaml                   Rate-limit middleware config.
  middleware-transform.yaml                   Header transformation middleware.

infrastructure/cloudnative-pg/
  app.yaml                                    ArgoCD Application for CloudNativePG operator chart 0.29.0.
  values.yaml                                 CNPG operator Helm values.

infrastructure/external-secrets/
  app.yaml                                    ArgoCD Application for External Secrets Operator.
  cluster-store.yaml                          ClusterSecretStore pointing to OpenBao (Kubernetes auth).
  service-account.yaml                        ServiceAccount for External Secrets to auth with OpenBao.
  rbac.yaml                                   RBAC for External Secrets service account.
  values.yaml                                 External Secrets Helm values.
  external-secret-authentik.yaml              Authentik + platform Postgres role credentials.
  external-secret-cloudflared.yaml            Cloudflare tunnel token.
  external-secret-gateway.yaml                api-gateway signing key + shared Valkey password/CA.
  external-secret-grafana.yaml                Grafana admin credentials.
  external-secret-storage.yaml                storage-service Postgres, Valkey, Garage, public key.
  external-secret-terminal.yaml               terminal-gateway signing + public key + Valkey.
  external-secret-valkey.yaml                 Valkey ACL password (namespace valkey).
  external-secret-iam.yaml                    iam-service DatabaseRole + chart-facing secrets.
  external-secret-compute.yaml                compute-service DatabaseRole + chart-facing secrets.
  external-secret-database.yaml               database-service DatabaseRole + chart-facing secrets.
  external-secret-registry.yaml               zot-registry-pull-credentials (backend).
  external-secret-registry-frontend.yaml      zot-registry-pull-credentials (frontend).
  external-secret-argocd.yaml                 ArgoCD OIDC credentials.

infrastructure/kyverno/
  app.yaml                                    ArgoCD Application for Kyverno Helm chart.
  values.yaml                                 Kyverno Helm values.

infrastructure/kyverno-policies/
  app.yaml                                    ArgoCD Application for Kyverno policy CRs.
  disallow-latest-tag.yaml                    Policy: images must have explicit tag (not latest). Audit.
  require-requests-limits.yaml                Policy: all containers must declare CPU/memory limits. Audit.
  require-run-as-non-root.yaml                Policy: all containers must run as non-root. Audit.
  restrict-image-registries.yaml              Policy: images must come from approved registries. Audit.
  restrict-compute-service-rbac-writes.yaml   Policy: compute-service RBAC/Namespace writes. Enforce.
  deny-pods-on-restoring-pvcs.yaml            Policy: deny Pods mounting a PVC locked by fci.io/restore-id unless label matches. Enforce.
  kyverno-tests/
    deny-pods-on-restoring-pvcs/              Local apiCall-based test fixtures for the policy above (run.sh, resources.yaml, values.yaml).

infrastructure/platform-postgresql/
  app.yaml                                    ArgoCD Application for CNPG Postgres cluster resources.
  cluster.yaml                                CNPG Cluster: 3 instances, TLS, scram-sha-256, local-path 20 Gi.
  certificate.yaml                            TLS certificate for Postgres (private CA).
  database.yaml                               CNPG Database CRs: platform + authentik.
  database-role.yaml                          CNPG DatabaseRole CRs — one role per service.
  networkpolicy.yaml                          NetworkPolicy: restrict Postgres ingress.

infrastructure/valkey/
  app.yaml                                    ArgoCD Application for Valkey Helm chart.
  certificate.yaml                            cert-manager Certificate → Secret valkey-server-tls.
  values.yaml                                 Valkey config: TLS, ACL, maxmemory 192mb, allkeys-lfu, no persistence.

infrastructure/garage/
  app.yaml                                    ArgoCD Application for Garage Helm chart.
  values.yaml                                 Garage config: 3 replicas, replicationFactor 3, longhorn-local PVCs.
  networkpolicy.yaml                          NetworkPolicy: restrict Garage to cluster-internal only.
  rpc-secret.yaml                             Garage RPC secret (value from OpenBao).

infrastructure/authentik/
  app.yaml                                    ArgoCD Application for Authentik Helm chart.
  values.yaml                                 Authentik config: 2 server + 2 worker, Postgres, Let's Encrypt TLS. blueprints.configMaps: [].
  blueprint.yaml                              Authentik Blueprint ConfigMap (not mounted; values leave configMaps empty).
  certificate.yaml                            TLS certificate for Authentik (Let's Encrypt).
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
  external-secrets.yaml                       ExternalSecret for Zot S3 credentials + htpasswd.
  middleware.yaml                             Traefik Middleware for registry authentication.
  networkpolicy.yaml                          NetworkPolicy for Zot registry.
  service-account.yaml                        ServiceAccount for Zot registry.

infrastructure/argocd/
  app-config.yaml                             ArgoCD Application to manage ArgoCD's own config (self-management).
  argocd-cm.yaml                              ArgoCD ConfigMap: resource health checks, exclusions.
  argocd-cmd-params-cm.yaml                   ArgoCD server command flags.
  argocd-rbac-cm.yaml                         ArgoCD RBAC ConfigMap.

infrastructure/openbao/
  app.yaml                                    ArgoCD Application for OpenBao Helm chart.
  certificate.yaml                            cert-manager Certificate for OpenBao.
  ingress.yaml                                Ingress for OpenBao.
  values.yaml                                 OpenBao Helm values.

infrastructure/kube-prometheus-stack/
  app.yaml                                    ArgoCD Application for kube-prometheus-stack Helm chart.
  values.yaml                                 Prometheus + Grafana: retention, PVC sizes, datasources (Prometheus, Loki, Tempo, Alloy).
  service-grafana.yaml                        ExposedService for Grafana (routed by Traefik).
  service-prometheus.yaml                     ExposedService for Prometheus.

infrastructure/loki/
  app.yaml                                    ArgoCD Application for Loki Helm chart.
  values.yaml                                 Loki config: single binary, filesystem storage, 10 Gi PVC.
  service.yaml                                ExposedService for Loki (used by OTel Collector and Grafana).

infrastructure/tempo/
  app.yaml                                    ArgoCD Application for Tempo Helm chart.
  values.yaml                                 Tempo config: single binary, OTLP receivers, 10 Gi PVC.
  service.yaml                                ExposedService for Tempo (used by OTel Collector and Grafana).

infrastructure/opentelemetry/
  app.yaml                                    ArgoCD Application for OTel Collector Helm chart.
  values.yaml                                 OTel config: OTLP receivers, batch processor, Tempo + Loki exporters.
  service.yaml                                LoadBalancer Service opentelemetry-collector-external (4317/4318/8888).

infrastructure/alloy/
  app.yaml                                    ArgoCD Application for Grafana Alloy Helm chart.
  values.yaml                                 Alloy config: log scraping, metric forwarding.
  service.yaml                                ExposedService for Alloy UI (routed by Traefik at /alloy).
```

---

## applications/

FCI product services. Each folder is an ArgoCD Application plus the Helm chart
it renders. Source repo is this repo; path is `applications/<name>`.

```
applications/README.md                        Notes on application apps.

applications/api-gateway/
  app.yaml                                    ArgoCD Application. Tag sha-0ac98efb497a.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  rules/api-gateway.yaml                      Prometheus alert rules (loaded via .Files.Get).
  templates/                                  9 Kubernetes templates + _helpers.tpl.

applications/compute-service/
  app.yaml                                    ArgoCD Application. Tag sha-xxxxxxxxxxxx. Automated sync off.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  templates/                                  9 Kubernetes templates + _helpers.tpl.

applications/database-service/
  app.yaml                                    ArgoCD Application. Tag sha-f247d60ac4de. Image repo ghcr.io.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  rules/database-service.yaml                 Prometheus alert rules (loaded via .Files.Get).
  templates/                                  11 Kubernetes templates + _helpers.tpl.

applications/iam-service/
  app.yaml                                    ArgoCD Application. Tag sha-xxxxxxxxxxxx. Automated sync off.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  templates/                                  7 Kubernetes templates + _helpers.tpl.

applications/storage-service/
  app.yaml                                    ArgoCD Application. Tag sha-2f2daba0c43e.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  templates/                                  10 Kubernetes templates + _helpers.tpl.

applications/terminal-gateway/
  app.yaml                                    ArgoCD Application. Tag sha-e3c09b7baefc.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  templates/                                  11 Kubernetes templates + _helpers.tpl.

applications/frontend/
  app.yaml                                    ArgoCD Application. Tag sha-7eefcc02593a. Destination namespace frontend.
  Chart.yaml                                  Chart descriptor.
  values.yaml                                 Default values.
  templates/                                  7 Kubernetes templates + _helpers.tpl (includes Ingress).
```

---

## scripts/

Repo-local checks. Not wired into CI; a workflow can call these directly.

```
check-image-digests.sh                        Reports app.yaml image.digest pins that lag the
                                               published image (see APPS.md). make check-digests.
```
