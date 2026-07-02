import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { FlashList } from "@shopify/flash-list";
import {
  ActivityIndicator,
  FlatList,
  InteractionManager,
  Keyboard,
  Platform,
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  View
} from "react-native";
import type { ChatProvider } from "../providers/ChatProvider";
import type { ChatMessagesPage } from "../providers/ChatProvider";
import type { ChatCacheProvider } from "../providers/ChatCacheProvider";
import { defaultChatCacheProvider } from "../providers/ChatCacheProvider";
import type { LocationProvider } from "../providers/LocationProvider";
import type { MediaPickerProvider, MediaUploadProvider } from "../providers/MediaUploadProvider";
import type { SpeechToTextProvider } from "../providers/SpeechToTextProvider";
import type { ChatMessage, ChatSessionConfig, OutgoingMessage } from "../types/chat";
import type { ChatLocation } from "../types/location";
import type { LocalMediaFile, MediaKind } from "../types/media";
import type { ChatRoom } from "../types/room";
import type { ChatTheme } from "../types/theme";
import type { ChatUser } from "../types/user";
import { resolveTheme } from "../utils/theme";
import { ChatInput } from "./ChatInput";
import { LocationPreview } from "./LocationPreview";
import { MediaPreview } from "./MediaPreview";
import { MessageBubble } from "./MessageBubble";
import { TypingIndicator } from "./TypingIndicator";

export interface ChatSDKConfig {
  chatProvider: ChatProvider;
  speechToTextProvider?: SpeechToTextProvider;
  mediaUploadProvider?: MediaUploadProvider;
  mediaPickerProvider?: MediaPickerProvider;
  locationProvider?: LocationProvider;
  session?: ChatSessionConfig;
  placeholderText?: string;
  headerTitle?: string;
  keyboardAvoidingEnabled?: boolean;
  messagePageSize?: number;
  cacheProvider?: ChatCacheProvider;
  cacheLimitPerRoom?: number;
}

export interface ChatSDKProps {
  config: ChatSDKConfig;
  user: ChatUser;
  theme?: ChatTheme;
  onSendMessage?: (message: OutgoingMessage) => void | Promise<void>;
  onUploadMedia?: (file: LocalMediaFile) => void | Promise<void>;
}

