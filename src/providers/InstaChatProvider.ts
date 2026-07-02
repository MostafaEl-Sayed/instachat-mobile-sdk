import type { ChatMessage, OutgoingMessage } from "../types/chat";
import type { ChatLocation } from "../types/location";
import type { LocalMediaFile, UploadedMedia } from "../types/media";
import type { ChatRoom, ChatRoomMember } from "../types/room";
import type { ChatCacheProvider } from "./ChatCacheProvider";
import type {
  ChatMessagesPage,
  ChatMessagesPageRequest,
  ChatProvider,
  ChatProviderMessageEvent,
  ChatProviderTypingEvent
} from "./ChatProvider";
import type { MediaUploadProvider } from "./MediaUploadProvider";

export interface InstaChatProviderConfig {
  baseUrl: string;
  token: string;
  roomId?: string;
  historyLimit?: number;
}

export interface CreateInstaChatSDKConfigOptions extends InstaChatProviderConfig {
  mediaPickerProvider?: import("./MediaUploadProvider").MediaPickerProvider;
  locationProvider?: import("./LocationProvider").LocationProvider;
  headerTitle?: string;
  placeholderText?: string;
  keyboardAvoidingEnabled?: boolean;
  messagePageSize?: number;
  cacheProvider?: ChatCacheProvider;
  cacheLimitPerRoom?: number;
}

interface InstaChatRoom {
  id: string;
  app_id?: string;
  type?: "direct" | "group";
  metadata?: Record<string, unknown>;
  created_at?: string;
  role?: "member" | "admin";
  joined_at?: string;
  members?: InstaChatRoomMember[];
}

interface InstaChatRoomMember {
  id: string;
  ext_user_id?: string;
  display_name: string;
  avatar_url?: string;
  is_online?: boolean;
  last_seen?: string;
  role?: "member" | "admin";
  joined_at?: string;
}

interface InstaChatAttachment {
  id: string;
  file_name: string;
  content_type: string;
  type?: "image" | "audio" | "video" | "file";
  file_size?: number;
  url: string;
}

interface InstaChatMessage {
  id: string;
  room_id: string;
  sender_id: string;
  content: string;
  type: "text" | "image" | "file" | "location";
  is_deleted?: boolean;
  created_at: string;
  attachments?: InstaChatAttachment[];
}

interface InstaChatMessagesResponse {
  data: InstaChatMessage[];
  next_cursor: string | null;
}

interface Envelope {
  type: string;
  payload: any;
}

interface DeliveredPayload {
  message_id?: string;
  room_id?: string;
}

interface TypingPayload {
  room_id?: string;
  user_id?: string;
  is_typing?: boolean;
}

interface PendingSend {
  roomId: string;
  content: string;
  outgoing: OutgoingMessage;
  attachmentIds: string[];
  resolve: (message: ChatMessage) => void;
  reject: (error: Error) => void;
  timeout: ReturnType<typeof setTimeout>;
}

export class InstaChatChatProvider implements ChatProvider {
  private readonly config: Required<Pick<InstaChatProviderConfig, "historyLimit">> & InstaChatProviderConfig;
  private ws: WebSocket | null = null;
  private connecting: Promise<void> | null = null;
  private connectingReject: ((error: Error) => void) | null = null;
  private socketConnectTimeout: ReturnType<typeof setTimeout> | null = null;
  private roomIdPromise: Promise<string> | null = null;
  private readonly currentUserId: string | undefined;
  private pending: PendingSend[] = [];
  private messageListeners = new Set<(event: ChatProviderMessageEvent) => void>();
  private typingListeners = new Set<(event: ChatProviderTypingEvent) => void>();

  constructor(config: InstaChatProviderConfig) {
    this.config = {
      historyLimit: 50,
      ...config,
      baseUrl: normalizeBaseUrl(config.baseUrl)
    };
    this.currentUserId = decodeJwtPayload(config.token)?.sub;
  }

  async getRooms(): Promise<ChatRoom[]> {
    const rooms = await this.fetchRooms();
    this.ensureSocket().catch(() => undefined);
    return rooms.map((room) => mapRoom(room, this.currentUserId));
  }

  async getMessages(roomId?: string): Promise<ChatMessage[]> {
    return (await this.getMessagesPage({ roomId, limit: this.config.historyLimit })).messages;
  }

