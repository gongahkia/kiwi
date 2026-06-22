export interface RecordingEvent {
  time: number;
  output: string;
}

export interface Recording {
  format: "cast" | "ansi";
  cols: number;
  rows: number;
  duration: number;
  events: RecordingEvent[];
}

export interface ParseOptions {
  format?: "auto" | "cast" | "ansi";
  cols?: number | string;
  rows?: number | string;
}

export class AnsiScreen {
  cols: number;
  rows: number;
  cursor: { row: number; col: number };
  constructor(cols?: number, rows?: number);
  resize(cols?: number, rows?: number): this;
  resetStyle(): void;
  clear(): void;
  clearLine(row: number, from?: number, to?: number): void;
  scrollUp(): void;
  putChar(ch: string): void;
  newline(): void;
  applySgr(params: number[]): void;
  applyCsi(raw: string, final: string): void;
  write(input: string): this;
  toHtml(): string;
}

export function parseCast(text: string): Recording;
export function parseAnsi(text: string, options?: ParseOptions): Recording;
export function parseRecording(text: string, options?: ParseOptions): Recording;
export function renderRecordingFrame(recording: Recording, time?: number): AnsiScreen;
export function recordingToHtml(recording: Recording, time?: number): string;

export class ContourttyPlayerElement extends HTMLElement {
  readonly duration: number;
  currentTime: number;
  readonly speed: number;
  reload(): Promise<void>;
  load(text: string, options?: ParseOptions): Promise<void>;
  renderAt(time: number): void;
  play(): void;
  pause(): void;
  seek(time: number): void;
}

export function defineContourttyPlayer(tagName?: string): typeof ContourttyPlayerElement | undefined;
