import { writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import WebSocket from "ws";

const baseUrl = process.env.INSTACHAT_BASE_URL || "https://instachat.instakit.pro";
const token = process.env.INSTACHAT_TOKEN || "";

if (!token) {
  throw new Error("Set INSTACHAT_TOKEN or keep the example token configured before running contract tests.");
}

const headers = { Authorization: `Bearer ${token}` };
const room = await fetchJson(`${baseUrl}/api/v1/me/rooms`, { headers }).then((rooms) => rooms[0]);
assert(room?.id, "GET /api/v1/me/rooms returned no rooms");

const messages = await fetchJson(`${baseUrl}/api/v1/rooms/${room.id}/messages?limit=10`, { headers });
assert(Array.isArray(messages.data), "GET /messages must return { data: [] }");

await assertWsSend(room.id, {
  content: "Contract text probe",
  type: "text",
  attachment_ids: []
});

await assertWsSend(room.id, {
  content: JSON.stringify({ latitude: 37.7749, longitude: -122.4194, name: "Contract location probe" }),
  type: "location",
  attachment_ids: []
});

const imageAttachment = await uploadProbeFile(room.id, "contract-image.png", "image/png", pngBytes());
assert(imageAttachment.type === "image", "image upload must return type=image");
await assertWsSend(room.id, {
  content: "Contract image probe",
  type: "image",
  attachment_ids: [imageAttachment.id]
});

const videoAttachment = await uploadProbeFile(room.id, "contract-video.mp4", "video/mp4", videoBytes());
assert(videoAttachment.type === "video" || videoAttachment.content_type === "video/mp4", "video upload must return video metadata");
await assertWsSend(room.id, {
  content: "Contract video probe",
  type: "file",
  attachment_ids: [videoAttachment.id]
});

console.log("InstaChat live contract test passed.");

async function fetchJson(url, init) {
  const response = await fetch(url, init);
  if (!response.ok) {
    throw new Error(`${url} failed with ${response.status}: ${await response.text()}`);
  }
  return response.json();
}

async function uploadProbeFile(roomId, name, type, bytes) {
  const path = join(tmpdir(), name);
  writeFileSync(path, bytes);
  const formData = new FormData();
  formData.append("file", new Blob([bytes], { type }), name);
  return fetchJson(`${baseUrl}/api/v1/rooms/${roomId}/attachments`, {
    method: "POST",
    headers,
    body: formData
  });
}

function assertWsSend(roomId, payload) {
  return new Promise((resolve, reject) => {
    const wsUrl = baseUrl.replace(/^https:/, "wss:").replace(/^http:/, "ws:").replace(/\/+$/, "");
    const ws = new WebSocket(`${wsUrl}/ws?token=${encodeURIComponent(token)}`);
    const timeout = setTimeout(() => {
      ws.close();
      reject(new Error(`Timed out waiting for ${payload.type} contract message`));
    }, 10000);

    ws.on("open", () => {
      ws.send(JSON.stringify({ type: "message.send", payload: { room_id: roomId, ...payload } }));
    });

    ws.on("message", (data) => {
      const frames = data
        .toString()
        .split(/\r?\n/)
        .filter(Boolean)
        .map((frame) => JSON.parse(frame));
      const delivered = frames.some((frame) => frame.type === "message.delivered" && frame.payload?.room_id === roomId);
      const message = frames.find((frame) => frame.type === "message.new" && frame.payload?.content === payload.content);
      if (delivered && message) {
        clearTimeout(timeout);
        ws.close();
        resolve(message.payload);
      }
    });

    ws.on("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
  });
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function pngBytes() {
  return Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=", "base64");
}

function videoBytes() {
  return Buffer.from([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6d, 0x70, 0x34, 0x32, 0x00, 0x00, 0x00, 0x00, 0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d]);
}
