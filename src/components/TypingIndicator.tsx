import React from "react";
import { StyleSheet, Text, View } from "react-native";
import type { ResolvedChatTheme } from "../types/theme";

interface TypingIndicatorProps {
  theme: ResolvedChatTheme;
}

export function TypingIndicator({ theme }: TypingIndicatorProps) {
  return (
    <View style={[styles.container, { backgroundColor: theme.assistantBubbleColor, borderRadius: theme.borderRadius }]}>
      <Text style={[styles.dot, { color: theme.mutedTextColor, fontFamily: theme.fontFamily }]}>Assistant is typing...</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignSelf: "flex-start",
    marginHorizontal: 16,
    marginVertical: 6,
    paddingHorizontal: 14,
    paddingVertical: 10
  },
  dot: {
    fontSize: 13
  }
});
