import React, { useEffect, useState } from "react";
import { Image, InteractionManager, Linking, Pressable, StyleSheet, Text, View } from "react-native";
import type { ChatMessage } from "../types/chat";
import type { ChatLocation } from "../types/location";
import type { ResolvedChatTheme } from "../types/theme";

interface MessageBubbleProps {
  message: ChatMessage;
  theme: ResolvedChatTheme;
  deferMedia?: boolean;
}

export const MessageBubble = React.memo(function MessageBubble({ message, theme, deferMedia }: MessageBubbleProps) {
  const isUser = message.role === "user";
  const bubbleColor = isUser ? theme.userBubbleColor : theme.assistantBubbleColor;
  const foreground = isUser ? "#FFFFFF" : theme.textColor;

  return (
    <View style={[styles.row, isUser ? styles.userRow : styles.assistantRow]}>
      {!isUser ? <Avatar source={theme.assistantAvatar ?? theme.avatar} fallback="A" theme={theme} /> : null}
      <View style={[styles.bubble, { backgroundColor: bubbleColor, borderRadius: theme.borderRadius }]}>
        {message.media ? <MediaBubble deferMedia={deferMedia} message={message} foreground={foreground} theme={theme} /> : null}
        {message.location ? <LocationBubble location={message.location} foreground={foreground} theme={theme} /> : null}
        {message.text ? (
          <Text style={[styles.text, { color: foreground, fontFamily: theme.fontFamily }]}>{message.text}</Text>
        ) : null}
        <Text style={[styles.time, { color: isUser ? "rgba(255,255,255,0.72)" : theme.mutedTextColor, fontFamily: theme.fontFamily }]}>
          {formatTime(message.createdAt)}
        </Text>
      </View>
      {isUser ? <Avatar source={theme.avatar} fallback="U" theme={theme} /> : null}
    </View>
  );
});

function LocationBubble({
  location,
  foreground,
  theme
}: {
  location: ChatLocation;
  foreground: string;
  theme: ResolvedChatTheme;
}) {
  const mapUrl = location.mapUrl ?? `https://maps.apple.com/?ll=${location.latitude},${location.longitude}`;

  async function openMap() {
    await Linking.openURL(mapUrl).catch(() => undefined);
  }

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel="Open shared location"
      onPress={openMap}
      style={[styles.locationBubble, { borderColor: theme.borderColor }]}
    >
      <View style={[styles.mapPreview, { backgroundColor: foreground }]}>
        <Text style={[styles.mapPin, { color: theme.backgroundColor }]}>📍</Text>
      </View>
      <View style={styles.locationMeta}>
        <Text numberOfLines={1} style={[styles.locationTitle, { color: foreground, fontFamily: theme.fontFamily }]}>
          {location.name ?? "Shared location"}
        </Text>
        <Text numberOfLines={2} style={[styles.locationText, { color: foreground, fontFamily: theme.fontFamily }]}>
          {location.address ?? formatCoordinates(location.latitude, location.longitude)}
        </Text>
      </View>
    </Pressable>
  );
}

function Avatar({ source, fallback, theme }: { source?: ResolvedChatTheme["avatar"]; fallback: string; theme: ResolvedChatTheme }) {
  if (typeof source === "string") {
    return <RemoteImage uri={source} style={styles.avatar} />;
  }

  if (source) {
    return <Image source={source} style={styles.avatar} />;
  }

  return (
    <View style={[styles.avatarFallback, { backgroundColor: theme.inputBackgroundColor, borderColor: theme.borderColor }]}>
      <Text style={[styles.avatarText, { color: theme.mutedTextColor, fontFamily: theme.fontFamily }]}>{fallback}</Text>
    </View>
  );
}

function MediaBubble({
  message,
  foreground,
  theme,
  deferMedia
}: {
  message: ChatMessage;
  foreground: string;
  theme: ResolvedChatTheme;
  deferMedia?: boolean;
}) {
  const media = message.media;
  if (!media) {
    return null;
  }

  if (media.type === "image") {
    return <RemoteImage deferLoad={deferMedia} uri={media.thumbnailUrl ?? media.url} style={styles.mediaImage} />;
  }

  if (media.type === "audio") {
    return <AudioBubble uri={media.url} durationMs={media.metadata?.durationMs} foreground={foreground} theme={theme} />;
  }

  return (
    <View style={[styles.videoBubble, { borderColor: theme.borderColor }]}>
      <Text style={[styles.videoIcon, { color: foreground }]}>▶</Text>
      <Text numberOfLines={1} style={[styles.videoText, { color: foreground, fontFamily: theme.fontFamily }]}>
        {media.name ?? "Video attachment"}
      </Text>
    </View>
  );
}

