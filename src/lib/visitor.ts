const KEY = "diary-visitor-id";

/** Stable per-browser identifier used to prevent duplicate likes. */
export function getVisitorId(): string {
  if (typeof window === "undefined") return "";
  let id = window.localStorage.getItem(KEY);
  if (!id) {
    id = `v-${crypto.randomUUID()}`;
    window.localStorage.setItem(KEY, id);
  }
  return id;
}
