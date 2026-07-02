import assert from "node:assert/strict";
import { test } from "node:test";
import { InstaChatChatProvider, InstaChatMediaUploadProvider } from "../src/providers/InstaChatProvider";
import type { LocalMediaFile } from "../src/types/media";

const token = createJwt({ sub: "user-1" });

test("InstaChatChatProvider maps rooms and all supported message types", async () => {
  const fetchMock = createFetchMock({
    "https://chat.test/api/v1/me/rooms": [
      {
        id: "room-1",
        type: "direct",
        created_at: "2026-06-29T10:00:00Z",
        members: [
          { id: "user-1", display_name: "Current User", is_online: true },
          { id: "agent-1", display_name: "Support Agent", avatar_url: "https://avatar.test/a.png", is_online: true }
        ]
      }
    ],
    "https://chat.test/api/v1/rooms/room-1/messages?limit=50": {
      data: [
        {
          id: "m-text",
          room_id: "room-1",
          sender_id: "agent-1",
          content: "Hello",
          type: "text",
          created_at: "2026-06-29T10:01:00Z"
        },
        {
          id: "m-location",
          room_id: "room-1",
          sender_id: "user-1",
          content: JSON.stringify({ latitude: 37.7749, longitude: -122.4194, name: "Office" }),
          type: "location",
          created_at: "2026-06-29T10:02:00Z"
        },
        {
          id: "m-image",
          room_id: "room-1",
          sender_id: "agent-1",
          content: "Image",
          type: "image",
          created_at: "2026-06-29T10:03:00Z",
          attachments: [
            {
              id: "att-image",
              file_name: "photo.png",
              content_type: "image/png",
              file_size: 42,
              url: "https://files.test/photo.png"
            }
          ]
        },
        {
          id: "m-video",
          room_id: "room-1",
          sender_id: "agent-1",
          content: "Video",
          type: "file",
          created_at: "2026-06-29T10:04:00Z",
          attachments: [
            {
              id: "att-video",
              file_name: "clip.mp4",
              content_type: "video/mp4",
              file_size: 84,
              url: "https://files.test/clip.mp4"
            }
          ]
        }
      ],
      next_cursor: null
    }
  });
  installFetch(fetchMock);

  const provider = new InstaChatChatProvider({ baseUrl: "https://chat.test/", token });
  const rooms = await provider.getRooms();
  const messages = await provider.getMessages("room-1");

  assert.equal(rooms[0].id, "room-1");
  assert.equal(rooms[0].title, "Support Agent");
  assert.equal(messages[0].text, "Hello");
  assert.equal(messages[1].location?.name, "Office");
  assert.equal(messages[1].location?.latitude, 37.7749);
  assert.equal(messages[2].media?.type, "image");
  assert.equal(messages[3].media?.type, "video");
});

test("InstaChatChatProvider fetches paged messages with backend cursor", async () => {
  const fetchMock = createFetchMock({
    "https://chat.test/api/v1/rooms/room-1/messages?limit=2": {
      data: [
        {
          id: "m-2",
          room_id: "room-1",
          sender_id: "agent-1",
          content: "Second",
          type: "text",
          created_at: "2026-06-29T10:02:00Z"
        },
        {
          id: "m-1",
          room_id: "room-1",
          sender_id: "agent-1",
          content: "First",
          type: "text",
          created_at: "2026-06-29T10:01:00Z"
        }
      ],
      next_cursor: "older-cursor"
    },
    "https://chat.test/api/v1/rooms/room-1/messages?limit=2&cursor=older-cursor": {
      data: [
        {
          id: "m-0",
          room_id: "room-1",
          sender_id: "agent-1",
          content: "Older",
          type: "text",
          created_at: "2026-06-29T10:00:00Z"
        }
      ],
      next_cursor: null
    }
  });
  installFetch(fetchMock);

  const provider = new InstaChatChatProvider({ baseUrl: "https://chat.test", token, roomId: "room-1" });
  const firstPage = await provider.getMessagesPage({ roomId: "room-1", limit: 2 });
  const olderPage = await provider.getMessagesPage({ roomId: "room-1", limit: 2, cursor: firstPage.nextCursor });

  assert.deepEqual(
    firstPage.messages.map((message) => message.id),
    ["m-1", "m-2"]
  );
  assert.equal(firstPage.nextCursor, "older-cursor");
  assert.equal(firstPage.hasMore, true);
  assert.deepEqual(
    olderPage.messages.map((message) => message.id),
    ["m-0"]
  );
  assert.equal(olderPage.hasMore, false);
});

