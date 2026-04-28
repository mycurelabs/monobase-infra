// Loaded into the NGF data-plane container as a ConfigMap volume
// (see charts/nginx-gateway/templates/njs-security-headers-cm.yaml) and wired
// into every server block via a SnippetsPolicy `js_header_filter` directive.
//
// Removes the `Server` response header, which OSS NGINX cannot suppress with
// `server_tokens` alone (that only hides the version). Closes vapt-2025#10
// L-001 without rebuilding the NGF data-plane image.

function clearServer(r) {
  delete r.headersOut['Server'];
}

export default { clearServer };
