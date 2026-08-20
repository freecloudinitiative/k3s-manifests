{{/*
Expand the name of the chart.
*/}}
{{- define "api-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "api-gateway.fullname" -}}
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

{{/*
Create chart label value.
*/}}
{{- define "api-gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "api-gateway.labels" -}}
helm.sh/chart: {{ include "api-gateway.chart" . }}
{{ include "api-gateway.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — used for Service and PDB selectors, and the Deployment
spec.selector. Must be immutable after first deploy.
*/}}
{{- define "api-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "api-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: api-gateway
{{- end }}

{{/*
Container image reference with explicit tag/digest enforcement.

Precedence:
  1. image.digest set → {repository}@{digest}
  2. image.tag set   → {repository}:{tag}
  3. neither         → fail (no silent fallback to .Chart.AppVersion)

The tag or digest must be supplied by the ArgoCD Application's helm.parameters
(image.tag=sha-<12> or image.digest=sha256:<...>). A missing value fails loudly
at render time rather than producing an ImagePullBackOff in the cluster.
*/}}
{{- define "api-gateway.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository (.Values.image.digest | toString) -}}
{{- else if .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | toString) -}}
{{- else -}}
{{- fail "image.tag or image.digest must be set — supply it via the ArgoCD Application's helm.parameters (image.tag=sha-<12>)" -}}
{{- end -}}
{{- end -}}
