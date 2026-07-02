import React from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import type { ChatLocation } from "../types/location";
import type { ResolvedChatTheme } from "../types/theme";

interface LocationPreviewProps {
  location: ChatLocation;
  theme: ResolvedChatTheme;
  onRemove: () => void;
}

export function LocationPreview({ location, theme, onRemove }: LocationPreviewProps) {
  return (
    <View style={[styles.container, { borderColor: theme.borderColor, backgroundColor: theme.inputBackgroundColor }]}>
      <View style={[styles.pin, { backgroundColor: theme.primaryColor }]}>
        <Text style={styles.pinText}>📍</Text>
      </View>
      <View style={styles.meta}>
        <Text numberOfLines={1} style={[styles.name, { color: theme.textColor, fontFamily: theme.fontFamily }]}>
          {location.name ?? "Shared location"}
        </Text>
        <Text numberOfLines={1} style={[styles.coords, { color: theme.mutedTextColor, fontFamily: theme.fontFamily }]}>
          {location.address ?? formatCoordinates(location.latitude, location.longitude)}
        </Text>
      </View>
      <Pressable accessibilityRole="button" accessibilityLabel="Remove location" onPress={onRemove} style={styles.remove}>
        <Text style={[styles.removeText, { color: theme.errorColor }]}>×</Text>
      </Pressable>
    </View>
  );
}

function formatCoordinates(latitude: number, longitude: number): string {
  return `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`;
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
  pin: {
    alignItems: "center",
    borderRadius: 8,
    height: 44,
    justifyContent: "center",
    width: 44
  },
  pinText: {
    color: "#FFFFFF",
    fontSize: 22,
    fontWeight: "800"
  },
  meta: {
    flex: 1
  },
  name: {
    fontSize: 14,
    fontWeight: "700"
  },
  coords: {
    fontSize: 12,
    marginTop: 2
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
