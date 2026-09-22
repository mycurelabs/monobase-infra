/**
 * Focused tests for the seed script's Better Auth admin `list-users` calls.
 *
 * Regression coverage for PR #455 review (jofftiquez): both the --reset live
 * permission probe (seed.ts ~7533) and the reset cleanup listing (seed.ts
 * ~8039) previously called `admin/list-users` with POST + a JSON body. But
 * Better Auth registers `admin/list-users` as a GET route that reads its
 * filters from QUERY PARAMETERS (packages/better-auth/src/plugins/admin/
 * routes.ts registers only GET; .../admin/client.ts maps `listUsers` to GET).
 * A POST method-errors before the handler runs, so the probe aborted EVERY
 * reset — even for correctly-elevated service accounts — and the cleanup
 * listing was broken the same way.
 *
 * The fix moves both call sites to GET with the filters URL-encoded on the
 * query string via `listUsersPath()`. These tests assert:
 *   (1) the query-string shaping (helper) carries the expected params;
 *   (2) the request layer issues a GET with NO body and the params on the URL;
 *   (3) the permission probe treats 200 as authorized, 401/403 as a
 *       fail-closed abort;
 *   (4) the cleanup listing uses the same GET shape and a listing failure is
 *       surfaced (collected), not swallowed.
 *
 * Run: bun test scripts/seed.adminListUsers.test.ts
 */
import { describe, expect, test } from "bun:test";
import { buildListUsersQuery, listUsersPath } from "./lib/admin-list-users";

// ---------------------------------------------------------------------------
// (1) Query-string shaping
// ---------------------------------------------------------------------------
describe("buildListUsersQuery / listUsersPath", () => {
  test("encodes the probe filters onto the query string", () => {
    const qs = buildListUsersQuery({
      limit: 1,
      searchValue: "svc+seed@example.com",
      searchField: "email",
      searchOperator: "contains",
    });
    const parsed = new URLSearchParams(qs);
    expect(parsed.get("limit")).toBe("1");
    expect(parsed.get("searchField")).toBe("email");
    expect(parsed.get("searchOperator")).toBe("contains");
    // The "+" in the service email must be percent-encoded so it round-trips
    // as a literal plus, not a space.
    expect(parsed.get("searchValue")).toBe("svc+seed@example.com");
    expect(qs).toContain("svc%2Bseed%40example.com");
  });

  test("omits undefined params (cleanup listing has no limit)", () => {
    const qs = buildListUsersQuery({
      searchValue: "user@example.com",
      searchField: "email",
      searchOperator: "contains",
    });
    const parsed = new URLSearchParams(qs);
    expect(parsed.has("limit")).toBe(false);
    expect(parsed.get("searchField")).toBe("email");
  });

  test("listUsersPath prefixes the admin route and a single '?'", () => {
    const path = listUsersPath({ limit: 1, searchField: "email" });
    expect(path.startsWith("/auth/admin/list-users?")).toBe(true);
    expect(path.split("?").length).toBe(2);
  });

  test("listUsersPath returns the bare path when there are no params", () => {
    expect(listUsersPath({})).toBe("/auth/admin/list-users");
  });
});

// ---------------------------------------------------------------------------
// Minimal faithful reproduction of seed.ts's `api()` request layer + the two
// call sites, so we can assert on the mocked fetch WITHOUT importing seed.ts
// (which runs parseArgs/main() at module load). This mirrors seed.ts:
//   - fetch(url, { method, body: body ? JSON.stringify(body) : undefined })
//   - throw new Error(`${method} ${path} → ${res.status}: ${text}`) on !ok
// and the probe's forbidden classifier `/ → (401|403):/`.
// ---------------------------------------------------------------------------
const API_URL = "https://hapihub.sandbox.localfirsthealth.com";

interface CapturedRequest {
  url: string;
  method: string;
  body: string | undefined;
}

