export const T = {
  bg: '#000000',
  surface: '#1C1C1E',
  card: '#2C2C2E',
  border: '#3A3A3C',
  accent: '#FF3B30',
  accentDim: '#FF3B3022',
  green: '#34C759',
  orange: '#FF9500',
  teal: '#5AC8FA',
  text: '#FFFFFF',
  textSub: '#EBEBF5CC',
  textMuted: '#EBEBF599',
  handleBg: '#FFFFFF',
  timelineB: '#1C1C1E',
};

export const fmtSize = (n: number) =>
  n > 1024 * 1024
    ? (n / 1024 / 1024).toFixed(1) + ' MB'
    : (n / 1024).toFixed(0) + ' KB';

export const fmtSec = (ms: number) => {
  const s = Math.max(0, ms / 1000);
  if (s < 60) return s.toFixed(1) + 's';
  const m = Math.floor(s / 60),
    sec = s % 60;
  return `${m}:${sec.toFixed(1).padStart(4, '0')}`;
};

export const fmtMs = (ms: number) => (ms / 1000).toFixed(1) + 's';