export function ChatSDK({ config, user, theme, onSendMessage, onUploadMedia }: ChatSDKProps) {
  const resolvedTheme = useMemo(
    () => resolveTheme(theme, { placeholderText: config.placeholderText, headerTitle: config.headerTitle }),
    [theme, config.placeholderText, config.headerTitle]
  );
  const messageListRef = useRef<FlashList<ChatMessage>>(null);
  const activeRoomRef = useRef<ChatRoom | null>(null);
  const typingStopTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const sentTypingStartRef = useRef(false);
  const inputRef = useRef("");
  const pendingInitialScrollRef = useRef(false);
  const settleInitialScrollUntilRef = useRef(0);
  const hasRoomList = Boolean(config.chatProvider.getRooms);
  const keyboardAvoidingEnabled = config.keyboardAvoidingEnabled ?? true;
  const messagePageSize = config.messagePageSize ?? 25;
  const cacheProvider = config.cacheProvider ?? defaultChatCacheProvider;
  const cacheLimitPerRoom = config.cacheLimitPerRoom ?? 150;
  const defaultRoom = useMemo<ChatRoom>(
    () => ({
      id: config.session?.sessionId ?? "default-room",
      title: resolvedTheme.headerTitle,
      subtitle: user.name
    }),
    [config.session?.sessionId, resolvedTheme.headerTitle, user.name]
  );
  const [rooms, setRooms] = useState<ChatRoom[]>([]);
  const [activeRoom, setActiveRoom] = useState<ChatRoom | null>(hasRoomList ? null : defaultRoom);
  const [loadingRooms, setLoadingRooms] = useState(hasRoomList);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [composerResetToken, setComposerResetToken] = useState(0);
  const [selectedMedia, setSelectedMedia] = useState<LocalMediaFile | null>(null);
  const [selectedLocation, setSelectedLocation] = useState<ChatLocation | null>(null);
  const [loading, setLoading] = useState(!hasRoomList);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [hasMoreMessages, setHasMoreMessages] = useState(false);
  const [sending, setSending] = useState(false);
  const [typing, setTyping] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [deferMedia, setDeferMedia] = useState(false);
  const messageLoadSequenceRef = useRef(0);
  const scrollIdleTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const scrollToBottom = useCallback((animated = true) => {
    requestAnimationFrame(() => messageListRef.current?.scrollToOffset({ offset: 0, animated }));
  }, []);

  const renderMessage = useCallback(
    ({ item }: { item: ChatMessage }) => <MessageBubble deferMedia={deferMedia} message={item} theme={resolvedTheme} />,
    [deferMedia, resolvedTheme]
  );

  const keyExtractor = useCallback((item: ChatMessage) => item.id, []);
  const displayedMessages = useMemo(() => [...messages].reverse(), [messages]);

  useEffect(() => {
    activeRoomRef.current = activeRoom;
  }, [activeRoom]);

  useEffect(() => {
    let mounted = true;

    async function loadRooms() {
      if (!config.chatProvider.getRooms) {
        setActiveRoom(defaultRoom);
        setLoadingRooms(false);
        return;
      }

      setLoadingRooms(true);
      setError(null);
      try {
        const loadedRooms = await config.chatProvider.getRooms();
        if (mounted) {
          setRooms(loadedRooms);
        }
      } catch (loadError) {
        if (mounted) {
          setError(toErrorMessage(loadError, "Could not load chats."));
        }
      } finally {
        if (mounted) {
          setLoadingRooms(false);
        }
      }
    }

    loadRooms();
    return () => {
      mounted = false;
    };
  }, [config.chatProvider, defaultRoom]);

  useEffect(() => {
    let mounted = true;
    const sequence = ++messageLoadSequenceRef.current;

    async function loadMessages() {
      if (!activeRoom) {
        setMessages([]);
        setNextCursor(null);
        setHasMoreMessages(false);
        setLoading(false);
        return;
      }

      setError(null);
      setLoading(true);
      try {
        const cached = await cacheProvider.getRoomMessages(activeRoom.id);
        if (!mounted || sequence !== messageLoadSequenceRef.current) {
          return;
        }

        if (cached.length > 0) {
          pendingInitialScrollRef.current = true;
          settleInitialScrollUntilRef.current = Date.now() + 350;
          setMessages(cached);
          setLoading(false);
        }

        await waitForInteractions();
        if (!mounted || sequence !== messageLoadSequenceRef.current) {
          return;
        }

        const page = await loadMessagePage(config.chatProvider, activeRoom.id, null, messagePageSize);
        if (mounted && sequence === messageLoadSequenceRef.current) {
          const loaded = trimCachedMessages(mergeMessages(cached, page.messages), cacheLimitPerRoom);
          pendingInitialScrollRef.current = loaded.length > 0;
          settleInitialScrollUntilRef.current = Date.now() + (cached.length > 0 ? 350 : 900);
          setMessages(loaded);
          setNextCursor(page.nextCursor ?? null);
          setHasMoreMessages(page.hasMore);
          cacheMessages(cacheProvider, activeRoom.id, loaded);
          const latestMessage = loaded[loaded.length - 1];
          if (latestMessage) {
            updateRoomPreview(activeRoom.id, latestMessage);
          }
        }
      } catch (loadError) {
        if (mounted) {
          setError(toErrorMessage(loadError, "Could not load chat messages."));
        }
      } finally {
        if (mounted) {
          setLoading(false);
        }
      }
    }

    loadMessages();
    return () => {
      mounted = false;
    };
  }, [activeRoom, cacheLimitPerRoom, cacheProvider, config.chatProvider, messagePageSize]);

  useEffect(() => {
    return () => {
      stopTyping();
      if (scrollIdleTimeoutRef.current) {
        clearTimeout(scrollIdleTimeoutRef.current);
      }
      config.chatProvider.disconnect?.();
    };
  }, [config.chatProvider]);

  useEffect(() => {
    const unsubscribeMessages = config.chatProvider.subscribeToMessages?.((event) => {
      updateRoomPreview(event.roomId, event.message);

      const currentRoom = activeRoomRef.current;
      if (currentRoom?.id === event.roomId) {
        setMessages((current) => {
          const updated = trimCachedMessages(upsertMessage(current, event.message), cacheLimitPerRoom);
          cacheMessages(cacheProvider, event.roomId, updated);
          return updated;
        });
        return;
      }

      cacheProvider.upsertRoomMessages?.(event.roomId, [event.message]).catch(() => undefined);
      setRooms((current) => current.map((room) => (room.id === event.roomId ? { ...room, unread: true } : room)));
    });

    const unsubscribeTyping = config.chatProvider.subscribeToTyping?.((event) => {
      const currentRoom = activeRoomRef.current;
      if (currentRoom?.id === event.roomId) {
        setTyping(event.isTyping);
      }
    });

    return () => {
      unsubscribeMessages?.();
      unsubscribeTyping?.();
    };
  }, [cacheLimitPerRoom, cacheProvider, config.chatProvider]);

  useEffect(() => {
    if (pendingInitialScrollRef.current) {
      return;
    }

    scrollToBottom();
  }, [messages.length, typing, scrollToBottom]);

  useEffect(() => {
    const showEvent = Platform.OS === "ios" ? "keyboardWillShow" : "keyboardDidShow";
    const hideEvent = Platform.OS === "ios" ? "keyboardWillHide" : "keyboardDidHide";
    const showSubscription = Keyboard.addListener(showEvent, () => {
      setTimeout(() => scrollToBottom(true), 80);
    });
    const hideSubscription = Keyboard.addListener(hideEvent, () => {
      setTimeout(() => scrollToBottom(true), 80);
    });

    return () => {
      showSubscription.remove();
      hideSubscription.remove();
    };
  }, [scrollToBottom]);

  function handleMessagesContentSizeChange() {
    if (pendingInitialScrollRef.current) {
      pendingInitialScrollRef.current = false;
      scrollToBottom(false);
      return;
    }

    if (Date.now() < settleInitialScrollUntilRef.current) {
      scrollToBottom(false);
    }
  }

  function handleScrollBegin() {
    if (scrollIdleTimeoutRef.current) {
      clearTimeout(scrollIdleTimeoutRef.current);
    }
    setDeferMedia(true);
  }

  function handleScrollIdle() {
    if (scrollIdleTimeoutRef.current) {
      clearTimeout(scrollIdleTimeoutRef.current);
    }
    scrollIdleTimeoutRef.current = setTimeout(() => {
      setDeferMedia(false);
    }, 180);
  }

  async function loadOlderMessages() {
    if (!activeRoom || loadingOlder || !hasMoreMessages) {
      return;
    }

    setLoadingOlder(true);
    try {
      const page = await loadMessagePage(config.chatProvider, activeRoom.id, nextCursor, messagePageSize);
      setMessages((current) => {
        const updated = trimCachedMessages(mergeMessages(page.messages, current), cacheLimitPerRoom);
        cacheMessages(cacheProvider, activeRoom.id, updated);
        return updated;
      });
      setNextCursor(page.nextCursor ?? null);
      setHasMoreMessages(page.hasMore);
    } catch (loadError) {
      setError(toErrorMessage(loadError, "Could not load older messages."));
    } finally {
      setLoadingOlder(false);
    }
  }

  function updateRoomPreview(roomId: string, message: ChatMessage) {
    setRooms((current) =>
      current.map((room) =>
        room.id === roomId
          ? {
              ...room,
              lastMessageText: previewForMessage(message),
              lastMessageAt: message.createdAt
            }
          : room
      )
    );
  }

  function openRoom(room: ChatRoom) {
    setActiveRoom(room);
    setError(null);
    setTyping(false);
    setSelectedMedia(null);
    setSelectedLocation(null);
    setRooms((current) => current.map((item) => (item.id === room.id ? { ...item, unread: false } : item)));
  }

  function closeRoom() {
    stopTyping();
    setActiveRoom(null);
    setMessages([]);
    inputRef.current = "";
    setComposerResetToken((current) => current + 1);
    setSelectedMedia(null);
    setSelectedLocation(null);
  }

  function handleChangeText(text: string) {
    inputRef.current = text;
    const roomId = activeRoom?.id;
    if (!roomId || !config.chatProvider.sendTyping) {
      return;
    }

    if (text.trim().length > 0 && !sentTypingStartRef.current) {
      sentTypingStartRef.current = true;
      sendTypingInBackground(roomId, true);
    }

    if (typingStopTimeoutRef.current) {
      clearTimeout(typingStopTimeoutRef.current);
    }

    typingStopTimeoutRef.current = setTimeout(() => {
      stopTyping();
    }, 2500);
  }

  function stopTyping() {
    if (typingStopTimeoutRef.current) {
      clearTimeout(typingStopTimeoutRef.current);
      typingStopTimeoutRef.current = null;
    }

    const roomId = activeRoomRef.current?.id;
    if (roomId && sentTypingStartRef.current) {
      sendTypingInBackground(roomId, false);
    }
    sentTypingStartRef.current = false;
  }

  function sendTypingInBackground(roomId: string, isTyping: boolean) {
    setTimeout(() => {
      Promise.resolve(config.chatProvider.sendTyping?.(roomId, isTyping)).catch(() => undefined);
    }, 0);
  }

  async function sendMessage() {
    if (!activeRoom) {
      return;
    }

    const text = inputRef.current.trim();
    if ((!text && !selectedMedia && !selectedLocation) || sending) {
      return;
    }

    stopTyping();
    setSending(true);
    setError(null);

    const optimisticMessage: ChatMessage = {
      id: `local-${Date.now()}`,
      roomId: activeRoom.id,
      role: "user",
      text: text || undefined,
      location: selectedLocation ?? undefined,
      createdAt: new Date().toISOString(),
      status: "sending",
      userId: user.id
    };

    try {
      let uploadedMedia = undefined;
      if (selectedMedia) {
        if (!config.mediaUploadProvider) {
          throw new Error("No media upload provider is configured.");
        }
        await onUploadMedia?.(selectedMedia);
        uploadedMedia = await config.mediaUploadProvider.upload(selectedMedia, activeRoom.id);
        optimisticMessage.media = uploadedMedia;
      }

      const outgoing: OutgoingMessage = {
        roomId: activeRoom.id,
        text: text || undefined,
        media: uploadedMedia,
        location: selectedLocation ?? undefined,
        localMedia: selectedMedia ?? undefined,
        userId: user.id,
        createdAt: optimisticMessage.createdAt,
        metadata: {
          sessionId: config.session?.sessionId
        }
      };

      setMessages((current) => {
        const updated = trimCachedMessages([...current, optimisticMessage], cacheLimitPerRoom);
        cacheMessages(cacheProvider, activeRoom.id, updated);
        return updated;
      });
      updateRoomPreview(activeRoom.id, optimisticMessage);
      inputRef.current = "";
      setComposerResetToken((current) => current + 1);
      setSelectedMedia(null);
      setSelectedLocation(null);
      await onSendMessage?.(outgoing);

      const response = await config.chatProvider.sendMessage(outgoing, activeRoom.id);
      setMessages((current) => {
        const updated =
          response.role === "user"
            ? current.map((message) => (message.id === optimisticMessage.id ? response : message))
            : [
                ...current.map((message) => (message.id === optimisticMessage.id ? { ...message, status: "sent" as const } : message)),
                response
              ];
        const trimmed = trimCachedMessages(updated, cacheLimitPerRoom);
        cacheMessages(cacheProvider, activeRoom.id, trimmed);
        return trimmed;
      });
    } catch (sendError) {
      setError(toErrorMessage(sendError, "Could not send message."));
      setMessages((current) =>
        current.map((message) => (message.id === optimisticMessage.id ? { ...message, status: "failed" as const } : message))
      );
    } finally {
      setSending(false);
    }
  }

  async function pickMedia(kind: Exclude<MediaKind, "audio">) {
    if (!config.mediaPickerProvider) {
      setError("No media picker provider is configured.");
      return;
    }

    try {
      setError(null);
      const file = await config.mediaPickerProvider.pickMedia(kind);
      if (file) {
        setSelectedLocation(null);
        setSelectedMedia(file);
      }
    } catch (pickError) {
      setError(toErrorMessage(pickError, "Could not select media."));
    }
  }

  async function shareLocation() {
    if (!config.locationProvider) {
      setError("No location provider is configured.");
      return;
    }

    try {
      setError(null);
      const location = await config.locationProvider.getCurrentLocation();
      setSelectedMedia(null);
      setSelectedLocation(location);
    } catch (locationError) {
      setError(toErrorMessage(locationError, "Could not get current location."));
    }
  }

  return (
    <SafeAreaView style={[styles.safeArea, { backgroundColor: resolvedTheme.backgroundColor }]}>
      <View style={[styles.container, { backgroundColor: resolvedTheme.backgroundColor }]}>
        {hasRoomList && !activeRoom ? (
          <ChatRoomList
            error={error}
            loading={loadingRooms}
            onRetry={() => config.chatProvider.getRooms?.().then(setRooms).catch((loadError) => setError(toErrorMessage(loadError, "Could not load chats.")))}
            onSelectRoom={openRoom}
            rooms={rooms}
            theme={resolvedTheme}
            title={resolvedTheme.headerTitle}
          />
        ) : (
          <>
            <View style={[styles.detailHeader, { borderColor: resolvedTheme.borderColor }]}>
              {hasRoomList ? (
                <Pressable accessibilityRole="button" accessibilityLabel="Back to chats" onPress={closeRoom} style={styles.detailBackButton}>
                  <Text style={[styles.detailBackIcon, { color: resolvedTheme.primaryColor }]}>‹</Text>
                  <Text style={[styles.detailBackLabel, { color: resolvedTheme.primaryColor, fontFamily: resolvedTheme.fontFamily }]}>
                    Chats
                  </Text>
                </Pressable>
              ) : null}
              <View style={styles.detailHeaderText}>
                <Text numberOfLines={1} style={[styles.detailTitle, { color: resolvedTheme.textColor, fontFamily: resolvedTheme.fontFamily }]}>
                  {activeRoom?.title ?? resolvedTheme.headerTitle}
                </Text>
                <Text numberOfLines={1} style={[styles.detailSubtitle, { color: resolvedTheme.mutedTextColor, fontFamily: resolvedTheme.fontFamily }]}>
                  {activeRoom?.subtitle ?? user.name}
                </Text>
              </View>
              {hasRoomList ? <View style={styles.detailHeaderSpacer} /> : null}
            </View>

            <KeyboardFrame avoidingEnabled={keyboardAvoidingEnabled}>
              {loading ? (
                <StateView theme={resolvedTheme} label="Loading conversation..." loading />
              ) : error && messages.length === 0 ? (
                <StateView
                  theme={resolvedTheme}
	                  label={error}
	                  actionLabel="Retry"
	                  onAction={async () => {
	                    if (!activeRoom) {
	                      return;
	                    }
	                    const page = await loadMessagePage(config.chatProvider, activeRoom.id, null, messagePageSize);
	                    setMessages(page.messages);
	                    setNextCursor(page.nextCursor ?? null);
	                    setHasMoreMessages(page.hasMore);
	                  }}
	                />
              ) : (
                <>
                  {messages.length === 0 ? (
                    <View style={styles.emptyWrap}>
                      <Text style={[styles.emptyTitle, { color: resolvedTheme.textColor, fontFamily: resolvedTheme.fontFamily }]}>
                        Start the conversation
                      </Text>
                      <Text style={[styles.emptyText, { color: resolvedTheme.mutedTextColor, fontFamily: resolvedTheme.fontFamily }]}>
                        Send a message, record voice, share location, or attach media to try the SDK.
                      </Text>
                    </View>
                  ) : null}
                  <FlashList
                    ref={messageListRef}
                    contentContainerStyle={styles.listContent}
                    data={displayedMessages}
                    estimatedItemSize={96}
                    inverted
                    keyExtractor={keyExtractor}
                    keyboardDismissMode="interactive"
                    keyboardShouldPersistTaps="handled"
                    ListFooterComponent={
                      loadingOlder ? (
                        <View style={styles.loadingOlder}>
                          <ActivityIndicator color={resolvedTheme.primaryColor} />
                        </View>
                      ) : null
                    }
                    onEndReached={loadOlderMessages}
                    onEndReachedThreshold={0.2}
                    onContentSizeChange={handleMessagesContentSizeChange}
                    onMomentumScrollBegin={handleScrollBegin}
                    onMomentumScrollEnd={handleScrollIdle}
                    onScrollBeginDrag={handleScrollBegin}
                    onScrollEndDrag={handleScrollIdle}
                    renderItem={renderMessage}
                  />
                  {typing ? <TypingIndicator theme={resolvedTheme} /> : null}
                </>
              )}

              {error && messages.length > 0 ? (
                <Text style={[styles.inlineError, { color: resolvedTheme.errorColor, fontFamily: resolvedTheme.fontFamily }]}>{error}</Text>
              ) : null}
              {selectedMedia ? <MediaPreview file={selectedMedia} theme={resolvedTheme} onRemove={() => setSelectedMedia(null)} /> : null}
              {selectedLocation ? (
                <LocationPreview location={selectedLocation} theme={resolvedTheme} onRemove={() => setSelectedLocation(null)} />
              ) : null}
              <ChatInput
                disabled={loading}
                hasMedia={Boolean(selectedMedia)}
                hasLocation={Boolean(selectedLocation)}
                onChangeText={handleChangeText}
                onPickMedia={pickMedia}
                onSend={sendMessage}
                onShareLocation={shareLocation}
                onVoiceRecorded={(file) => {
                  setError(null);
                  setSelectedLocation(null);
                  setSelectedMedia(file);
                }}
                onVoiceError={setError}
                sending={sending}
                theme={resolvedTheme}
                resetToken={composerResetToken}
              />
            </KeyboardFrame>
          </>
        )}
      </View>
    </SafeAreaView>
  );
}

