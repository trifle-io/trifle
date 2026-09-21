{{/* Leave room for gateway and Secret suffixes within DNS label limits. */}}
{{- define "trifle.networkGatewayName" -}}
{{- printf "%s-network-gateway" (include "trifle.fullname" . | trunc 40 | trimSuffix "-") -}}
{{- end -}}

{{- define "trifle.networkGatewayStateSecret" -}}
{{- .Values.networkGateway.stateKeySecret | default (printf "%s-state" (include "trifle.networkGatewayName" .)) -}}
{{- end -}}

{{- define "trifle.networkGatewayServerSecret" -}}
{{- .Values.networkGateway.serverTLSSecret | default (printf "%s-server" (include "trifle.networkGatewayName" .)) -}}
{{- end -}}

{{- define "trifle.networkGatewayClientSecret" -}}
{{- .Values.networkGateway.clientTLSSecret | default (printf "%s-client" (include "trifle.networkGatewayName" .)) -}}
{{- end -}}
