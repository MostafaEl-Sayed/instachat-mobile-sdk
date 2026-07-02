import type { LocalMediaFile } from "../types/media";

export function getFileNameFromUri(uri: string, fallback = "media"): string {
  const cleanUri = uri.split("?")[0] ?? uri;
  return cleanUri.split("/").pop() || fallback;
}

export function createLocalMediaFile(uri: string, type: LocalMediaFile["type"], overrides: Partial<LocalMediaFile> = {}): LocalMediaFile {
  return {
    uri,
    type,
    name: getFileNameFromUri(uri, `${type}-upload`),
    ...overrides
  };
}
