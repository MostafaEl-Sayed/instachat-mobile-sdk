import type { ChatMessage, OutgoingMessage } from "../types/chat";
import type { ChatRoom } from "../types/room";

export interface ChatProviderMessageEvent {
  roomId: string;
  message: ChatMessage;
}

export interface ChatProviderTypingEvent {
  roomId: string;
  userId: string;
  isTyping: boolean;
}

export type ChatProviderUnsubscribe = () => void;

export interface ChatMessagesPage {
  messages: ChatMessage[];
  nextCursor?: string | null;
  hasMore: boolean;
}

export interface ChatMessagesPageRequest {
  roomId?: string;
  limit?: number;
  cursor?: string | null;
}

export interface ChatProvider {
  getRooms?(): Promise<ChatRoom[]>;
  getMessages(roomId?: string): Promise<ChatMessage[]>;
  getMessagesPage?(request: ChatMessagesPageRequest): Promise<ChatMessagesPage>;
  sendMessage(message: OutgoingMessage, roomId?: string): Promise<ChatMessage>;
  sendTyping?(roomId: string, isTyping: boolean): Promise<void> | void;
  subscribeToMessages?(listener: (event: ChatProviderMessageEvent) => void): ChatProviderUnsubscribe;
  subscribeToTyping?(listener: (event: ChatProviderTypingEvent) => void): ChatProviderUnsubscribe;
  disconnect?(): void;
}
