# Pod Security Standards — Exception Register

Use sparingly — only for components that cannot meet the restricted profile.

CURRENT exceptions (live cluster, set via ArgoCD managedNamespaceMetadata or
kubectl labels — see charts/argocd-infrastructure/templates/{velero,monitoring}.yaml):

- kube-system                 privileged (managed by DOKS)
- velero                      audit/warn=baseline only — node-agent is
                              privileged + hostPath BY DESIGN (reads pod
                              volumes for FSB). Documented exception; exec
                              into this namespace reaches PHI volumes, the
                              control is kubeconfig custody.
- monitoring                  audit/warn=baseline only — node-exporter is
                              hostNetwork + hostPath BY DESIGN (node metrics).
                              ALSO houses promtail (DaemonSet): runs as root
                              (default) + hostPath mounts (/var/log,
                              /var/lib/docker/containers) BY DESIGN — it tails
                              node/container log files, which requires host FS
                              read + root. Compensating controls: promtail is
                              NONPROD-ONLY on DOKS (no node-pool tolerations, so
                              it never lands on prod-db/prod-apps/infra), read-
                              only-root-fs + drop-ALL caps on its own container,
                              and its container security context sets
                              allowPrivilegeEscalation:false. Follow-ups: (1)
                              migrate to Grafana Alloy — promtail is deprecated
                              upstream (EOL 2026); (2) drop root via
                              runAsUser + a supplemental group with read on the
                              log paths; (3) pin image digests. Plan to remove:
                              superseded by the Alloy migration.
- argocd                      enforce=baseline (holds cluster-admin; no
                              privileged pods, restricted is the goal)
- cert-manager                enforce=baseline
- external-secrets-system     enforce=baseline
- external-dns                enforce=baseline
- default                     enforce=restricted (nothing may run here)

All client namespaces (mycure-production, mycure-preprod): restricted ✅

When to Use Exceptions

✅ System Components:

- CSI drivers
- Network plugins (Cilium)
- Monitoring agents (node exporters)
- Backup agents (velero node-agent)

❌ Application Workloads:

- Never relax PSS for applications
- Fix the application to comply with restricted profile
- No exceptions allowed for PHI-handling workloads

Exception Documentation

If you create an exception, document:

1. Why the exception is needed
2. What specific requirement cannot be met
3. Compensating controls (if any)
4. Plan to remove exception (if possible)
5. Risk assessment

Audit Exception Usage

List all namespaces with non-restricted PSS
kubectl get namespaces -o json | \
  jq -r '.items[] | select(.metadata.labels."pod-security.kubernetes.io/enforce" != "restricted") | .metadata.name'

HIPAA Compliance Note

For HIPAA compliance:

- Document all PSS exceptions in System Security Plan
- Justify why restricted profile cannot be used
- Implement compensating controls
- Regular security reviews of excepted workloads
- Include in annual risk assessment
