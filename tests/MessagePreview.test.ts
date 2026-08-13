import assert from "node:assert/strict";
import { test } from "node:test";
import type { ChatMessage } from "../src/types/chat";
import { previewForMessage } from "../src/utils/messagePreview";

const baseMessage: ChatMessage = {
  id: "message-1",
  roomId: "room-1",
  role: "user",
  createdAt: "2026-08-13T12:00:00Z"
};

test("room previews hide uploaded filenames for every supported media type", () => {
  const samples: Array<[ChatMessage, string]> = [
    [{ ...baseMessage, text: "private-photo.jpg", media: media("image") }, "Photo"],
    [{ ...baseMessage, text: "local-video.mov", media: media("video") }, "Video"],
    [{ ...baseMessage, text: "local-recording.m4a", media: media("audio") }, "Voice note"],
    [{ ...baseMessage, text: "encoded coordinates", location: { latitude: 30, longitude: 31 } }, "Location"]
  ];

  for (const [message, expected] of samples) {
    assert.equal(previewForMessage(message), expected);
  }
});

test("room previews preserve ordinary text messages", () => {
  assert.equal(previewForMessage({ ...baseMessage, text: "Hello" }), "Hello");
});

function media(type: "image" | "video" | "audio") {
  return {
    id: `media-${type}`,
    url: `https://cdn.example.com/media.${type}`,
    type
  };
}