function KeyboardFrame({ avoidingEnabled, children }: { avoidingEnabled: boolean; children: React.ReactNode }) {
  const [keyboardInset, setKeyboardInset] = useState(0);

  useEffect(() => {
    if (!avoidingEnabled || Platform.OS !== "ios") {
      setKeyboardInset(0);
      return;
    }

    const showSubscription = Keyboard.addListener("keyboardWillChangeFrame", (event) => {
      setKeyboardInset(Math.max(0, event.endCoordinates.height - IOS_HOME_INDICATOR_INSET));
    });
    const hideSubscription = Keyboard.addListener("keyboardWillHide", () => {
      setKeyboardInset(0);
    });

    return () => {
      showSubscription.remove();
      hideSubscription.remove();
    };
  }, [avoidingEnabled]);

  return <View style={[styles.keyboardAvoider, keyboardInset > 0 ? { paddingBottom: keyboardInset } : null]}>{children}</View>;
}

const IOS_HOME_INDICATOR_INSET = 34;

function ChatRoomList({
  error,
  loading,
  onRetry,
  onSelectRoom,
  rooms,
  theme,
  title
}: {
  error: string | null;
  loading: boolean;
  onRetry: () => void;
  onSelectRoom: (room: ChatRoom) => void;
  rooms: ChatRoom[];
  theme: ReturnType<typeof resolveTheme>;
  title: string;
}) {
  return (
    <View style={[styles.roomList, { backgroundColor: theme.inputBackgroundColor }]}>
      <View style={styles.roomListHeader}>
        <View style={styles.headerText}>
          <Text style={[styles.roomListTitle, { color: theme.textColor, fontFamily: theme.fontFamily }]}>{title}</Text>
          <Text style={[styles.roomListSubtitle, { color: theme.mutedTextColor, fontFamily: theme.fontFamily }]}>
            {rooms.length === 1 ? "1 chat" : `${rooms.length} chats`}
          </Text>
        </View>
      </View>

      {loading ? (
        <StateView theme={theme} label="Loading chats..." loading />
      ) : error && rooms.length === 0 ? (
        <StateView theme={theme} label={error} actionLabel="Retry" onAction={onRetry} />
      ) : rooms.length === 0 ? (
        <StateView theme={theme} label="No chats are available yet." />
      ) : (
        <FlatList
          contentContainerStyle={styles.roomListContent}
          data={rooms}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={`Open ${item.title}`}
              onPress={() => onSelectRoom(item)}
              style={({ pressed }) => [
                styles.roomRow,
                {
                  backgroundColor: pressed ? "#EAEAEC" : theme.backgroundColor,
                  borderColor: theme.borderColor
                }
              ]}
            >
              <View style={[styles.roomAvatar, { backgroundColor: theme.assistantBubbleColor }]}>
                <Text style={[styles.roomAvatarText, { color: theme.primaryColor, fontFamily: theme.fontFamily }]}>
                  {initialsFor(item.title)}
                </Text>
                {item.unread ? <View style={[styles.unreadDot, { backgroundColor: theme.errorColor }]} /> : null}
              </View>
              <View style={styles.roomBody}>
                <View style={styles.roomTitleRow}>
                  <Text numberOfLines={1} style={[styles.roomTitle, { color: theme.textColor, fontFamily: theme.fontFamily }]}>
                    {item.title}
                  </Text>
                  {item.lastMessageAt ? (
                    <Text style={[styles.roomTime, { color: theme.mutedTextColor, fontFamily: theme.fontFamily }]}>
                      {formatRoomTime(item.lastMessageAt)}
                    </Text>
                  ) : null}
                </View>
                <Text numberOfLines={1} style={[styles.roomSubtitle, { color: theme.mutedTextColor, fontFamily: theme.fontFamily }]}>
                  {item.lastMessageText ?? item.subtitle ?? "Open chat"}
                </Text>
              </View>
              <Text style={[styles.roomChevron, { color: theme.mutedTextColor }]}>›</Text>
            </Pressable>
          )}
        />
      )}
    </View>
  );
}

