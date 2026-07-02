import type { ChatLocation } from "../types/location";

export interface LocationProvider {
  getCurrentLocation(): Promise<ChatLocation>;
}
