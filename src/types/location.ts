export interface ChatLocation {
  latitude: number;
  longitude: number;
  accuracy?: number;
  altitude?: number | null;
  heading?: number | null;
  speed?: number | null;
  name?: string;
  address?: string;
  mapUrl?: string;
  timestamp?: string;
  metadata?: Record<string, unknown>;
}
