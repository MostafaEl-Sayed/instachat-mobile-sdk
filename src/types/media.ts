export type MediaKind = "image" | "video" | "audio";

export interface LocalMediaFile {
  uri: string;
  type: MediaKind;
  name?: string;
  mimeType?: string;
  size?: number;
  width?: number;
  height?: number;
  durationMs?: number;
}

export interface UploadedMedia {
  id: string;
  url: string;
  type: MediaKind;
  name?: string;
  mimeType?: string;
  size?: number;
  thumbnailUrl?: string;
  metadata?: Record<string, unknown>;
}
