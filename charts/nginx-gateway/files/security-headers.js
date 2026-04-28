// Loaded into the NGF data-plane container as a ConfigMap volume
// (see charts/nginx-gateway/templates/njs-security-headers-cm.yaml) and wired
// into every location block via a SnippetsPolicy `js_header_filter` directive.
//
// Overrides the `Server` response header. Both `delete` and `=''` were tried
// first; both produced `Server: nginx` because they leave njs's
// r->headers_out.server NULL, and NGINX's core header filter then emits its
// own default. Setting a non-empty value makes NGINX skip the default. A
// single space is the smallest such value and reveals no software identifier
// — closes vapt-2025#10 L-001 without rebuilding the NGF data-plane image
// (which would otherwise need the `headers-more` module).

function clearServer(r) {
  r.headersOut['Server'] = ' ';
}

export default { clearServer };
