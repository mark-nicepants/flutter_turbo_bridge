export type EventCategory =
  | 'network'
  | 'log'
  | 'navigation'
  | 'error'
  | 'bridge';

export type EventStatus = 'ok' | 'warn' | 'failed';

/** Normalized timeline event, regardless of where it originated. */
export interface TimelineEvent {
  /** Stable id `category:rawId`, used as the React-style key. */
  id: string;
  category: EventCategory;
  /** Epoch milliseconds. */
  timestamp: number;
  /** Optional duration in ms (network calls). */
  durationMs?: number;
  /** Short label shown on the pill. */
  label: string;
  status: EventStatus;
  /** True while a network call is in flight (started, no response yet).
   *  Rendered as a growing, pulsing yellow bar. */
  inFlight?: boolean;
  /** Original payload, kept for the detail panel. */
  raw: Record<string, unknown>;
}

export interface CategoryDef {
  key: EventCategory;
  label: string;
  iconSvg: string;
}
