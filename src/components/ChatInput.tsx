import React, { useEffect, useState } from "react";
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from "react-native";
import type { LocalMediaFile, MediaKind } from "../types/media";
import type { ResolvedChatTheme } from "../types/theme";
import { VoiceInputButton } from "./VoiceInputButton";

interface ChatInputProps {
  theme: ResolvedChatTheme;
  disabled?: boolean;
  sending?: boolean;
  hasMedia?: boolean;
  hasLocation?: boolean;
  resetToken?: number;
  onChangeText: (text: string) => void;
  onSend: () => void;
  onPickMedia: (kind: Exclude<MediaKind, "audio">) => void;
  onShareLocation: () => void;
  onVoiceRecorded: (file: LocalMediaFile) => void;
  onVoiceError: (message: string) => void;
}

export function ChatInput({
  theme,
  disabled,
  sending,
  hasMedia,
  hasLocation,
  resetToken,
  onChangeText,
  onSend,
  onPickMedia,
  onShareLocation,
  onVoiceRecorded,
  onVoiceError
}: ChatInputProps) {
  const [value, setValue] = useState("");
  const [recordingVoice, setRecordingVoice] = useState(false);
  const [showActions, setShowActions] = useState(false);
  const canSend = (value.trim().length > 0 || hasMedia || hasLocation) && !disabled && !sending;
  const canShowActions = theme.showMediaUploadButton || theme.showLocationButton;

  useEffect(() => {
    setValue("");
  }, [resetToken]);

  function handleTextChange(text: string) {
    setValue(text);
    onChangeText(text);
  }

  function selectAction(action: "location" | "image" | "video") {
    setShowActions(false);
    if (action === "location") {
      onShareLocation();
      return;
    }

    onPickMedia(action);
  }

  return (
    <View style={[styles.container, { backgroundColor: theme.backgroundColor, borderColor: theme.borderColor }]}>
      {!recordingVoice && canShowActions ? (
        <View style={styles.actionAnchor}>
          {showActions ? (
            <View style={[styles.actionMenu, { backgroundColor: theme.backgroundColor, borderColor: theme.borderColor }]}>
              {theme.showLocationButton ? (
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel="Share location"
                  disabled={disabled}
                  onPress={() => selectAction("location")}
                  style={styles.actionItem}
                >
                  <Text style={styles.actionIcon}>⌖</Text>
                  <Text style={[styles.actionLabel, { color: theme.textColor, fontFamily: theme.fontFamily }]}>Location</Text>
                </Pressable>
              ) : null}
              {theme.showMediaUploadButton ? (
                <>
                  <Pressable
                    accessibilityRole="button"
                    accessibilityLabel="Send photo"
                    disabled={disabled}
                    onPress={() => selectAction("image")}
                    style={styles.actionItem}
                  >
                    <Text style={styles.actionIcon}>▧</Text>
                    <Text style={[styles.actionLabel, { color: theme.textColor, fontFamily: theme.fontFamily }]}>Photo</Text>
                  </Pressable>
                  <Pressable
                    accessibilityRole="button"
                    accessibilityLabel="Send video"
                    disabled={disabled}
                    onPress={() => selectAction("video")}
                    style={styles.actionItem}
                  >
                    <Text style={styles.actionIcon}>▶</Text>
                    <Text style={[styles.actionLabel, { color: theme.textColor, fontFamily: theme.fontFamily }]}>Video</Text>
                  </Pressable>
                </>
              ) : null}
            </View>
          ) : null}
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Open attachment menu"
            disabled={disabled}
            onPress={() => setShowActions((current) => !current)}
            style={[styles.iconButton, { backgroundColor: theme.inputBackgroundColor, borderColor: theme.borderColor, opacity: disabled ? 0.45 : 1 }]}
          >
            <Text style={[styles.plusIcon, { color: theme.primaryColor }]}>{showActions ? "×" : "+"}</Text>
          </Pressable>
        </View>
      ) : null}
      {theme.showMicrophoneButton ? (
        <VoiceInputButton
          key="voice-input"
          theme={theme}
          disabled={disabled}
          expanded={recordingVoice}
          onRecorded={onVoiceRecorded}
          onError={onVoiceError}
          onRecordingChange={setRecordingVoice}
        />
      ) : null}
      {!recordingVoice ? (
        <>
          <TextInput
            accessibilityLabel="Message input"
            autoCapitalize="sentences"
            autoComplete="off"
            autoCorrect={false}
            editable={!disabled}
            importantForAutofill="no"
            multiline
            onChangeText={handleTextChange}
            placeholder={theme.placeholderText}
            placeholderTextColor={theme.mutedTextColor}
            spellCheck={false}
            style={[
              styles.input,
              {
                backgroundColor: theme.inputBackgroundColor,
                borderColor: theme.borderColor,
                borderRadius: theme.borderRadius,
                color: theme.textColor,
                fontFamily: theme.fontFamily
              }
            ]}
            textContentType="none"
            value={value}
          />
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Send message"
            disabled={!canSend}
            onPress={onSend}
            style={[styles.sendButton, { backgroundColor: theme.primaryColor, opacity: canSend ? 1 : 0.45 }]}
          >
            {sending ? <ActivityIndicator color="#FFFFFF" /> : theme.sendButtonIcon ?? <Text style={styles.sendText}>↑</Text>}
          </Pressable>
        </>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: "flex-end",
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 10
  },
  iconButton: {
    alignItems: "center",
    borderRadius: 18,
    borderWidth: StyleSheet.hairlineWidth,
    height: 40,
    justifyContent: "center",
    width: 40
  },
  actionAnchor: {
    position: "relative"
  },
  actionMenu: {
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    bottom: 48,
    left: 0,
    minWidth: 150,
    paddingVertical: 6,
    position: "absolute",
    shadowColor: "#000000",
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.16,
    shadowRadius: 18,
    zIndex: 10,
    elevation: 8
  },
  actionItem: {
    alignItems: "center",
    flexDirection: "row",
    gap: 10,
    minHeight: 42,
    paddingHorizontal: 12
  },
  actionIcon: {
    color: "#111827",
    fontSize: 18,
    lineHeight: 22,
    textAlign: "center",
    width: 24
  },
  actionLabel: {
    fontSize: 15,
    fontWeight: "600"
  },
  plusIcon: {
    fontSize: 24,
    fontWeight: "600",
    lineHeight: 26
  },
  input: {
    borderWidth: StyleSheet.hairlineWidth,
    flex: 1,
    fontSize: 15,
    maxHeight: 120,
    minHeight: 40,
    paddingHorizontal: 14,
    paddingVertical: 9
  },
  sendButton: {
    alignItems: "center",
    borderRadius: 20,
    height: 40,
    justifyContent: "center",
    width: 40
  },
  sendText: {
    color: "#FFFFFF",
    fontSize: 24,
    lineHeight: 26
  }
});
