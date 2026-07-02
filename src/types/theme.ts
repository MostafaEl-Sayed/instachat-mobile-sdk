import type { ReactNode } from "react";
import type { ImageSourcePropType } from "react-native";

export interface ChatTheme {
  primaryColor?: string;
  backgroundColor?: string;
  userBubbleColor?: string;
  assistantBubbleColor?: string;
  textColor?: string;
  mutedTextColor?: string;
  inputBackgroundColor?: string;
  borderColor?: string;
  errorColor?: string;
  placeholderText?: string;
  headerTitle?: string;
  avatar?: ImageSourcePropType | string;
  assistantAvatar?: ImageSourcePropType | string;
  sendButtonIcon?: ReactNode;
  showMicrophoneButton?: boolean;
  showMediaUploadButton?: boolean;
  showLocationButton?: boolean;
  borderRadius?: number;
  fontFamily?: string;
}

export type ResolvedChatTheme = Required<
  Pick<
    ChatTheme,
    | "primaryColor"
    | "backgroundColor"
    | "userBubbleColor"
    | "assistantBubbleColor"
    | "textColor"
    | "mutedTextColor"
    | "inputBackgroundColor"
    | "borderColor"
    | "errorColor"
    | "placeholderText"
    | "headerTitle"
    | "showMicrophoneButton"
    | "showMediaUploadButton"
    | "showLocationButton"
    | "borderRadius"
  >
> &
  Pick<ChatTheme, "avatar" | "assistantAvatar" | "sendButtonIcon" | "fontFamily">;
