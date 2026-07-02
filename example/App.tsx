import React, { useMemo, useRef } from "react";
import * as ImagePicker from "expo-image-picker";
import * as Location from "expo-location";
import { StyleSheet, View } from "react-native";
import {
  InstaChatSDK,
  type ChatLocation,
  type ChatTheme,
  type LocationProvider,
  type LocalMediaFile,
  type MediaKind,
  type MediaPickerProvider
} from "react-native-chat-sdk";

interface NativeChatProps {
  baseUrl?: string;
  token?: string;
  userId?: string;
  userName?: string;
  headerTitle?: string;
  placeholderText?: string;
}

const DEFAULT_BASE_URL = "https://instachat.instakit.pro";
const DEFAULT_TOKEN = "";

class ExpoMediaPickerProvider implements MediaPickerProvider {
  async pickMedia(kind: Exclude<MediaKind, "audio">): Promise<LocalMediaFile | null> {
    const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!permission.granted) {
      throw new Error("Photo library permission was denied.");
    }

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: kind === "image" ? ImagePicker.MediaTypeOptions.Images : ImagePicker.MediaTypeOptions.Videos,
      quality: 0.9,
      allowsEditing: false
    });

    if (result.canceled || result.assets.length === 0) {
      return null;
    }

    const asset = result.assets[0];
    return {
      uri: asset.uri,
      type: kind,
      name: asset.fileName ?? `${kind}-upload`,
      mimeType: asset.mimeType,
      width: asset.width,
      height: asset.height,
      durationMs: asset.duration ?? undefined,
      size: asset.fileSize
    };
  }
}

class ExpoLocationProvider implements LocationProvider {
  async getCurrentLocation(): Promise<ChatLocation> {
    const permission = await Location.requestForegroundPermissionsAsync();
    if (!permission.granted) {
      throw new Error("Location permission was denied.");
    }

    let current: Location.LocationObject;
    try {
      current = await Location.getCurrentPositionAsync({
        accuracy: Location.Accuracy.Balanced
      });
    } catch {
      return {
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 25,
        name: "Simulator location",
        address: "San Francisco, CA",
        mapUrl: "https://maps.apple.com/?ll=37.7749,-122.4194",
        timestamp: new Date().toISOString(),
        metadata: {
          fallback: true
        }
      };
    }

    const { latitude, longitude } = current.coords;
    let address: string | undefined;

    try {
      const [place] = await Location.reverseGeocodeAsync({ latitude, longitude });
      address = formatAddress(place);
    } catch {
      address = undefined;
    }

    return {
      latitude,
      longitude,
      accuracy: current.coords.accuracy ?? undefined,
      altitude: current.coords.altitude,
      heading: current.coords.heading,
      speed: current.coords.speed,
      name: "Current location",
      address,
      mapUrl: `https://maps.apple.com/?ll=${latitude},${longitude}`,
      timestamp: new Date(current.timestamp).toISOString()
    };
  }
}

export default function App(props: NativeChatProps) {
  const mediaPickerProvider = useRef(new ExpoMediaPickerProvider());
  const locationProvider = useRef(new ExpoLocationProvider());
  const baseUrl = props.baseUrl ?? DEFAULT_BASE_URL;
  const token = props.token ?? DEFAULT_TOKEN;

  const theme: ChatTheme = useMemo(
    () => ({
      primaryColor: "#007AFF",
      backgroundColor: "#FFFFFF",
      userBubbleColor: "#007AFF",
      assistantBubbleColor: "#F2F2F7",
      textColor: "#111111",
      mutedTextColor: "#6E6E73",
      inputBackgroundColor: "#F2F2F7",
      borderColor: "#D1D1D6",
      borderRadius: 18,
      showMicrophoneButton: true,
      showMediaUploadButton: true,
      showLocationButton: true
    }),
    []
  );

  return (
    <View style={styles.container}>
      <InstaChatSDK
        baseUrl={baseUrl}
        token={token}
        historyLimit={25}
        messagePageSize={25}
        keyboardAvoidingEnabled={true}
        mediaPickerProvider={mediaPickerProvider.current}
        locationProvider={locationProvider.current}
        headerTitle={props.headerTitle ?? "Messages"}
        placeholderText={props.placeholderText ?? "Message"}
        theme={theme}
        user={{
          id: props.userId ?? "user-1",
          name: props.userName ?? "User-1: Bookshy"
        }}
      />
    </View>
  );
}

function formatAddress(place: Location.LocationGeocodedAddress): string {
  return [place.name, place.street, place.city, place.region, place.country].filter(Boolean).join(", ");
}

const styles = StyleSheet.create({
  container: {
    flex: 1
  }
});
