export interface ChatRoomMember {
  id: string;
  externalUserId?: string;
  displayName: string;
  avatarUrl?: string;
  isOnline?: boolean;
  lastSeen?: string;
  role?: "member" | "admin" | string;
}

export interface ChatRoom {
  id: string;
  title: string;
  subtitle?: string;
  avatarUrl?: string;
  type?: "direct" | "group" | string;
  members?: ChatRoomMember[];
  lastMessageText?: string;
  lastMessageAt?: string;
  unread?: boolean;
  metadata?: Record<string, unknown>;
}
