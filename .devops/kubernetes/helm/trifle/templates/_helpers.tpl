{{/*
Expand the name of the chart.
*/}}
{{- define "trifle.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "trifle.fullname" -}}
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
{{- define "trifle.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "trifle.labels" -}}
helm.sh/chart: {{ include "trifle.chart" . }}
{{ include "trifle.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "trifle.selectorLabels" -}}
app.kubernetes.io/name: {{ include "trifle.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "trifle.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "trifle.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Database URL helper
*/}}
{{- define "trifle.databaseUrl" -}}
{{- if .Values.postgresql.enabled }}
postgresql://{{ .Values.postgresql.auth.username }}:{{ .Values.postgresql.auth.password }}@{{ include "trifle.fullname" . }}-postgresql:5432/{{ .Values.postgresql.auth.database }}
{{- else }}
postgresql://{{ .Values.externalPostgresql.username }}:{{ .Values.externalPostgresql.password }}@{{ .Values.externalPostgresql.host }}:{{ .Values.externalPostgresql.port }}/{{ .Values.externalPostgresql.database }}
{{- end }}
{{- end }}

{{/*
Internal observability toggle shared by the app and release hook jobs.
Explicit app.env overrides take precedence, without duplicate env entries.
*/}}
{{- define "trifle.observabilityEnv" -}}
{{- $appEnv := .Values.app.env | default (dict) -}}
{{- $observability := .Values.app.observability | default (dict) -}}
{{- if not (hasKey $appEnv "TRIFLE_OBSERVABILITY_ENABLED") -}}
- name: TRIFLE_OBSERVABILITY_ENABLED
  {{- if hasKey $observability "enabled" }}
  value: {{ index $observability "enabled" | quote }}
  {{- else }}
  value: "true"
  {{- end }}
{{- end -}}
{{- end -}}

{{/* Internal observability storage shared by the app and release jobs. */}}
{{- define "trifle.observabilityStorageEnv" -}}
{{- $appEnv := .Values.app.env | default (dict) -}}
{{- $observability := .Values.app.observability | default (dict) -}}
{{- $traces := .Values.app.traces | default (dict) -}}
{{- $sqliteStorage := .Values.app.sqliteStorage | default (dict) -}}
{{- $objectStore := (index $sqliteStorage "objectStore") | default (dict) -}}
{{- if and (not (hasKey $appEnv "MONGODB_URL")) .Values.app.mongodbUrl }}
- name: MONGODB_URL
  valueFrom:
    secretKeyRef:
      name: {{ include "trifle.fullname" . }}-secret
      key: mongodb-url
{{- end }}
{{- if and (not (hasKey $appEnv "TRIFLE_OBSERVABILITY_INDEX_BACKEND")) (hasKey $observability "indexBackend") }}
- name: TRIFLE_OBSERVABILITY_INDEX_BACKEND
  value: {{ index $observability "indexBackend" | quote }}
{{- end }}
{{- if and (not (hasKey $appEnv "TRIFLE_TRACES_STORAGE_BACKEND")) (index $traces "storageBackend") }}
- name: TRIFLE_TRACES_STORAGE_BACKEND
  value: {{ index $traces "storageBackend" | quote }}
{{- end }}
{{- if and (not (hasKey $appEnv "TRIFLE_TRACES_STORAGE_PATH")) (hasKey $traces "storagePath") }}
- name: TRIFLE_TRACES_STORAGE_PATH
  value: {{ index $traces "storagePath" | quote }}
{{- end }}
{{- if and (not (hasKey $appEnv "TRIFLE_TRACES_RETENTION_DAYS")) (hasKey $traces "retentionDays") }}
- name: TRIFLE_TRACES_RETENTION_DAYS
  value: {{ index $traces "retentionDays" | quote }}
{{- end }}
{{- if and (not (hasKey $appEnv "TRIFLE_TRACES_GZIP")) (hasKey $traces "gzip") }}
- name: TRIFLE_TRACES_GZIP
  value: {{ index $traces "gzip" | quote }}
{{- end }}
{{- if and (not (hasKey $appEnv "TRIFLE_TRACES_MANAGE_S3_LIFECYCLE")) (hasKey $traces "manageS3Lifecycle") }}
- name: TRIFLE_TRACES_MANAGE_S3_LIFECYCLE
  value: {{ index $traces "manageS3Lifecycle" | quote }}
{{- end }}
{{- if and (eq (index $traces "storageBackend") "s3") (index $traces "useSqliteObjectStore") }}
{{- if not (hasKey $appEnv "TRIFLE_TRACES_S3_ENDPOINT") }}
- name: TRIFLE_TRACES_S3_ENDPOINT
  value: {{ index $objectStore "endpoint" | quote }}
{{- end }}
{{- if not (hasKey $appEnv "TRIFLE_TRACES_S3_BUCKETS") }}
- name: TRIFLE_TRACES_S3_BUCKETS
  value: {{ index $objectStore "bucket" | quote }}
{{- end }}
{{- if not (hasKey $appEnv "TRIFLE_TRACES_S3_REGION") }}
- name: TRIFLE_TRACES_S3_REGION
  value: {{ index $objectStore "region" | quote }}
{{- end }}
{{- if not (hasKey $appEnv "TRIFLE_TRACES_S3_PREFIX") }}
- name: TRIFLE_TRACES_S3_PREFIX
  value: {{ index $traces "s3Prefix" | default "traces" | quote }}
{{- end }}
{{- if and (not (hasKey $appEnv "TRIFLE_TRACES_S3_ACCESS_KEY_ID")) (index $objectStore "accessKeyId") }}
- name: TRIFLE_TRACES_S3_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "trifle.fullname" . }}-secret
      key: sqlite-object-store-access-key-id
{{- end }}
{{- if and (not (hasKey $appEnv "TRIFLE_TRACES_S3_SECRET_ACCESS_KEY")) (index $objectStore "secretAccessKey") }}
- name: TRIFLE_TRACES_S3_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "trifle.fullname" . }}-secret
      key: sqlite-object-store-secret-access-key
{{- end }}
{{- end }}
{{- end -}}
