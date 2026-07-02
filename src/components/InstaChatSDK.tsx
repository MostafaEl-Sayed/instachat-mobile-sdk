import React, { useMemo } from "react";
import { createInstaChatSDKConfig } from "../providers/InstaChatProvider";
import type { CreateInstaChatSDKConfigOptions } from "../providers/InstaChatProvider";
import type { ChatUser } from "../types/user";
import { ChatSDK } from "./ChatSDK";
import type { ChatSDKProps } from "./ChatSDK";

export interface InstaChatSDKProps extends CreateInstaChatSDKConfigOptions {
  user: ChatUser;
  theme?: ChatSDKProps["theme"];
  onSendMessage?: ChatSDKProps["onSendMessage"];
  onUploadMedia?: ChatSDKProps["onUploadMedia"];
}

export function InstaChatSDK({
  baseUrl,
  token,
  roomId,
  historyLimit,
  mediaPickerProvider,
  locationProvider,
  headerTitle,
  placeholderText,
  keyboardAvoidingEnabled,
  messagePageSize,
  cacheProvider,
  cacheLimitPerRoom,
  user,
  theme,
  onSendMessage,
  onUploadMedia
}: InstaChatSDKProps) {
  const config = useMemo(
    () =>
      createInstaChatSDKConfig({
        baseUrl,
        token,
        roomId,
        historyLimit,
        mediaPickerProvider,
        locationProvider,
        headerTitle,
        placeholderText,
        keyboardAvoidingEnabled,
        messagePageSize,
        cacheProvider,
        cacheLimitPerRoom
      }),
    [
      baseUrl,
      cacheLimitPerRoom,
      cacheProvider,
      headerTitle,
      historyLimit,
      keyboardAvoidingEnabled,
      locationProvider,
      mediaPickerProvider,
      messagePageSize,
      placeholderText,
      roomId,
      token
    ]
  );

  return (
    <ChatSDK
      config={config}
      user={user}
      theme={theme}
      onSendMessage={onSendMessage}
      onUploadMedia={onUploadMedia}
    />
  );
}