  async getMessagesPage(request: ChatMessagesPageRequest): Promise<ChatMessagesPage> {
    const resolvedRoomId = request.roomId ?? (await this.ensureRoomId());
    const params = new URLSearchParams({ limit: String(request.limit ?? this.config.historyLimit) });
    if (request.cursor) {
      params.set("cursor", request.cursor);
    }
    const response = await fetch(`${this.config.baseUrl}/api/v1/rooms/${resolvedRoomId}/messages?${params.toString()}`, {
      method: "GET",
      headers: this.jsonHeaders()
    });

    if (!response.ok) {
      throw new Error(`Failed to fetch messages: ${response.status}`);
    }

    const body = await parseJsonResponse<InstaChatMessagesResponse>(response, "messages");
    const messages = body.data
      .filter((message) => !message.is_deleted)
      .map((message) => mapBackendMessage(message, this.currentUserId))
      .sort((left, right) => new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime());

    return {
      messages,
      nextCursor: body.next_cursor,
      hasMore: Boolean(body.next_cursor)
    };
  }

  async sendMessage(message: OutgoingMessage, roomId?: string): Promise<ChatMessage> {
    const resolvedRoomId = roomId ?? message.roomId ?? (await this.ensureRoomId());
    await this.ensureSocket();

    const attachmentIds = message.media?.id ? [message.media.id] : [];
    const content = resolveMessageContent(message);
    const envelope = {
      type: "message.send",
      payload: {
        room_id: resolvedRoomId,
        content,
        type: resolveMessageType(message),
        attachment_ids: attachmentIds
      }
    };

    return new Promise<ChatMessage>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending = this.pending.filter((pending) => pending !== pendingSend);
        reject(new Error("Timed out waiting for InstaChat message confirmation."));
      }, 12000);
      const pendingSend: PendingSend = {
        roomId: resolvedRoomId,
        content,
        outgoing: { ...message, roomId: resolvedRoomId },
        attachmentIds,
        resolve,
        reject,
        timeout
      };
      this.pending.push(pendingSend);

      try {
        this.ws?.send(JSON.stringify(envelope));
      } catch (error) {
        clearTimeout(timeout);
        this.pending = this.pending.filter((pending) => pending !== pendingSend);
        reject(error instanceof Error ? error : new Error("Failed to send WebSocket message."));
      }
    });
  }

  async sendTyping(roomId: string, isTyping: boolean): Promise<void> {
    await this.ensureSocket();
    this.ws?.send(
      JSON.stringify({
        type: isTyping ? "typing.start" : "typing.stop",
        payload: {
          room_id: roomId
        }
      })
    );
  }

  subscribeToMessages(listener: (event: ChatProviderMessageEvent) => void) {
    this.messageListeners.add(listener);
    this.ensureSocket().catch(() => undefined);
    return () => {
      this.messageListeners.delete(listener);
    };
  }

  subscribeToTyping(listener: (event: ChatProviderTypingEvent) => void) {
    this.typingListeners.add(listener);
    this.ensureSocket().catch(() => undefined);
    return () => {
      this.typingListeners.delete(listener);
    };
  }

  disconnect(): void {
    this.pending.forEach((pending) => {
      clearTimeout(pending.timeout);
      pending.reject(new Error("InstaChat socket disconnected."));
    });
    this.pending = [];
    this.messageListeners.clear();
    this.typingListeners.clear();
    if (this.socketConnectTimeout) {
      clearTimeout(this.socketConnectTimeout);
      this.socketConnectTimeout = null;
    }
    this.connectingReject?.(new Error("InstaChat socket disconnected."));
    this.connectingReject = null;
    if (this.ws) {
      this.ws.onopen = null;
      this.ws.onmessage = null;
      this.ws.onerror = null;
      this.ws.onclose = null;
    }
    this.ws?.close();
    this.ws = null;
    this.connecting = null;
  }

  private async ensureRoomId(): Promise<string> {
    if (this.config.roomId) {
      return this.config.roomId;
    }

    if (!this.roomIdPromise) {
      this.roomIdPromise = this.fetchFirstRoomId();
    }

    return this.roomIdPromise;
  }

  private async fetchFirstRoomId(): Promise<string> {
    const rooms = await this.fetchRooms();
    const room = rooms[0];
    if (!room) {
      throw new Error("No InstaChat rooms are available for this user.");
    }

    return room.id;
  }

  private async fetchRooms(): Promise<InstaChatRoom[]> {
    const response = await fetch(`${this.config.baseUrl}/api/v1/me/rooms`, {
      method: "GET",
      headers: this.jsonHeaders()
    });

    if (!response.ok) {
      throw new Error(`Failed to fetch rooms: ${response.status}`);
    }

    return parseJsonResponse<InstaChatRoom[]>(response, "rooms");
  }

  private async ensureSocket(): Promise<void> {
    if (this.ws?.readyState === WebSocket.OPEN) {
      return;
    }

    if (this.connecting) {
      return this.connecting;
    }

    this.connecting = new Promise<void>((resolve, reject) => {
      this.connectingReject = reject;
      const ws = new WebSocket(`${toWsBaseUrl(this.config.baseUrl)}/ws?token=${encodeURIComponent(this.config.token)}`);
      this.socketConnectTimeout = setTimeout(() => {
        this.socketConnectTimeout = null;
        this.connectingReject = null;
        this.connecting = null;
        reject(new Error("Timed out connecting to InstaChat WebSocket."));
        ws.close();
      }, 12000);

      ws.onopen = () => {
        if (this.socketConnectTimeout) {
          clearTimeout(this.socketConnectTimeout);
          this.socketConnectTimeout = null;
        }
        this.connectingReject = null;
        this.ws = ws;
        this.connecting = null;
        resolve();
      };

      ws.onmessage = (event) => {
        parseEnvelopes(event.data).forEach((envelope) => {
          try {
            this.handleEnvelope(envelope);
          } catch {
            // Keep malformed or unexpected realtime events from crashing the host app.
          }
        });
      };

      ws.onerror = () => {
        if (this.socketConnectTimeout) {
          clearTimeout(this.socketConnectTimeout);
          this.socketConnectTimeout = null;
        }
        this.connectingReject = null;
        this.connecting = null;
        reject(new Error("InstaChat WebSocket connection failed."));
      };

      ws.onclose = () => {
        if (this.socketConnectTimeout) {
          clearTimeout(this.socketConnectTimeout);
          this.socketConnectTimeout = null;
        }
        this.connectingReject = null;
        this.ws = null;
        this.connecting = null;
      };
    });

    return this.connecting;
  }

  private handleEnvelope(envelope: Envelope) {
    if (envelope.type === "message.new") {
      const message = mapBackendMessage(envelope.payload as InstaChatMessage, this.currentUserId);
      const match = this.pending.find((pending) => matchesPending(message, pending));
      if (match) {
        clearTimeout(match.timeout);
        this.pending = this.pending.filter((pending) => pending !== match);
        match.resolve(message);
      }
      if (message.roomId) {
        this.emitMessage({ roomId: message.roomId, message });
      }
      return;
    }

    if (envelope.type === "message.delivered") {
      const payload = envelope.payload as DeliveredPayload;
      const match = this.pending.find((pending) => pending.roomId === payload.room_id);
      if (match) {
        clearTimeout(match.timeout);
        this.pending = this.pending.filter((pending) => pending !== match);
        match.resolve(mapDeliveredMessage(payload, match, this.currentUserId));
      }
      return;
    }

    if (envelope.type === "typing") {
      const payload = envelope.payload as TypingPayload;
      if (payload.room_id && payload.user_id) {
        this.emitTyping({
          roomId: payload.room_id,
          userId: payload.user_id,
          isTyping: Boolean(payload.is_typing)
        });
      }
      return;
    }

    if (envelope.type === "error") {
      const error = new Error(envelope.payload?.message ?? "InstaChat server error.");
      this.pending.forEach((pending) => {
        clearTimeout(pending.timeout);
        pending.reject(error);
      });
      this.pending = [];
    }
  }

  private emitMessage(event: ChatProviderMessageEvent) {
    this.messageListeners.forEach((listener) => listener(event));
  }

  private emitTyping(event: ChatProviderTypingEvent) {
    this.typingListeners.forEach((listener) => listener(event));
  }

  private jsonHeaders(): HeadersInit {
    return {
      Authorization: `Bearer ${this.config.token}`,
      "Content-Type": "application/json"
    };
  }
}

