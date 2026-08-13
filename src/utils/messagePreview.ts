import type { ChatMessage } from "../types/chat";

export function previewForMessage(message: ChatMessage): string {
  if (message.location) {
    return "Location";
  }
  if (message.media?.type === "audio") {
    return "Voice note";
  }
  if (message.media?.type === "image") {
    return "Photo";
  }
  if (message.media?.type === "video") {
    return "Video";
  }
  if (message.text) {
    return message.text;
  }
  return "New message";
}