function makeApi(
  status: number,
  responseBody: unknown,
  captured: CapturedRequest[],
) {
  const fetchImpl = async (
    url: string,
    init: { method: string; body?: string },
  ) => {
    captured.push({ url, method: init.method, body: init.body });
    const text = JSON.stringify(responseBody);
    return {
      ok: status >= 200 && status < 300,
      status,
      headers: { getSetCookie: () => [] as string[] },
      text: async () => text,
    };
  };
  // Faithful copy of the relevant slice of seed.ts's api().
  return async function api(method: string, path: string, body?: unknown) {
    const res = await fetchImpl(`${API_URL}${path}`, {
      method,
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    if (!res.ok) {
      throw new Error(`${method} ${path} → ${res.status}: ${text}`);
    }
    return text ? JSON.parse(text) : {};
  };
}

// The permission probe, extracted verbatim in shape from seed.ts (~7533):
// GET list-users with the probe filters; classify 401/403 as fail-closed.
async function runProbe(
  api: (m: string, p: string, b?: unknown) => Promise<unknown>,
  serviceEmail: string,
): Promise<{ authorized: boolean; forbidden: boolean; error?: string }> {
  try {
    await api(
      "GET",
      listUsersPath({
        limit: 1,
        searchValue: serviceEmail,
        searchField: "email",
        searchOperator: "contains",
      }),
    );
    return { authorized: true, forbidden: false };
  } catch (err) {
    const msg = (err as Error).message;
    const forbidden = / → (401|403):/.test(msg);
    return { authorized: false, forbidden, error: msg };
  }
}

// The cleanup listing, extracted in shape from seed.ts (~8039): GET list-users;
// on failure push into adminFailures (surface, non-zero) rather than swallow.
async function runCleanupListing(
  api: (m: string, p: string, b?: unknown) => Promise<unknown>,
  email: string,
): Promise<{ users: Array<{ id: string; email: string }>; failures: string[] }> {
  const failures: string[] = [];
  let listed: { users?: Array<{ id: string; email: string }> } | null = null;
  try {
    listed = (await api(
      "GET",
      listUsersPath({
        searchValue: email,
        searchField: "email",
        searchOperator: "contains",
      }),
    )) as { users?: Array<{ id: string; email: string }> };
  } catch (err) {
    failures.push(`list-users ${email}: ${(err as Error).message}`);
  }
  return { users: listed?.users ?? [], failures };
}

// ---------------------------------------------------------------------------
// (2)+(3) Permission probe
// ---------------------------------------------------------------------------
describe("permission probe — GET shape + fail-closed", () => {
  const serviceEmail = "svc+seed@example.com";

  test("issues a GET with the params on the query string and NO body", async () => {
    const captured: CapturedRequest[] = [];
    const api = makeApi(200, { users: [], total: 0 }, captured);
    const result = await runProbe(api, serviceEmail);

    expect(result.authorized).toBe(true);
    expect(captured.length).toBe(1);
    const req = captured[0];
    // Method must be GET, never POST.
    expect(req.method).toBe("GET");
    // No JSON request body — filters live on the URL.
    expect(req.body).toBeUndefined();
    // The URL carries the admin route + the encoded filters.
    expect(req.url).toContain("/auth/admin/list-users?");
    const qs = new URLSearchParams(req.url.split("?")[1]);
    expect(qs.get("limit")).toBe("1");
    expect(qs.get("searchField")).toBe("email");
    expect(qs.get("searchOperator")).toBe("contains");
    expect(qs.get("searchValue")).toBe(serviceEmail);
  });

  test("treats 200 as authorized", async () => {
    const captured: CapturedRequest[] = [];
    const api = makeApi(200, { users: [] }, captured);
    const result = await runProbe(api, serviceEmail);
    expect(result.authorized).toBe(true);
    expect(result.forbidden).toBe(false);
  });

  test("fails closed on 403 (forbidden → abort)", async () => {
    const captured: CapturedRequest[] = [];
    const api = makeApi(403, { message: "You are not allowed to list users" }, captured);
    const result = await runProbe(api, serviceEmail);
    expect(result.authorized).toBe(false);
    expect(result.forbidden).toBe(true);
    // Still a GET even on the failing path.
    expect(captured[0].method).toBe("GET");
    expect(captured[0].body).toBeUndefined();
  });

  test("fails closed on 401 (unauthorized → abort)", async () => {
    const captured: CapturedRequest[] = [];
    const api = makeApi(401, { message: "unauthorized" }, captured);
    const result = await runProbe(api, serviceEmail);
    expect(result.authorized).toBe(false);
    expect(result.forbidden).toBe(true);
  });

  test("fails closed on other errors (e.g. 500 → abort, not authorized)", async () => {
    const captured: CapturedRequest[] = [];
    const api = makeApi(500, { message: "boom" }, captured);
    const result = await runProbe(api, serviceEmail);
    expect(result.authorized).toBe(false);
    // 500 is not classified "forbidden" but still aborts (not authorized).
    expect(result.forbidden).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// (4) Cleanup listing
// ---------------------------------------------------------------------------
describe("cleanup listing — GET shape + surfaces failures", () => {
  const email = "user@example.com";

  test("issues a GET with the params on the query string and NO body", async () => {
    const captured: CapturedRequest[] = [];
    const api = makeApi(200, { users: [{ id: "u1", email }] }, captured);
    const { users, failures } = await runCleanupListing(api, email);

    expect(failures.length).toBe(0);
    expect(users).toEqual([{ id: "u1", email }]);
    const req = captured[0];
    expect(req.method).toBe("GET");
    expect(req.body).toBeUndefined();
    expect(req.url).toContain("/auth/admin/list-users?");
    const qs = new URLSearchParams(req.url.split("?")[1]);
    expect(qs.get("searchField")).toBe("email");
    expect(qs.get("searchOperator")).toBe("contains");
    expect(qs.get("searchValue")).toBe(email);
    // Cleanup listing intentionally sends no `limit`.
    expect(qs.has("limit")).toBe(false);
  });

  test("surfaces a listing failure (collected, non-zero) — not swallowed", async () => {
    const captured: CapturedRequest[] = [];
    const api = makeApi(403, { message: "You are not allowed to list users" }, captured);
    const { users, failures } = await runCleanupListing(api, email);

    expect(users.length).toBe(0);
    expect(failures.length).toBe(1);
    expect(failures[0]).toContain(`list-users ${email}`);
    expect(failures[0]).toContain("403");
    // Still a GET on the failing path.
    expect(captured[0].method).toBe("GET");
  });
});