export class InstaChatMediaUploadProvider implements MediaUploadProvider {
  private readonly config: InstaChatProviderConfig;
  private roomIdPromise: Promise<string> | null = null;

  constructor(config: InstaChatProviderConfig) {
    this.config = {
      ...config,
      baseUrl: normalizeBaseUrl(config.baseUrl)
    };
  }

  async upload(file: LocalMediaFile, roomId?: string): Promise<UploadedMedia> {
    const resolvedRoomId = roomId ?? (await this.ensureRoomId());
    const formData = new FormData();
    formData.append("file", {
      uri: file.uri,
      name: file.name ?? `upload.${extensionFor(file)}`,
      type: file.mimeType ?? mimeTypeFor(file)
    } as any);

    const response = await fetch(`${this.config.baseUrl}/api/v1/rooms/${resolvedRoomId}/attachments`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.config.token}`
      },
      body: formData
    });

    if (!response.ok) {
      throw new Error(`Upload failed: ${response.status}`);
    }

    const attachment = await parseJsonResponse<InstaChatAttachment>(response, "attachment");
    return mapAttachment(attachment);
  }

  private async ensureRoomId(): Promise<string> {
    if (this.config.roomId) {
      return this.config.roomId;
    }

    if (!this.roomIdPromise) {
      this.roomIdPromise = fetchFirstRoomId(this.config);
    }

    return this.roomIdPromise;
  }
}

export function createInstaChatSDKConfig({
  mediaPickerProvider,
  locationProvider,
  headerTitle,
  placeholderText,
  keyboardAvoidingEnabled,
  messagePageSize,
  cacheProvider,
  cacheLimitPerRoom,
  ...providerConfig
}: CreateInstaChatSDKConfigOptions): import("../components/ChatSDK").ChatSDKConfig {
  return {
    chatProvider: new InstaChatChatProvider(providerConfig),
    mediaUploadProvider: new InstaChatMediaUploadProvider(providerConfig),
    mediaPickerProvider,
    locationProvider,
    headerTitle,
    placeholderText,
    keyboardAvoidingEnabled,
    messagePageSize: messagePageSize ?? providerConfig.historyLimit,
    cacheProvider,
    cacheLimitPerRoom
  };
}

function mapBackendMessage(message: InstaChatMessage, currentUserId?: string): ChatMessage {
  const media = message.attachments?.[0] ? mapAttachment(message.attachments[0]) : undefined;
  const location = message.type === "location" ? parseLocationContent(message.content) : undefined;

  return {
    id: message.id,
    roomId: message.room_id,
    role: message.sender_id === currentUserId ? "user" : "assistant",
    text: location ? undefined : message.content || undefined,
    media,
    location,
    createdAt: message.created_at,
    status: "sent",
    userId: message.sender_id
  };
}

function mapDeliveredMessage(payload: DeliveredPayload, pending: PendingSend, currentUserId?: string): ChatMessage {
  return {
    id: payload.message_id ?? `instachat-${Date.now()}`,
    roomId: pending.roomId,
    role: "user",
    text: pending.outgoing.location ? undefined : pending.content || undefined,
    media: pending.outgoing.media,
    location: pending.outgoing.location,
    createdAt: pending.outgoing.createdAt ?? new Date().toISOString(),
    status: "sent",
    userId: currentUserId ?? pending.outgoing.userId
  };
}

function mapRoom(room: InstaChatRoom, currentUserId?: string): ChatRoom {
  const members = room.members?.map(mapRoomMember) ?? [];
  const otherMembers = members.filter((member) => member.id !== currentUserId);
  const primaryMember = otherMembers[0] ?? members[0];
  const groupTitle = otherMembers.map((member) => member.displayName).filter(Boolean).join(", ");
  const metadataTitle = typeof room.metadata?.title === "string" ? room.metadata.title : undefined;

  return {
    id: room.id,
    title: metadataTitle ?? (room.type === "group" ? groupTitle || "Group chat" : primaryMember?.displayName ?? "Chat"),
    subtitle: room.type === "group" ? `${members.length} members` : primaryMember?.isOnline ? "Online" : "Direct message",
    avatarUrl: primaryMember?.avatarUrl,
    type: room.type,
    members,
    metadata: room.metadata,
    lastMessageAt: room.created_at
  };
}

function mapRoomMember(member: InstaChatRoomMember): ChatRoomMember {
  return {
    id: member.id,
    externalUserId: member.ext_user_id,
    displayName: member.display_name,
    avatarUrl: member.avatar_url,
    isOnline: member.is_online,
    lastSeen: member.last_seen,
    role: member.role
  };
}

function mapAttachment(attachment: InstaChatAttachment): UploadedMedia {
  return {
    id: attachment.id,
    url: attachment.url,
    type: resolveAttachmentKind(attachment),
    name: attachment.file_name,
    mimeType: attachment.content_type,
    size: attachment.file_size,
    metadata: {
      attachmentId: attachment.id,
      backendType: attachment.type
    }
  };
}

function resolveAttachmentKind(attachment: InstaChatAttachment): UploadedMedia["type"] {
  if (attachment.type === "image" || attachment.type === "audio" || attachment.type === "video") {
    return attachment.type;
  }

  if (attachment.content_type.startsWith("image/")) {
    return "image";
  }

  if (attachment.content_type.startsWith("audio/")) {
    return "audio";
  }

  return "video";
}

async function fetchFirstRoomId(config: InstaChatProviderConfig): Promise<string> {
  const response = await fetch(`${normalizeBaseUrl(config.baseUrl)}/api/v1/me/rooms`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${config.token}`,
      "Content-Type": "application/json"
    }
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch rooms: ${response.status}`);
  }

  const rooms = await parseJsonResponse<InstaChatRoom[]>(response, "rooms");
  const room = rooms[0];
  if (!room) {
    throw new Error("No InstaChat rooms are available for this user.");
  }

  return room.id;
}

function resolveMessageType(message: OutgoingMessage): "text" | "image" | "file" | "location" {
  if (message.location) {
    return "location";
  }

  if (message.media?.type === "image") {
    return "image";
  }

  if (message.media) {
    return "file";
  }

  return "text";
}

function resolveMessageContent(message: OutgoingMessage): string {
  if (message.location) {
    return formatLocationContent(message.location);
  }

  return message.text?.trim() ?? "";
}

function matchesPending(message: ChatMessage, pending: PendingSend): boolean {
  const sameContent = (message.text ?? "") === pending.content;
  const sameAttachment = pending.attachmentIds.length === 0 || (message.media?.id ? pending.attachmentIds.includes(message.media.id) : false);
  return sameContent && sameAttachment;
}

function formatLocationContent(location: ChatLocation): string {
  return JSON.stringify({
    latitude: location.latitude,
    longitude: location.longitude,
    name: location.name ?? location.address
  });
}

function parseLocationContent(content: string): ChatLocation | undefined {
  try {
    const parsed = JSON.parse(content) as Partial<ChatLocation>;
    if (typeof parsed.latitude !== "number" || typeof parsed.longitude !== "number") {
      return undefined;
    }

    return {
      latitude: parsed.latitude,
      longitude: parsed.longitude,
      name: typeof parsed.name === "string" ? parsed.name : "Shared location",
      mapUrl: `https://maps.apple.com/?ll=${parsed.latitude},${parsed.longitude}`,
      timestamp: new Date().toISOString()
    };
  } catch {
    return undefined;
  }
}

