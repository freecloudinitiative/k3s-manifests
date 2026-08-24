{{/*
Chart name, truncated to fit Kubernetes name limits when combined with
suffixes like -serviceaccount.
*/}}
{{- define "iam-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "iam-service.fullname" -}}
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

{{- define "iam-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "iam-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "iam-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: iam-service
fci.io/tier: backend
{{- end }}

{{- define "iam-service.labels" -}}
helm.sh/chart: {{ include "iam-service.chart" . }}
{{ include "iam-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "iam-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "iam-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
iam-service.image — authoritative image reference.

Precedence:
  1. digest set  →  {repository}@{digest}      (immutable; wins over tag)
  2. tag   set   →  {repository}:{tag}
  3. neither     →  hard error; never falls back to .Chart.AppVersion

CI produces tags of the form sha-<full 40-char GITHUB_SHA> (see
iam-service/.github/workflows/build-and-push.yml, step "Derive
image tags").  Supply the value via the ArgoCD Application's
helm.parameters — image.digest is preferred, e.g.:
  - name: image.digest
    value: sha256:abc123...
*/}}
{{- define "iam-service.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else if .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- fail (printf "image.tag and image.digest are both empty for release %q. Set one via the ArgoCD Application's helm.parameters (image.digest is preferred). Never falls back to Chart.appVersion." .Release.Name) -}}
{{- end -}}
{{- end }}
