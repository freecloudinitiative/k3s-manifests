{{/*
Chart name, truncated to fit Kubernetes name limits when combined with
suffixes like -serviceaccount.
*/}}
{{- define "compute-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "compute-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "compute-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "compute-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "compute-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: compute-service
fci.io/tier: backend
{{- end }}

{{- define "compute-service.labels" -}}
helm.sh/chart: {{ include "compute-service.chart" . }}
{{ include "compute-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
compute-service.serviceAccountName — deliberately ignores
.Values.serviceAccount.name. The Kyverno policy in
infrastructure/kyverno-policies/restrict-compute-service-rbac-writes.yaml
hardcodes its match.subjects to ServiceAccount "compute-service" in
namespace "backend" — it is a plain YAML resource outside this chart and
cannot read Helm values, so it cannot follow an override here. Letting the
name diverge would silently stop that policy from matching this chart's
real identity, disabling the RBAC-write restriction entirely rather than
loudly failing. The name is therefore always the chart's canonical
fullname; serviceAccount.create still controls whether this chart creates
the object (see serviceaccount.yaml).
*/}}
{{- define "compute-service.serviceAccountName" -}}
{{- include "compute-service.fullname" . }}
{{- end }}

{{/*
compute-service.image — authoritative image reference.

Precedence:
  1. digest set  →  {repository}@{digest}      (immutable; wins over tag)
  2. tag   set   →  {repository}:{tag}
  3. neither     →  hard error; never falls back to .Chart.AppVersion

CI produces tags of the form sha-<full 40-char GITHUB_SHA> (see
compute-service/.github/workflows/build-and-push.yml, step "Derive
image tags").  Supply the value via the ArgoCD Application's
helm.parameters — image.digest is preferred, e.g.:
  - name: image.digest
    value: sha256:abc123...
*/}}
{{- define "compute-service.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else if .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- fail (printf "image.tag and image.digest are both empty for release %q. Set one via the ArgoCD Application's helm.parameters (image.digest is preferred). Never falls back to Chart.appVersion." .Release.Name) -}}
{{- end -}}
{{- end }}
