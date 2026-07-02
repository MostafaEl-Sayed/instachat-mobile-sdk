import type { ChatTheme, ResolvedChatTheme } from "../types/theme";

export const defaultTheme: ResolvedChatTheme = {
  primaryColor: "#0E2544",
  backgroundColor: "#FFFFFF",
  userBubbleColor: "#0E2544",
  assistantBubbleColor: "#F4F6F8",
  textColor: "#111827",
  mutedTextColor: "#6B7280",
  inputBackgroundColor: "#F9FAFB",
  borderColor: "#E5E7EB",
  errorColor: "#B42318",
  placeholderText: "Type a message",
  headerTitle: "Chat",
  showMicrophoneButton: true,
  showMediaUploadButton: true,
  showLocationButton: true,
  borderRadius: 18
};

export function resolveTheme(theme?: ChatTheme, configText?: Pick<ChatTheme, "placeholderText" | "headerTitle">): ResolvedChatTheme {
  return {
    ...defaultTheme,
    ...configText,
    ...theme
  };
}