test("InstaChatChatProvider sends location content using backend contract", async () => {
  installFetch(createFetchMock({}));
  const sockets = installWebSocket();
  const provider = new InstaChatChatProvider({ baseUrl: "https://chat.test", token, roomId: "room-1" });

  const promise = provider.sendMessage({
    roomId: "room-1",
    userId: "user-1",
    location: {
      latitude: 30.0444,
      longitude: 31.2357,
      name: "Cairo",
      timestamp: "2026-06-29T10:00:00Z"
    },
    createdAt: "2026-06-29T10:00:00Z"
  });

  const socket = sockets[0];
  await socket.waitForOpen();
  await socket.waitForSent(1);
  const sent = JSON.parse(socket.sent[0]);
  assert.equal(sent.type, "message.send");
  assert.equal(sent.payload.room_id, "room-1");
  assert.equal(sent.payload.type, "location");
  assert.deepEqual(JSON.parse(sent.payload.content), { latitude: 30.0444, longitude: 31.2357, name: "Cairo" });

  socket.receive(
    [
      JSON.stringify({ type: "message.delivered", payload: { message_id: "m-location", room_id: "room-1" } }),
      JSON.stringify({
        type: "message.new",
        payload: {
          id: "m-location",
          room_id: "room-1",
          sender_id: "user-1",
          content: sent.payload.content,
          type: "location",
          created_at: "2026-06-29T10:00:01Z"
        }
      })
    ].join("\n")
  );

  const resolved = await promise;
  assert.equal(resolved.id, "m-location");
  assert.equal(resolved.location?.name, "Cairo");
  provider.disconnect();
});

test("InstaChatChatProvider sends image/video/file attachments and typing over WebSocket", async () => {
  installFetch(createFetchMock({}));
  const sockets = installWebSocket();
  const provider = new InstaChatChatProvider({ baseUrl: "https://chat.test", token, roomId: "room-1" });

  await provider.sendTyping("room-1", true);
  const socket = sockets[0];
  await socket.waitForOpen();
  await socket.waitForSent(1);
  assert.deepEqual(JSON.parse(socket.sent[0]), { type: "typing.start", payload: { room_id: "room-1" } });

  const sendPromise = provider.sendMessage(
    {
      roomId: "room-1",
      userId: "user-1",
      text: "Video",
      media: {
        id: "att-video",
        url: "file:///clip.mp4",
        type: "video",
        name: "clip.mp4",
        mimeType: "video/mp4"
      },
      createdAt: "2026-06-29T10:00:00Z"
    },
    "room-1"
  );
  await socket.waitForSent(2);
  const sent = JSON.parse(socket.sent[1]);
  assert.equal(sent.payload.type, "file");
  assert.deepEqual(sent.payload.attachment_ids, ["att-video"]);
  socket.receive(JSON.stringify({ type: "message.delivered", payload: { message_id: "m-video", room_id: "room-1" } }));
  assert.equal((await sendPromise).media?.type, "video");
  provider.disconnect();
});

test("InstaChatChatProvider disconnect clears listeners, pending sends, and socket state", async () => {
  installFetch(createFetchMock({}));
  const sockets = installWebSocket();
  const provider = new InstaChatChatProvider({ baseUrl: "https://chat.test", token, roomId: "room-1" });
  let receivedMessages = 0;
  const unsubscribe = provider.subscribeToMessages(() => {
    receivedMessages += 1;
  });

  const sendPromise = provider.sendMessage({
    roomId: "room-1",
    userId: "user-1",
    text: "Pending",
    createdAt: "2026-06-29T10:00:00Z"
  });
  const socket = sockets[0];
  await socket.waitForOpen();
  await socket.waitForSent(1);

  unsubscribe();
  provider.disconnect();
  socket.receive(
    JSON.stringify({
      type: "message.new",
      payload: {
        id: "m-after-disconnect",
        room_id: "room-1",
        sender_id: "agent-1",
        content: "Late",
        type: "text",
        created_at: "2026-06-29T10:00:01Z"
      }
    })
  );

  await assert.rejects(sendPromise, /socket disconnected/i);
  assert.equal(socket.closed, true);
  assert.equal(receivedMessages, 0);
});

