/**
 * Focused, fail-closed tests for the seed script's production-target guard.
 *
 * Regression coverage for PR #455 review (jofftiquez): the guard previously
 * compared WHATWG URL.host, which INCLUDES the port, so
 * `https://hapihub.localfirsthealth.com:443` / `:8443` did NOT equal the
 * configured `hapihub.localfirsthealth.com` and slipped past the --confirm
 * gate. The fix compares canonical URL.hostname on both sides.
 *
 * Run: bun test scripts/seed.targetsProduction.test.ts
 */
import { describe, expect, test } from "bun:test";
import {
  canonicalHostname,
  deriveProdApiHostname,
  targetsProduction,
} from "./lib/targets-production";

// The configured production API URL, exactly as ENVS.production.api in seed.ts.
const PROD_API_URL = "https://hapihub.localfirsthealth.com";
const PROD_HOST = deriveProdApiHostname(PROD_API_URL);

// Convenience wrapper mirroring seed.ts's bound `targetsProduction(rawUrl)`.
const hitsProd = (rawUrl: string) => targetsProduction(rawUrl, PROD_HOST);

describe("deriveProdApiHostname", () => {
  test("derives the bare hostname (no scheme, no port) from the prod URL", () => {
    expect(PROD_HOST).toBe("hapihub.localfirsthealth.com");
  });

  test("ignores an explicit port in the configured prod URL", () => {
    expect(deriveProdApiHostname("https://hapihub.localfirsthealth.com:443")).toBe(
      "hapihub.localfirsthealth.com",
    );
  });

  test("falls back when the configured URL is unparseable", () => {
    expect(deriveProdApiHostname("not a url")).toBe("hapihub.localfirsthealth.com");
  });
});

describe("targetsProduction — REJECTED (must require --confirm)", () => {
  const rejected: Array<[string, string]> = [
    ["canonical prod URL", "https://hapihub.localfirsthealth.com"],
    ["prod host, explicit default port :443", "https://hapihub.localfirsthealth.com:443"],
    ["prod host, non-default port :8443", "https://hapihub.localfirsthealth.com:8443"],
    ["prod host with a path", "https://hapihub.localfirsthealth.com/v1/organizations"],
    ["prod host with a query string", "https://hapihub.localfirsthealth.com/?reset=1"],
    ["prod host with userinfo", "https://user:pass@hapihub.localfirsthealth.com"],
    ["prod host over http (differing scheme)", "http://hapihub.localfirsthealth.com"],
    ["prod host, http + non-default port", "http://hapihub.localfirsthealth.com:8443/seed"],
    ["prod host, uppercased", "https://HAPIHUB.LocalFirstHealth.com"],
    ["trailing-dot FQDN root", "https://hapihub.localfirsthealth.com."],
    ["trailing-dot FQDN + port", "https://hapihub.localfirsthealth.com.:8443"],
    // Bare host, no scheme — decision: unparseable as a URL, so we fall back to
    // a normalized exact-string compare and REJECT if it equals the prod host.
    ["bare prod host, no scheme", "hapihub.localfirsthealth.com"],
    ["bare prod host, trailing dot, no scheme", "hapihub.localfirsthealth.com."],
    ["bare prod host, uppercased, no scheme", "HAPIHUB.localfirsthealth.COM"],
  ];

  for (const [label, url] of rejected) {
    test(`REJECTS: ${label} (${url})`, () => {
      expect(hitsProd(url)).toBe(true);
    });
  }
});

describe("targetsProduction — ALLOWED (non-production, no --confirm needed)", () => {
  const allowed: Array<[string, string]> = [
    ["preprod host", "https://hapihub.preprod.localfirsthealth.com"],
    ["staging host", "https://hapihub.staging.localfirsthealth.com"],
    ["sandbox host", "https://hapihub.sandbox.localfirsthealth.com"],
    ["localhost dev", "http://localhost:7500"],
    // Suffix-lookalike: prod hostname is a LABEL PREFIX of a different domain.
    ["evil suffix lookalike", "https://hapihub.localfirsthealth.com.evil.com"],
    ["bare evil suffix lookalike, no scheme", "hapihub.localfirsthealth.com.evil.com"],
    // Prefix-lookalike: extra chars on the leftmost label.
    ["nothapihub prefix lookalike", "https://nothapihub.localfirsthealth.com"],
    ["different TLD lookalike", "https://hapihub.localfirsthealth.org"],
    // Empty / clearly-not-a-host inputs must not accidentally match prod.
    ["empty string", ""],
    ["whitespace only", "   "],
  ];

  for (const [label, url] of allowed) {
    test(`ALLOWS: ${label} (${url})`, () => {
      expect(hitsProd(url)).toBe(false);
    });
  }
});

describe("canonicalHostname", () => {
  test("returns null for a bare host (no scheme) — callers fail closed", () => {
    expect(canonicalHostname("hapihub.localfirsthealth.com")).toBeNull();
  });

  test("lowercases and strips a single trailing dot", () => {
    expect(canonicalHostname("https://HAPIHUB.localfirsthealth.com.")).toBe(
      "hapihub.localfirsthealth.com",
    );
  });

  test("drops the port", () => {
    expect(canonicalHostname("https://hapihub.localfirsthealth.com:8443")).toBe(
      "hapihub.localfirsthealth.com",
    );
  });
});
