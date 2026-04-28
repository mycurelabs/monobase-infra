// Loaded into the NGF data-plane container as a ConfigMap volume
// (see charts/nginx-gateway/templates/njs-security-headers-cm.yaml) and wired
// into every location block via a SnippetsPolicy `js_header_filter` directive.
//
// Overrides the `Server` response header — `delete` is not enough because
// NGINX's core header filter only emits its default `Server: nginx` when
// `r->headers_out.server` is NULL, and `delete` leaves it NULL. Setting the
// field to an empty string makes NGINX skip its default and emit nothing
// useful, which closes vapt-2025#10 L-001 without rebuilding the NGF data-
// plane image (which would otherwise need `headers-more`).

function clearServer(r) {
  r.headersOut['Server'] = '';
}

export default { clearServer };
