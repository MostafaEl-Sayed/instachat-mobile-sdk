import { readFileSync } from "node:fs";
import { basename, extname } from "node:path";
import WebSocket from "ws";

const baseUrl = (process.env.INSTACHAT_BASE_URL || "https://instachat.instakit.pro").replace(/\/+$/, "");
const token = process.env.INSTACHAT_TOKEN?.trim() || "";
const roomId = process.env.INSTACHAT_TEST_ROOM_ID?.trim() || "";
const allowMutations = process.env.INSTACHAT_ALLOW_MUTATION_TESTS === "true";

assert(token, "Set INSTACHAT_TOKEN before running live contract tests.");
assert(
  roomId,
  "Set INSTACHAT_TEST_ROOM_ID to a dedicated test room. The test will never select a consumer room automatically."
);
assert(
  allowMutations,
  "Set INSTACHAT_ALLOW_MUTATION_TESTS=true to acknowledge that this test persists messages in the selected room."
);

const headers = { Authorization: `Bearer ${token}` };
const rooms = await fetchJson(`${baseUrl}/api/v1/me/rooms`, { headers });
assert(Array.isArray(rooms), "GET /api/v1/me/rooms must return an array");
assert(rooms.some((room) => room?.id === roomId), `Room ${roomId} is not available to this token`);

const messages = await fetchJson(`${baseUrl}/api/v1/rooms/${roomId}/messages?limit=10`, { headers });
assert(Array.isArray(messages.data), "GET /messages must return { data: [] }");

const runId = new Date().toISOString();
await assertWsSend(roomId, {
  content: `[SDK contract test ${runId}] text`,
  type: "text",
  attachment_ids: []
});

await assertWsSend(roomId, {
  content: JSON.stringify({
    latitude: 37.7749,
    longitude: -122.4194,
    name: `[SDK contract test ${runId}] location`
  }),
  type: "location",
  attachment_ids: []
});

if (process.env.INSTACHAT_TEST_IMAGE_PATH) {
  const image = loadMediaFixture(process.env.INSTACHAT_TEST_IMAGE_PATH, "image");
  const attachment = await uploadFixture(roomId, image);
  assert(attachment.type === "image", "image upload must return type=image");
  await assertWsSend(roomId, {
    content: `[SDK contract test ${runId}] image`,
    type: "image",
    attachment_ids: [attachment.id]
  });
}

if (process.env.INSTACHAT_TEST_VIDEO_PATH) {
  const video = loadMediaFixture(process.env.INSTACHAT_TEST_VIDEO_PATH, "video");
  const attachment = await uploadFixture(roomId, video);
  assert(
    attachment.type === "video" || attachment.content_type === video.mimeType,
    "video upload must return video metadata"
  );
  await assertWsSend(roomId, {
    content: `[SDK contract test ${runId}] video`,
    type: "file",
    attachment_ids: [attachment.id]
  });
}

console.log(`InstaChat live contract test passed for dedicated room ${roomId}.`);

async function fetchJson(url, init) {
  const response = await fetch(url, init);
  if (!response.ok) {
    throw new Error(`${url} failed with ${response.status}: ${await response.text()}`);
  }
  return response.json();
}

async function uploadFixture(targetRoomId, fixture) {
  const formData = new FormData();
  formData.append("file", new Blob([fixture.bytes], { type: fixture.mimeType }), fixture.name);
  return fetchJson(`${baseUrl}/api/v1/rooms/${targetRoomId}/attachments`, {
    method: "POST",
    headers,
    body: formData
  });
}

function loadMediaFixture(path, kind) {
  const name = basename(path);
  const extension = extname(name).toLowerCase();
  const bytes = readFileSync(path);
  const mimeType = mediaMimeType(extension, kind);

  assert(bytes.length >= 1024, `${kind} fixture ${name} is too small to represent usable media`);
  if (kind === "image") {
    const isPng = bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
    const isJpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes.at(-2) === 0xff && bytes.at(-1) === 0xd9;
    assert(isPng || isJpeg, `${name} is not a valid PNG or JPEG fixture`);
    if (isPng) {
      assert(bytes.readUInt32BE(16) > 1 && bytes.readUInt32BE(20) > 1, `${name} must be larger than 1x1 pixel`);
    }
  } else {
    assert(bytes.subarray(4, 8).toString("ascii") === "ftyp", `${name} is not a valid MP4 fixture`);
  }

  return { name, mimeType, bytes };
}

function mediaMimeType(extension, kind) {
  if (kind === "image") {
    assert([".png", ".jpg", ".jpeg"].includes(extension), "Image fixture must be PNG or JPEG");
    return extension === ".png" ? "image/png" : "image/jpeg";
  }
  assert(extension === ".mp4", "Video fixture must be MP4");
  return "video/mp4";
}

function assertWsSend(targetRoomId, payload) {
  return new Promise((resolve, reject) => {
    const wsUrl = baseUrl.replace(/^https:/, "wss:").replace(/^http:/, "ws:");
    const ws = new WebSocket(`${wsUrl}/ws?token=${encodeURIComponent(token)}`);
    const timeout = setTimeout(() => {
      ws.close();
      reject(new Error(`Timed out waiting for ${payload.type} contract message`));
    }, 10000);

    ws.on("open", () => {
      ws.send(JSON.stringify({ type: "message.send", payload: { room_id: targetRoomId, ...payload } }));
    });

    ws.on("message", (data) => {
      const frames = data
        .toString()
        .split(/\r?\n/)
        .filter(Boolean)
        .map((frame) => JSON.parse(frame));
      const delivered = frames.some(
        (frame) => frame.type === "message.delivered" && frame.payload?.room_id === targetRoomId
      );
      const message = frames.find(
        (frame) => frame.type === "message.new" && frame.payload?.content === payload.content
      );
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