async function parseJsonResponse<T>(response: Response, label: string): Promise<T> {
  try {
    return (await response.json()) as T;
  } catch {
    throw new Error(`Failed to parse InstaChat ${label} response.`);
  }
}

function parseEnvelopes(data: unknown): Envelope[] {
  if (typeof data === "string") {
    const trimmed = data.trim();
    if (!trimmed || (!trimmed.startsWith("{") && !trimmed.startsWith("["))) {
      return [];
    }

    const parsed = parseEnvelopeString(trimmed);
    if (parsed.length > 0) {
      return parsed;
    }

    return trimmed.split(/\r?\n/).flatMap((line) => parseEnvelopeString(line.trim()));
  }

  if (typeof data === "object" && data !== null && isEnvelope(data)) {
    return [data];
  }

  return [];
}

function parseEnvelopeString(value: string): Envelope[] {
  if (!value) {
    return [];
  }

  try {
    const parsed = JSON.parse(value) as Partial<Envelope> | Partial<Envelope>[];
    if (Array.isArray(parsed)) {
      return parsed.filter(isEnvelope);
    }

    return isEnvelope(parsed) ? [parsed] : [];
  } catch {
    return [];
  }
}

function isEnvelope(value: unknown): value is Envelope {
  return typeof value === "object" && value !== null && typeof (value as Envelope).type === "string";
}

function decodeJwtPayload(token: string): { sub?: string } | undefined {
  try {
    const [, payload] = token.split(".");
    if (!payload) {
      return undefined;
    }
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    return JSON.parse(atob(padded)) as { sub?: string };
  } catch {
    return undefined;
  }
}

function normalizeBaseUrl(baseUrl: string): string {
  return baseUrl.replace(/\/+$/, "");
}

function toWsBaseUrl(baseUrl: string): string {
  const normalized = normalizeBaseUrl(baseUrl);
  if (normalized.startsWith("https://")) {
    return normalized.replace("https://", "wss://");
  }
  if (normalized.startsWith("http://")) {
    return normalized.replace("http://", "ws://");
  }
  return `wss://${normalized}`;
}

function mimeTypeFor(file: LocalMediaFile): string {
  if (file.mimeType) {
    return file.mimeType;
  }
  if (file.type === "image") {
    return "image/jpeg";
  }
  if (file.type === "audio") {
    return "audio/m4a";
  }
  return "video/mp4";
}

function extensionFor(file: LocalMediaFile): string {
  if (file.type === "image") {
    return "jpg";
  }
  if (file.type === "audio") {
    return "m4a";
  }
  return "mp4";
}