function AudioBubble({
  uri,
  durationMs,
  foreground,
  theme
}: {
  uri: string;
  durationMs?: unknown;
  foreground: string;
  theme: ResolvedChatTheme;
}) {
  const [playing, setPlaying] = useState(false);

  useEffect(() => {
    return () => {
      removePlaybackListener();
      if (playing) {
        getNitroSound().stopPlayer().catch(() => undefined);
      }
    };
  }, [playing]);

  async function togglePlayback() {
    try {
      const NitroSound = getNitroSound();
      if (playing) {
        await NitroSound.stopPlayer();
        setPlaying(false);
        return;
      }

      await NitroSound.stopPlayer().catch(() => undefined);
      removePlaybackListener();
      await NitroSound.startPlayer(uri);
      NitroSound.addPlaybackEndListener(() => {
        removePlaybackListener();
        setPlaying(false);
      });
      setPlaying(true);
    } catch {
      setPlaying(false);
    }
  }

  return (
    <View style={[styles.audioBubble, { borderColor: theme.borderColor }]}>
      <Pressable accessibilityRole="button" accessibilityLabel={playing ? "Stop voice note" : "Play voice note"} onPress={togglePlayback} style={styles.audioButton}>
        <Text style={[styles.audioButtonText, { color: foreground }]}>{playing ? "■" : "▶"}</Text>
      </Pressable>
      <View style={styles.waveform}>
        <View style={[styles.waveBar, { backgroundColor: foreground, height: 12 }]} />
        <View style={[styles.waveBar, { backgroundColor: foreground, height: 22 }]} />
        <View style={[styles.waveBar, { backgroundColor: foreground, height: 16 }]} />
        <View style={[styles.waveBar, { backgroundColor: foreground, height: 28 }]} />
        <View style={[styles.waveBar, { backgroundColor: foreground, height: 18 }]} />
        <View style={[styles.waveBar, { backgroundColor: foreground, height: 24 }]} />
        <View style={[styles.waveBar, { backgroundColor: foreground, height: 14 }]} />
      </View>
      <Text style={[styles.audioDuration, { color: foreground, fontFamily: theme.fontFamily }]}>
        {typeof durationMs === "number" ? formatDuration(durationMs) : "Voice note"}
      </Text>
    </View>
  );
}

function RemoteImage({ uri, style, deferLoad }: { uri: string; style: any; deferLoad?: boolean }) {
  const [loaded, setLoaded] = useState(false);
  const [shouldLoad, setShouldLoad] = useState(false);

  useEffect(() => {
    const interaction = InteractionManager.runAfterInteractions(() => {
      if (!deferLoad) {
        setShouldLoad(true);
      }
    });

    return () => {
      interaction.cancel();
    };
  }, [deferLoad, uri]);

  return (
    <View style={style}>
      {!loaded ? <View style={[StyleSheet.absoluteFillObject, styles.imagePlaceholder]} /> : null}
      {shouldLoad ? (
        <Image
          onLoadEnd={() => setLoaded(true)}
          resizeMethod="resize"
          resizeMode="cover"
          source={{ uri, cache: "force-cache" } as any}
          style={StyleSheet.absoluteFillObject}
        />
      ) : null}
    </View>
  );
}

function removePlaybackListener() {
  (getNitroSound() as any).removePlaybackEndListener?.();
}

function getNitroSound(): typeof import("react-native-nitro-sound").default {
  return require("react-native-nitro-sound").default;
}

function formatTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function formatDuration(durationMs: number): string {
  const totalSeconds = Math.max(0, Math.round(durationMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

function formatCoordinates(latitude: number, longitude: number): string {
  return `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`;
}

const styles = StyleSheet.create({
  row: {
    alignItems: "flex-end",
    flexDirection: "row",
    gap: 8,
    marginHorizontal: 16,
    marginVertical: 6
  },
  userRow: {
    justifyContent: "flex-end"
  },
  assistantRow: {
    justifyContent: "flex-start"
  },
  bubble: {
    maxWidth: "78%",
    paddingHorizontal: 14,
    paddingVertical: 10
  },
  text: {
    fontSize: 15,
    lineHeight: 21
  },
  time: {
    alignSelf: "flex-end",
    fontSize: 11,
    marginTop: 6
  },
  avatar: {
    borderRadius: 16,
    height: 32,
    width: 32
  },
  avatarFallback: {
    alignItems: "center",
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    height: 32,
    justifyContent: "center",
    width: 32
  },
  avatarText: {
    fontSize: 12,
    fontWeight: "700"
  },
  mediaImage: {
    borderRadius: 12,
    height: 180,
    marginBottom: 8,
    overflow: "hidden",
    width: 220
  },
  imagePlaceholder: {
    backgroundColor: "rgba(148, 163, 184, 0.22)"
  },
  videoBubble: {
    alignItems: "center",
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    gap: 8,
    marginBottom: 8,
    minWidth: 180,
    padding: 12
  },
  videoIcon: {
    fontSize: 16
  },
  videoText: {
    flex: 1,
    fontSize: 14,
    fontWeight: "600"
  },
  audioBubble: {
    alignItems: "center",
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    gap: 10,
    marginBottom: 8,
    minWidth: 220,
    paddingHorizontal: 10,
    paddingVertical: 12
  },
  audioButton: {
    alignItems: "center",
    height: 32,
    justifyContent: "center",
    width: 32
  },
  audioButtonText: {
    fontSize: 16,
    fontWeight: "800"
  },
  waveform: {
    alignItems: "center",
    flex: 1,
    flexDirection: "row",
    gap: 4,
    minHeight: 32
  },
  waveBar: {
    borderRadius: 2,
    opacity: 0.68,
    width: 4
  },
  audioDuration: {
    fontSize: 12,
    fontWeight: "700"
  },
  locationBubble: {
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    marginBottom: 8,
    minWidth: 220,
    overflow: "hidden"
  },
  mapPreview: {
    alignItems: "center",
    height: 78,
    justifyContent: "center",
    opacity: 0.9
  },
  mapPin: {
    fontSize: 30,
    fontWeight: "800"
  },
  locationMeta: {
    padding: 10
  },
  locationTitle: {
    fontSize: 14,
    fontWeight: "800"
  },
  locationText: {
    fontSize: 12,
    lineHeight: 16,
    marginTop: 2,
    opacity: 0.78
  }
});
