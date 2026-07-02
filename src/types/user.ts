export interface ChatUser {
  id: string;
  name: string;
  avatarUrl?: string;
  metadata?: Record<string, unknown>;
}
