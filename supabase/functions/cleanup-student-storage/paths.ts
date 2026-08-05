const UUID_HEX_PATTERN = /^[0-9a-f]{32}$/;

/**
 * Normalizes UUID-like storage folder/object names (hyphenated, braced, bare hex)
 * to a 32-char lowercase hex string, or null if the name is not a UUID.
 */
export function normalizeUuidLike(value: string): string | null {
  const unwrapped = value.startsWith("{") && value.endsWith("}")
    ? value.slice(1, -1)
    : value;
  const hex = unwrapped.replaceAll("-", "").toLowerCase();
  return UUID_HEX_PATTERN.test(hex) ? hex : null;
}

/** Formats a 32-char hex UUID as the canonical hyphenated path prefix. */
export function canonicalUuid(hex: string): string {
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${
    hex.slice(16, 20)
  }-${hex.slice(20)}`;
}

/**
 * True when a bucket root object name is the same student as `normalizedStudentId`
 * (after UUID normalization). Deliberately rejects arbitrary prefix matching.
 */
export function rootNameMatchesStudent(
  objectName: string,
  normalizedStudentId: string,
): boolean {
  return normalizeUuidLike(objectName) === normalizedStudentId;
}

export function joinStoragePath(folder: string, name: string): string {
  return folder ? `${folder}/${name}` : name;
}
