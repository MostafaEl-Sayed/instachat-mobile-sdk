import type { ChatMessage } from "../types/chat";

export interface ChatCacheProvider {
  getRoomMessages(roomId: string): Promise<ChatMessage[]>;
  setRoomMessages(roomId: string, messages: ChatMessage[]): Promise<void>;
  upsertRoomMessages?(roomId: string, messages: ChatMessage[]): Promise<void>;
  clearRoom?(roomId: string): Promise<void>;
}

export interface MemoryChatCacheProviderOptions {
  maxMessagesPerRoom?: number;
}

export class MemoryChatCacheProvider implements ChatCacheProvider {
  private readonly rooms = new Map<string, ChatMessage[]>();
  private readonly maxMessagesPerRoom: number;

  constructor(options: MemoryChatCacheProviderOptions = {}) {
    this.maxMessagesPerRoom = options.maxMessagesPerRoom ?? 150;
  }

  async getRoomMessages(roomId: string): Promise<ChatMessage[]> {
    return [...(this.rooms.get(roomId) ?? [])];
  }

  async setRoomMessages(roomId: string, messages: ChatMessage[]): Promise<void> {
    this.rooms.set(roomId, normalizeMessages(messages, this.maxMessagesPerRoom));
  }

  async upsertRoomMessages(roomId: string, messages: ChatMessage[]): Promise<void> {
    const current = this.rooms.get(roomId) ?? [];
    this.rooms.set(roomId, normalizeMessages([...current, ...messages], this.maxMessagesPerRoom));
  }

  async clearRoom(roomId: string): Promise<void> {
    this.rooms.delete(roomId);
  }
}

export const defaultChatCacheProvider = new MemoryChatCacheProvider();

function normalizeMessages(messages: ChatMessage[], maxMessages: number): ChatMessage[] {
  const byId = new Map<string, ChatMessage>();
  messages.forEach((message) => {
    byId.set(message.id, { ...byId.get(message.id), ...message });
  });

  const sorted = Array.from(byId.values()).sort((left, right) => new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime());
  if (sorted.length <= maxMessages) {
    return sorted;
  }

  return sorted.slice(sorted.length - maxMessages);
}
