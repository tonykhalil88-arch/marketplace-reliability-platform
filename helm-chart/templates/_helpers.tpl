{{/*
Common helper templates for the product-catalog chart.
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "product-catalog.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "product-catalog.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "product-catalog.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource.
*/}}
{{- define "product-catalog.labels" -}}
helm.sh/chart: {{ include "product-catalog.chart" . }}
{{ include "product-catalog.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: marketplace-platform
team: platform
region: {{ .Values.config.region }}
environment: {{ .Values.config.environment }}
{{- end }}

{{/*
Selector labels — used in deployment and service selectors.
*/}}
{{- define "product-catalog.selectorLabels" -}}
app.kubernetes.io/name: {{ include "product-catalog.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name.
*/}}
{{- define "product-catalog.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "product-catalog.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Datadog unified service tags — used for correlation across
traces, metrics, and logs in the Datadog UI.
*/}}
{{- define "product-catalog.datadogLabels" -}}
tags.datadoghq.com/env: {{ .Values.config.environment }}
tags.datadoghq.com/service: {{ include "product-catalog.name" . }}
tags.datadoghq.com/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
{{- end }}
