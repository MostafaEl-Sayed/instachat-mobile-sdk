import type { LocalMediaFile, MediaKind, UploadedMedia } from "../types/media";

export interface MediaUploadProvider {
  upload(file: LocalMediaFile, roomId?: string): Promise<UploadedMedia>;
}

export interface MediaPickerProvider {
  pickMedia(kind: Exclude<MediaKind, "audio">): Promise<LocalMediaFile | null>;
}
