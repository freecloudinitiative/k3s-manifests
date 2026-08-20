{{/*
Chart name, truncated to fit Kubernetes name limits when combined with
suffixes like -serviceaccount.
*/}}
{{- define "storage-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "storage-service.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "storage-service.labels" -}}
app: {{ include "storage-service.fullname" . }}
fci.io/tier: backend
app.kubernetes.io/name: {{ include "storage-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "storage-service.selectorLabels" -}}
app: {{ include "storage-service.fullname" . }}
app.kubernetes.io/name: {{ include "storage-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "storage-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "storage-service.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
storage-service.image — authoritative image reference.

Precedence:
  1. digest set  →  {repository}@{digest}      (immutable; wins over tag)
  2. tag   set   →  {repository}:{tag}
  3. neither     →  hard error; never falls back to .Chart.AppVersion

CI produces tags of the form sha-<first 12 of GITHUB_SHA> (see
platform-common/.github/workflows/build-arm64-image.yml, step "Derive
image tags").  Supply the value via the ArgoCD Application's
helm.parameters, e.g.:
  - name: image.tag
    value: sha-abc123def456
*/}}
{{- define "storage-service.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else if .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- fail (printf "image.tag and image.digest are both empty for release %q. Set one via the ArgoCD Application's helm.parameters (e.g. --set image.tag=sha-<12-char-sha>). Never falls back to Chart.appVersion." .Release.Name) -}}
{{- end -}}
{{- end -}}
