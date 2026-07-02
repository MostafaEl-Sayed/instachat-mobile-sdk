import React from "react";
import { Image, Pressable, StyleSheet, Text, View } from "react-native";
import type { LocalMediaFile } from "../types/media";
import type { ResolvedChatTheme } from "../types/theme";

interface MediaPreviewProps {
  file: LocalMediaFile;
  theme: ResolvedChatTheme;
  onRemove: () => void;
}

export function MediaPreview({ file, theme, onRemove }: MediaPreviewProps) {
  return (
    <View style={[styles.container, { borderColor: theme.borderColor, backgroundColor: theme.inputBackgroundColor }]}>
      {file.type === "image" ? (
        <Image source={{ uri: file.uri }} style={styles.thumbnail} />
      ) : file.type === "video" ? (
        <View style={[styles.videoThumb, { backgroundColor: theme.primaryColor }]}>
          <Text style={[styles.videoIcon, { color: "#FFFFFF" }]}>▶</Text>
        </View>
      ) : (
        <View style={[styles.videoThumb, { backgroundColor: theme.primaryColor }]}>
          <Text style={[styles.videoIcon, { color: "#FFFFFF" }]}>♪</Text>
        </View>
      )}
      <View style={styles.meta}>
        <Text numberOfLines={1} style={[styles.name, { color: theme.textColor, fontFamily: theme.fontFamily }]}>
          {file.name ?? `${file.type} upload`}
        </Text>
        <Text style={[styles.type, { color: theme.mutedTextColor, fontFamily: theme.fontFamily }]}>
          {file.type === "audio" ? `Voice note${file.durationMs ? ` · ${formatDuration(file.durationMs)}` : ""}` : file.type}
        </Text>
      </View>
      <Pressable accessibilityRole="button" accessibilityLabel="Remove media" onPress={onRemove} style={styles.remove}>
        <Text style={[styles.removeText, { color: theme.errorColor }]}>×</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: "center",
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    gap: 10,
    paddingHorizontal: 16,
    paddingVertical: 10
  },
  thumbnail: {
    borderRadius: 8,
    height: 44,
    width: 44
  },
  videoThumb: {
    alignItems: "center",
    borderRadius: 8,
    height: 44,
    justifyContent: "center",
    width: 44
  },
  videoIcon: {
    fontSize: 16
  },
  meta: {
    flex: 1
  },
  name: {
    fontSize: 14,
    fontWeight: "600"
  },
  type: {
    fontSize: 12,
    marginTop: 2,
    textTransform: "capitalize"
  },
  remove: {
    alignItems: "center",
    height: 32,
    justifyContent: "center",
    width: 32
  },
  removeText: {
    fontSize: 26,
    lineHeight: 28
  }
});

function formatDuration(durationMs: number): string {
  const totalSeconds = Math.max(0, Math.round(durationMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}
