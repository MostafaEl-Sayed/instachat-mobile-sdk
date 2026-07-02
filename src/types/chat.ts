import type { LocalMediaFile, UploadedMedia } from "./media";
import type { ChatLocation } from "./location";

export type ChatRole = "user" | "assistant" | "system";
export type ChatMessageStatus = "sending" | "sent" | "failed";

export interface ChatMessage {
  id: string;
  roomId?: string;
  role: ChatRole;
  text?: string;
  media?: UploadedMedia;
  location?: ChatLocation;
  createdAt: string;
  status?: ChatMessageStatus;
  userId?: string;
}

export interface OutgoingMessage {
  roomId?: string;
  text?: string;
  media?: UploadedMedia;
  location?: ChatLocation;
  localMedia?: LocalMediaFile;
  userId: string;
  createdAt?: string;
  metadata?: Record<string, unknown>;
}

export interface ChatSessionConfig {
  sessionId?: string;
  authToken?: string;
  endpoint?: string;
  metadata?: Record<string, unknown>;
}
