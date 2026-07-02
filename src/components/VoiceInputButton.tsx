import React, { useEffect, useRef, useState } from "react";
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, View } from "react-native";
import NitroSound from "react-native-nitro-sound";
import type { LocalMediaFile } from "../types/media";
import type { ResolvedChatTheme } from "../types/theme";
import { requestMicrophonePermission } from "../utils/permissions";

interface VoiceInputButtonProps {
  theme: ResolvedChatTheme;
  disabled?: boolean;
  expanded?: boolean;
  onRecorded: (file: LocalMediaFile) => void;
  onError: (message: string) => void;
  onRecordingChange?: (recording: boolean) => void;
}

export function VoiceInputButton({ theme, disabled, expanded, onRecorded, onError, onRecordingChange }: VoiceInputButtonProps) {
  const [recording, setRecording] = useState(false);
  const [processing, setProcessing] = useState(false);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [waveformLevels, setWaveformLevels] = useState(() => createInitialWaveform());
  const startedAt = useRef<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const fallbackWaveStepRef = useRef(0);
  const latestLevelRef = useRef(0.22);
  const lastMeterSampleAtRef = useRef(0);
  const receivedMeteringRef = useRef(false);

  useEffect(() => {
    return () => {
      clearTimer();
      clearMetering();
    };
  }, []);

  function clearTimer() {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }

  function clearMetering() {
    (NitroSound as any).removeRecordBackListener?.();
  }

  function beginTimer(started: number) {
    clearTimer();
    setElapsedSeconds(0);
    setWaveformLevels(createInitialWaveform());
    timerRef.current = setInterval(() => {
      setElapsedSeconds(Math.floor((Date.now() - started) / 1000));
      if (!receivedMeteringRef.current) {
        pushFallbackLevel();
      }
    }, 500);
  }

  function beginMetering() {
    clearMetering();
    NitroSound.addRecordBackListener?.((event: { currentMetering?: number; currentPosition?: number }) => {
      if (typeof event.currentPosition === "number") {
        setElapsedSeconds(Math.floor(event.currentPosition / 1000));
      }
      if (typeof event.currentMetering === "number") {
        pushMeterLevel(event.currentMetering);
      }
    });
  }

  function pushMeterLevel(metering: number) {
    const now = Date.now();
    if (now - lastMeterSampleAtRef.current < 170) {
      return;
    }

    lastMeterSampleAtRef.current = now;
    receivedMeteringRef.current = true;
    const normalized = normalizeMetering(metering);
    const smoothed = latestLevelRef.current * 0.68 + normalized * 0.32;
    latestLevelRef.current = smoothed;
    setWaveformLevels((current) => [...current.slice(1), smoothed]);
  }

  function pushFallbackLevel() {
    fallbackWaveStepRef.current += 1;
    const level = 0.26 + Math.abs(Math.sin(fallbackWaveStepRef.current * 0.42)) * 0.24;
    setWaveformLevels((current) => [...current.slice(1), level]);
  }

  function setRecordingState(value: boolean) {
    setRecording(value);
    onRecordingChange?.(value);
  }

  async function toggleRecording() {
    if (disabled || processing) {
      return;
    }

    try {
      if (!recording) {
        const granted = await requestMicrophonePermission();
        if (!granted) {
          onError("Microphone permission was denied.");
          return;
        }

        startedAt.current = Date.now();
        receivedMeteringRef.current = false;
        lastMeterSampleAtRef.current = 0;
        latestLevelRef.current = 0.22;
        await NitroSound.startRecorder(undefined, undefined, true);
        beginTimer(startedAt.current);
        beginMetering();
        setRecordingState(true);
        return;
      }

      await finishRecording();
    } catch (error) {
      clearTimer();
      clearMetering();
      setRecordingState(false);
      const message = error instanceof Error ? error.message : "Voice input failed.";
      onError(message);
      Alert.alert("Voice input failed", message);
    } finally {
      setProcessing(false);
    }
  }

  async function finishRecording() {
    setProcessing(true);
    const audioUri = await NitroSound.stopRecorder();
    const stoppedAt = Date.now();
    clearTimer();
    clearMetering();
    setRecordingState(false);
    const started = startedAt.current ?? stoppedAt;
    startedAt.current = null;
    receivedMeteringRef.current = false;
    const uri = audioUri || `recording-${started}.m4a`;
    onRecorded({
      uri,
      type: "audio",
      name: `voice-note-${started}.m4a`,
      mimeType: "audio/m4a",
      durationMs: Math.max(0, stoppedAt - started)
    });
  }

  async function cancelRecording() {
    if (processing) {
      return;
    }

    try {
      setProcessing(true);
      await NitroSound.stopRecorder().catch(() => undefined);
    } finally {
      clearTimer();
      clearMetering();
      startedAt.current = null;
      receivedMeteringRef.current = false;
      setElapsedSeconds(0);
      setProcessing(false);
      setRecordingState(false);
    }
  }

  if (recording || expanded) {
    return (
      <View style={styles.recordingWrap}>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Cancel voice note"
          onPress={cancelRecording}
          style={styles.trashButton}
        >
          <Text style={[styles.trashText, { color: theme.mutedTextColor }]}>🗑</Text>
        </Pressable>
        <View style={[styles.recordingPill, { backgroundColor: theme.inputBackgroundColor, borderColor: theme.borderColor }]}>
          <View style={[styles.recordingDot, { backgroundColor: theme.errorColor }]} />
          <Text style={[styles.timerText, { color: theme.mutedTextColor, fontFamily: theme.fontFamily }]}>
            {formatDuration(elapsedSeconds)}
          </Text>
          <View style={styles.liveWaveform}>
            {waveformLevels.map((level, index) => (
              <View
                key={index}
                style={[styles.liveBar, { backgroundColor: theme.mutedTextColor, height: 7 + Math.round(level * 24) }]}
              />
            ))}
          </View>
        </View>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Finish voice note"
          disabled={processing}
          onPress={toggleRecording}
          style={[styles.finishButton, { backgroundColor: theme.primaryColor, opacity: processing ? 0.6 : 1 }]}
        >
          {processing ? <ActivityIndicator size="small" color="#FFFFFF" /> : <Text style={styles.finishText}>➤</Text>}
        </Pressable>
      </View>
    );
  }

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={recording ? "Stop recording" : "Start voice input"}
      disabled={disabled}
      onPress={toggleRecording}
      style={[
        styles.button,
        {
          backgroundColor: recording ? theme.errorColor : theme.inputBackgroundColor,
          borderColor: theme.borderColor,
          opacity: disabled ? 0.45 : 1
        }
      ]}
    >
      {processing ? (
        <ActivityIndicator size="small" color={theme.primaryColor} />
      ) : (
        <Text style={[styles.icon, { color: recording ? "#FFFFFF" : theme.primaryColor }]}>{recording ? "■" : "🎙"}</Text>
      )}
    </Pressable>
  );
}

