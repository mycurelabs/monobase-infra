/**
 * Production-target safety guard for destructive seed operations.
 *
 * Extracted from scripts/seed.ts so the guard is unit-testable without running
 * the seed script's top-level CLI/side effects.
 *
 * The guard must be FAIL-CLOSED: any URL that resolves to the production API
 * hostname is treated as production regardless of scheme, port, path, query,
 * userinfo, or a trailing FQDN-root dot. Only a genuinely different hostname
 * (e.g. a preprod/sandbox/staging host, or a lookalike suffix domain) is
 * allowed through without --confirm.
 */

/**
 * Canonicalize a URL's hostname for host-equality comparison:
 *   - lowercase (DNS is case-insensitive)
 *   - strip a single trailing dot (the FQDN root, e.g. "host." === "host")
 *
 * Returns null when the input can't be parsed into a URL with a hostname. We
 * require a scheme: a bare host like "hapihub.localfirsthealth.com" is NOT a
 * valid WHATWG URL and returns null here. Callers must fail closed on null
 * (treat it as "cannot prove it's safe") rather than allowing it through.
 */
export function canonicalHostname(rawUrl: string): string | null {
  let host: string;
  try {
    host = new URL(rawUrl).hostname;
  } catch {
    return null;
  }
  if (!host) return null;
  host = host.toLowerCase();
  if (host.endsWith(".")) host = host.slice(0, -1);
  return host;
}

/**
 * Hostname of the production API endpoint the confirmation guard protects.
 * Derived from the configured production API URL via URL.hostname (NOT .host,
 * which would embed a port) so the comparison is port-insensitive.
 */
export function deriveProdApiHostname(
  productionApiUrl: string,
  fallback = "hapihub.localfirsthealth.com",
): string {
  return canonicalHostname(productionApiUrl) ?? fallback;
}

/**
 * Does the given URL resolve to the production API hostname?
 *
 * Compares canonical HOSTNAMES on both sides (URL.hostname, lowercased, trailing
 * dot stripped), so scheme, port, path, query, and userinfo are all irrelevant
 * to the match. A bare host without a scheme is unparseable and is treated as a
 * potential production target (fail closed) via a defensive canonical-string
 * comparison against the prod hostname.
 *
 * @param rawUrl        the --api-url value under scrutiny
 * @param prodHostname  the canonical production hostname (from deriveProdApiHostname)
 */
export function targetsProduction(rawUrl: string, prodHostname: string): boolean {
  const host = canonicalHostname(rawUrl);
  if (host !== null) {
    return host === prodHostname;
  }
  // Unparseable as a URL (e.g. a bare host with no scheme). Fail closed: if the
  // input, normalized the same way (lowercased, trailing dot stripped), IS the
  // prod hostname, treat it as production. This catches
  // "hapihub.localfirsthealth.com" and "hapihub.localfirsthealth.com." passed
  // without a scheme. A lookalike like "hapihub.localfirsthealth.com.evil.com"
  // is NOT an exact match and is correctly allowed.
  let normalized = rawUrl.trim().toLowerCase();
  if (normalized.endsWith(".")) normalized = normalized.slice(0, -1);
  return normalized === prodHostname;
}
