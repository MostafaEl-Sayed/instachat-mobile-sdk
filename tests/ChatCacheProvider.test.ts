import assert from "node:assert/strict";
import { test } from "node:test";
import { MemoryChatCacheProvider } from "../src/providers/ChatCacheProvider";

test("MemoryChatCacheProvider dedupes, sorts, and trims messages per room", async () => {
  const cache = new MemoryChatCacheProvider({ maxMessagesPerRoom: 2 });

  await cache.setRoomMessages("room-1", [
    { id: "m-2", roomId: "room-1", role: "assistant", text: "Second", createdAt: "2026-06-29T10:02:00Z" },
    { id: "m-1", roomId: "room-1", role: "assistant", text: "First", createdAt: "2026-06-29T10:01:00Z" }
  ]);
  await cache.upsertRoomMessages("room-1", [
    { id: "m-2", roomId: "room-1", role: "assistant", text: "Second updated", createdAt: "2026-06-29T10:02:00Z" },
    { id: "m-3", roomId: "room-1", role: "user", text: "Third", createdAt: "2026-06-29T10:03:00Z" }
  ]);

  const cached = await cache.getRoomMessages("room-1");

  assert.deepEqual(
    cached.map((message) => message.id),
    ["m-2", "m-3"]
  );
  assert.equal(cached[0].text, "Second updated");
});