test("InstaChatMediaUploadProvider posts multipart media to the selected room without JSON content-type", async () => {
  const fetchMock = createFetchMock({
    "https://chat.test/api/v1/rooms/room-1/attachments": {
      id: "att-image",
      file_name: "photo.png",
      content_type: "image/png",
      type: "image",
      file_size: 42,
      url: "https://files.test/photo.png"
    }
  });
  installFetch(fetchMock);
  installFormData();

  const provider = new InstaChatMediaUploadProvider({ baseUrl: "https://chat.test", token });
  const file: LocalMediaFile = {
    uri: "file:///photo.png",
    type: "image",
    name: "photo.png",
    mimeType: "image/png"
  };
  const uploaded = await provider.upload(file, "room-1");

  assert.equal(uploaded.type, "image");
  assert.equal(fetchMock.calls[0].url, "https://chat.test/api/v1/rooms/room-1/attachments");
  assert.equal(fetchMock.calls[0].init.headers.Authorization, `Bearer ${token}`);
  assert.equal(fetchMock.calls[0].init.headers["Content-Type"], undefined);
});

function createJwt(payload: Record<string, unknown>): string {
  const encodedPayload = Buffer.from(JSON.stringify(payload)).toString("base64url");
  return `header.${encodedPayload}.signature`;
}

function createFetchMock(routes: Record<string, unknown>) {
  const calls: Array<{ url: string; init: any }> = [];
  const fetchMock = async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init });
    if (!(url in routes)) {
      return response({ error: `No route for ${url}` }, 404);
    }
    return response(routes[url], 200);
  };
  return Object.assign(fetchMock, { calls });
}

function installFetch(fetchMock: ReturnType<typeof createFetchMock>) {
  (globalThis as any).fetch = fetchMock;
}

function response(body: unknown, status: number) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body
  } as Response;
}

function installFormData() {
  class TestFormData {
    values: Array<[string, unknown]> = [];
    append(name: string, value: unknown) {
      this.values.push([name, value]);
    }
  }
  (globalThis as any).FormData = TestFormData;
}

function installWebSocket() {
  const sockets: TestWebSocket[] = [];
  class WebSocketMock extends TestWebSocket {
    static OPEN = 1;
    constructor(url: string) {
      super(url);
      sockets.push(this);
    }
  }
  (globalThis as any).WebSocket = WebSocketMock;
  return sockets;
}

class TestWebSocket {
  static OPEN = 1;
  readyState = 0;
  sent: string[] = [];
  closed = false;
  onopen?: () => void;
  onmessage?: (event: { data: string }) => void;
  onerror?: () => void;
  onclose?: () => void;
  private openPromise: Promise<void>;
  private resolveOpen!: () => void;

  constructor(readonly url: string) {
    this.openPromise = new Promise((resolve) => {
      this.resolveOpen = resolve;
    });
    setTimeout(() => {
      this.readyState = TestWebSocket.OPEN;
      this.onopen?.();
      this.resolveOpen();
    }, 0);
  }

  waitForOpen() {
    return this.openPromise;
  }

  waitForSent(count: number) {
    return new Promise<void>((resolve, reject) => {
      const startedAt = Date.now();
      const interval = setInterval(() => {
        if (this.sent.length >= count) {
          clearInterval(interval);
          resolve();
          return;
        }
        if (Date.now() - startedAt > 1000) {
          clearInterval(interval);
          reject(new Error(`Expected ${count} WebSocket sends, received ${this.sent.length}.`));
        }
      }, 5);
    });
  }

  send(value: string) {
    this.sent.push(value);
  }

  receive(data: string) {
    this.onmessage?.({ data });
  }

  close() {
    this.closed = true;
    this.readyState = 3;
    this.onclose?.();
  }
}
