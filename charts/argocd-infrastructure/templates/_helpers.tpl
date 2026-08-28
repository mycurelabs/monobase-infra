{{/*
Ops-plane pod placement (nodeSelector + tolerations) for the infrastructure
operators. Defaults to the "infra" node pool; override infra.nodeSelector /
infra.tolerations in values/clusters/<cluster>/argocd/infrastructure.yaml
(set both empty to schedule anywhere, or use your own pool labels/taints).
Emits nothing for an empty nodeSelector/tolerations, so overriding to {} / []
removes the constraint entirely.
*/}}
{{- define "argocd-infrastructure.infraPlacement" -}}
{{- with .Values.infra.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.infra.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