function formatDuration(totalSeconds: number): string {
  const safeSeconds = Math.max(0, totalSeconds);
  const minutes = Math.floor(safeSeconds / 60);
  const seconds = safeSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

function createInitialWaveform(): number[] {
  return Array.from({ length: 24 }, (_, index) => 0.18 + (index % 5) * 0.04);
}

function normalizeMetering(value: number): number {
  if (value >= 0 && value <= 1) {
    return clamp(value, 0.08, 1);
  }

  const db = Math.max(-60, Math.min(0, value));
  return clamp((db + 60) / 60, 0.08, 1);
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

const styles = StyleSheet.create({
  button: {
    alignItems: "center",
    borderRadius: 18,
    borderWidth: StyleSheet.hairlineWidth,
    height: 40,
    justifyContent: "center",
    width: 40
  },
  icon: {
    fontSize: 18,
    lineHeight: 22
  },
  recordingWrap: {
    alignItems: "center",
    flex: 1,
    flexDirection: "row",
    gap: 8
  },
  trashButton: {
    alignItems: "center",
    height: 40,
    justifyContent: "center",
    width: 36
  },
  trashText: {
    fontSize: 22,
    fontWeight: "700"
  },
  recordingPill: {
    alignItems: "center",
    borderRadius: 22,
    borderWidth: StyleSheet.hairlineWidth,
    flex: 1,
    flexDirection: "row",
    gap: 10,
    minHeight: 44,
    paddingHorizontal: 14
  },
  recordingDot: {
    borderRadius: 5,
    height: 10,
    width: 10
  },
  timerText: {
    fontSize: 16,
    fontWeight: "600",
    minWidth: 42
  },
  liveWaveform: {
    alignItems: "center",
    flex: 1,
    flexDirection: "row",
    gap: 3,
    justifyContent: "flex-end"
  },
  liveBar: {
    borderRadius: 2,
    opacity: 0.9,
    width: 3
  },
  finishButton: {
    alignItems: "center",
    borderRadius: 22,
    height: 44,
    justifyContent: "center",
    width: 44
  },
  finishText: {
    color: "#FFFFFF",
    fontSize: 22,
    fontWeight: "800",
    lineHeight: 24
  }
});