function StateView({
  theme,
  label,
  loading,
  actionLabel,
  onAction
}: {
  theme: ReturnType<typeof resolveTheme>;
  label: string;
  loading?: boolean;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <View style={styles.state}>
      {loading ? <ActivityIndicator color={theme.primaryColor} /> : null}
      <Text style={[styles.stateText, { color: theme.mutedTextColor, fontFamily: theme.fontFamily }]}>{label}</Text>
      {actionLabel && onAction ? (
        <Pressable style={[styles.retryButton, { backgroundColor: theme.primaryColor }]} onPress={onAction}>
          <Text style={styles.retryText}>{actionLabel}</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

function toErrorMessage(error: unknown, fallback: string): string {
  return error instanceof Error ? error.message : fallback;
}

function upsertMessage(messages: ChatMessage[], message: ChatMessage): ChatMessage[] {
  const existingIndex = messages.findIndex((item) => item.id === message.id);
  if (existingIndex >= 0) {
    return messages.map((item, index) => (index === existingIndex ? { ...item, ...message, status: message.status ?? item.status } : item));
  }

  const pendingIndex = messages.findIndex(
    (item) =>
      item.status === "sending" &&
      item.role === message.role &&
      item.roomId === message.roomId &&
      (item.text ?? "") === (message.text ?? "")
  );
  if (pendingIndex >= 0) {
    return messages.map((item, index) => (index === pendingIndex ? message : item));
  }

  return [...messages, message].sort((left, right) => new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime());
}

async function loadMessagePage(
  provider: ChatProvider,
  roomId: string,
  cursor: string | null = null,
  limit = 25
): Promise<ChatMessagesPage> {
  if (provider.getMessagesPage) {
    return provider.getMessagesPage({ roomId, cursor, limit });
  }

  if (cursor) {
    return {
      messages: [],
      nextCursor: null,
      hasMore: false
    };
  }

  return {
    messages: await provider.getMessages(roomId),
    nextCursor: null,
    hasMore: false
  };
}

function mergeMessages(olderMessages: ChatMessage[], currentMessages: ChatMessage[]): ChatMessage[] {
  const byId = new Map<string, ChatMessage>();
  [...olderMessages, ...currentMessages].forEach((message) => {
    byId.set(message.id, { ...byId.get(message.id), ...message });
  });

  return Array.from(byId.values()).sort((left, right) => new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime());
}

function trimCachedMessages(messages: ChatMessage[], limit: number): ChatMessage[] {
  if (messages.length <= limit) {
    return messages;
  }

  return messages.slice(messages.length - limit);
}

function cacheMessages(cacheProvider: ChatCacheProvider, roomId: string, messages: ChatMessage[]) {
  setTimeout(() => {
    cacheProvider.setRoomMessages(roomId, messages).catch(() => undefined);
  }, 0);
}

function waitForInteractions(): Promise<void> {
  return new Promise((resolve) => {
    InteractionManager.runAfterInteractions(() => resolve());
  });
}

function previewForMessage(message: ChatMessage): string {
  if (message.text) {
    return message.text;
  }
  if (message.location) {
    return "Shared a location";
  }
  if (message.media?.type === "audio") {
    return "Voice note";
  }
  if (message.media?.type === "image") {
    return "Image";
  }
  if (message.media?.type === "video") {
    return "Video";
  }
  return "New message";
}

function initialsFor(title: string): string {
  return title
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

function formatRoomTime(value: string): string {
  return new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(new Date(value));
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1
  },
  container: {
    flex: 1
  },
  keyboardAvoider: {
    flex: 1
  },
  header: {
    alignItems: "center",
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    gap: 8,
    paddingHorizontal: 20,
    paddingVertical: 14
  },
  detailHeader: {
    alignItems: "center",
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    minHeight: 56,
    paddingHorizontal: 12,
    paddingVertical: 8
  },
  detailBackButton: {
    alignItems: "center",
    flexDirection: "row",
    height: 40,
    justifyContent: "flex-start",
    minWidth: 64
  },
  detailBackIcon: {
    fontSize: 28,
    fontWeight: "500",
    lineHeight: 30,
    marginRight: 2
  },
  detailBackLabel: {
    fontSize: 16,
    lineHeight: 20
  },
  detailHeaderText: {
    alignItems: "center",
    flex: 1,
    justifyContent: "center",
    minWidth: 0
  },
  detailHeaderSpacer: {
    minWidth: 64
  },
  detailTitle: {
    fontSize: 17,
    fontWeight: "700",
    lineHeight: 21,
    maxWidth: "100%",
    textAlign: "center"
  },
  detailSubtitle: {
    fontSize: 12,
    lineHeight: 16,
    marginTop: 1,
    maxWidth: "100%",
    textAlign: "center"
  },
  backButton: {
    alignItems: "center",
    height: 34,
    justifyContent: "center",
    width: 34
  },
  backText: {
    fontSize: 34,
    lineHeight: 36
  },
  headerText: {
    flex: 1
  },
  title: {
    fontSize: 18,
    fontWeight: "700"
  },
  subtitle: {
    fontSize: 13,
    marginTop: 3
  },
  listContent: {
    paddingBottom: 10,
    paddingTop: 12
  },
  loadingOlder: {
    alignItems: "center",
    justifyContent: "center",
    paddingVertical: 14
  },
  state: {
    alignItems: "center",
    flex: 1,
    gap: 12,
    justifyContent: "center",
    padding: 24
  },
  stateText: {
    fontSize: 15,
    textAlign: "center"
  },
  retryButton: {
    borderRadius: 18,
    paddingHorizontal: 18,
    paddingVertical: 10
  },
  retryText: {
    color: "#FFFFFF",
    fontSize: 14,
    fontWeight: "700"
  },
  emptyWrap: {
    alignItems: "center",
    left: 24,
    position: "absolute",
    right: 24,
    top: "38%",
    zIndex: 0
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: "700",
    textAlign: "center"
  },
  emptyText: {
    fontSize: 14,
    lineHeight: 20,
    marginTop: 8,
    maxWidth: 280,
    textAlign: "center"
  },
  inlineError: {
    fontSize: 13,
    paddingHorizontal: 16,
    paddingVertical: 8,
    textAlign: "center"
  },
  roomList: {
    flex: 1,
    paddingTop: 24
  },
  roomListHeader: {
    paddingBottom: 12,
    paddingHorizontal: 20,
    paddingTop: 22
  },
  roomListTitle: {
    fontSize: 34,
    fontWeight: "800",
    letterSpacing: 0,
    lineHeight: 40
  },
  roomListSubtitle: {
    fontSize: 15,
    marginTop: 4
  },
  roomListContent: {
    paddingBottom: 18,
    paddingHorizontal: 16,
    paddingTop: 4
  },
  roomRow: {
    alignItems: "center",
    borderRadius: 14,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    gap: 12,
    minHeight: 76,
    marginBottom: 10,
    paddingHorizontal: 14,
    paddingVertical: 12
  },
  roomAvatar: {
    alignItems: "center",
    borderRadius: 24,
    height: 48,
    justifyContent: "center",
    width: 48
  },
  roomAvatarText: {
    fontSize: 16,
    fontWeight: "800"
  },
  unreadDot: {
    borderColor: "#FFFFFF",
    borderRadius: 6,
    borderWidth: 2,
    height: 12,
    position: "absolute",
    right: 0,
    top: 0,
    width: 12
  },
  roomBody: {
    flex: 1,
    gap: 4
  },
  roomTitleRow: {
    alignItems: "center",
    flexDirection: "row",
    gap: 10
  },
  roomTitle: {
    flex: 1,
    fontSize: 16,
    fontWeight: "700"
  },
  roomTime: {
    fontSize: 12
  },
  roomSubtitle: {
    fontSize: 13
  },
  roomChevron: {
    fontSize: 28,
    lineHeight: 30
  }
});
