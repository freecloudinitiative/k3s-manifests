{{- define "terminal-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "terminal-gateway.fullname" -}}
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

{{- define "terminal-gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "terminal-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "terminal-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: terminal-gateway
fci.io/tier: backend
{{- end }}

{{- define "terminal-gateway.labels" -}}
helm.sh/chart: {{ include "terminal-gateway.chart" . }}
{{ include "terminal-gateway.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Image reference for terminal-gateway.
Fails loudly if neither image.tag nor image.digest is set;
never silently falls back to .Chart.AppVersion.
*/}}
{{- define "terminal-gateway.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else if .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- fail "image.tag or image.digest must be set (e.g. via helm.parameters in the Application manifest)" -}}
{{- end -}}
{{- end }}
