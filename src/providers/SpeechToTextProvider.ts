export interface SpeechToTextProvider {
  transcribe(audioUri: string): Promise<string>;
}
