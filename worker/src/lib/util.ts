export function now(): string {
  return new Date().toISOString();
}

/** Parse the metadata JSON column for API responses. */
export function serialize<T extends { metadata: string }>(
  row: T
): Omit<T, "metadata"> & { metadata: Record<string, unknown> } {
  return { ...row, metadata: JSON.parse(row.metadata) };
}
