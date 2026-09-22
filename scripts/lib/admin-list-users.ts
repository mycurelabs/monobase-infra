/**
 * Better Auth admin `list-users` request shaping.
 *
 * Extracted from scripts/seed.ts so the request shape is unit-testable without
 * running the seed script's top-level CLI/side effects.
 *
 * Better Auth registers `admin/list-users` as a GET endpoint that reads its
 * filters from QUERY PARAMETERS (packages/better-auth/src/plugins/admin/routes.ts
 * registers only GET; packages/better-auth/src/plugins/admin/client.ts maps the
 * `listUsers` action to GET). Calling it with POST + a JSON body method-errors
 * before the handler ever runs — so BOTH the reset permission probe and the
 * cleanup listing must issue GET with the filters URL-encoded on the query
 * string, using the admin plugin's documented param names:
 *   - limit           (number)
 *   - offset          (number)
 *   - searchField     ("email" | "name")
 *   - searchValue     (string)
 *   - searchOperator  ("contains" | "starts_with" | "ends_with")
 *   - sortBy, sortDirection, filterField, filterValue, filterOperator (unused here)
 */

export interface ListUsersQuery {
  limit?: number;
  offset?: number;
  searchField?: string;
  searchValue?: string;
  searchOperator?: string;
  sortBy?: string;
  sortDirection?: string;
  filterField?: string;
  filterValue?: string;
  filterOperator?: string;
}

/**
 * Build a URL-encoded query string (without a leading "?") for a GET
 * `admin/list-users` request from the given filters. Undefined/null values are
 * omitted; numbers are stringified. Uses URLSearchParams so every value is
 * percent-encoded (e.g. a "+" in a service email won't be mis-decoded to a
 * space).
 */
export function buildListUsersQuery(params: ListUsersQuery): string {
  const usp = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null) continue;
    usp.set(key, String(value));
  }
  return usp.toString();
}

/**
 * Full request path (path + "?" + query) for a GET `admin/list-users` call.
 * Returns the bare path when there are no params. This is what gets handed to
 * the seed script's `api("GET", path)` helper.
 */
export function listUsersPath(
  params: ListUsersQuery,
  basePath = "/auth/admin/list-users",
): string {
  const qs = buildListUsersQuery(params);
  return qs ? `${basePath}?${qs}` : basePath;
}
