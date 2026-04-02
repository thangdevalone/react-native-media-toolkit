import { Ionicons } from '@expo/vector-icons';
import * as VideoThumbnails from 'expo-video-thumbnails';
import React, { useEffect, useRef, useState } from 'react';
import { Animated, Image, Platform, StyleSheet, Text, View } from 'react-native';
import { fmtSec } from '../theme';

const HW = 22;
const BAR_H = 60;
const BORD = 3;
const FC = 16;
const MIN_SEL_PX = 30;
const TRIM_H_MARGIN = Platform.OS === 'android' ? 20 : 8;

interface Props {
  videoUri: string;
  durationMs: number;
  trimBarRef?: React.MutableRefObject<{ getRange: () => { startMs: number; endMs: number } } | null>;
  onSeek?: (ms: number) => void;
  playheadPos?: number;
}

const VideoTrimBar = ({ videoUri, durationMs, trimBarRef, onSeek, playheadPos }: Props) => {
  const trackWRef = useRef(0);
  const [trackW, setTrackW] = useState(0);

  const aPxL = useRef(new Animated.Value(0)).current;
  const aPxR = useRef(new Animated.Value(0)).current;
  const pxL = useRef(0);
  const pxR = useRef(0);

  const aTrackW = useRef(new Animated.Value(0)).current;
  const aHandleRLeft = useRef(Animated.subtract(aPxR, HW)).current;
  const aDimRW = useRef(Animated.subtract(aTrackW, aPxR)).current;
  const aInnerL = useRef(Animated.add(aPxL, HW)).current;
  const aInnerW = useRef(
    Animated.subtract(Animated.subtract(aPxR, HW), Animated.add(aPxL, HW))
  ).current;

  const [frames, setFrames] = useState<Array<string | null>>([]);
  const [startMs, setStartMs] = useState(0);
  const [endMs, setEndMs] = useState(durationMs);
  const startMsRef = useRef(0);
  const endMsRef = useRef(durationMs);

  const drag = useRef<'L' | 'R' | 'S' | null>(null);
  const lastX = useRef(0);
  const slideSelW = useRef(0);

  const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));

  const pxToMs = (px: number) =>
    clamp(Math.round((px / Math.max(1, trackWRef.current)) * durationMs), 0, durationMs);

  const init = (w: number) => {
    pxL.current = 0;
    pxR.current = w;
    aPxL.setValue(0);
    aPxR.setValue(w);
    startMsRef.current = 0;
    endMsRef.current = durationMs;
  };

  const onTrackLayout = (w: number) => {
    trackWRef.current = w;
    aTrackW.setValue(w);
    if (w > 0 && pxR.current === 0) init(w);
    setTrackW(w);
  };

  useEffect(() => {
    setStartMs(0);
    setEndMs(durationMs);
    startMsRef.current = 0;
    endMsRef.current = durationMs;
    const w = trackWRef.current;
    if (w > 0) init(w);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [durationMs]);

  useEffect(() => {
    if (!videoUri || durationMs <= 0) return;
    setFrames((prev) => Array(FC).fill(null).map((_, i) => prev[i] ?? null));
    let cancelled = false;
    (async () => {
      for (let i = 0; i < FC && !cancelled; i++) {
        try {
          const t = Math.round((i / Math.max(1, FC - 1)) * Math.max(0, durationMs - 100));
          const { uri } = await VideoThumbnails.getThumbnailAsync(videoUri, { time: t, quality: 0.4 });
          if (!cancelled && uri) setFrames((p) => { const n = [...p]; n[i] = uri; return n; });
        } catch {}
      }
    })();
    return () => { cancelled = true; };
  }, [videoUri, durationMs]);

  const getRange = () => ({
    startMs: clamp(startMsRef.current, 0, durationMs),
    endMs: clamp(endMsRef.current, 0, durationMs),
  });

  useEffect(() => { if (trimBarRef) trimBarRef.current = { getRange }; });

  // Loop within cut
  useEffect(() => {
    if (playheadPos == null || durationMs <= 0) return;
    const cur = playheadPos * durationMs;
    if (cur >= endMsRef.current && endMsRef.current > startMsRef.current) {
      onSeek?.(startMsRef.current);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playheadPos]);

  // ── Gesture handlers (uses RN core Responder system — no gesture-handler dep) ──
  const onGrant = (e: any) => {
    const x = e.nativeEvent.locationX;
    const w = trackWRef.current;
    if (w <= 0) return;
    const l = pxL.current, r = pxR.current;
    const onL = x >= l - 4 && x <= l + HW;
    const onR = x >= r - HW && x <= r + 4;
    const onS = !onL && !onR && x > l && x < r;
    if (onL && onR) {
      drag.current = Math.abs(x - (l + HW / 2)) <= Math.abs(x - (r - HW / 2)) ? 'L' : 'R';
    } else if (onL) { drag.current = 'L';
    } else if (onR) { drag.current = 'R';
    } else if (onS) {
      drag.current = 'S';
      lastX.current = x;
      slideSelW.current = r - l;
    } else { drag.current = null; }
  };

  const onMove = (e: any) => {
    if (!drag.current) return;
    const x = e.nativeEvent.locationX;
    const w = trackWRef.current;
    if (w <= 0) return;
    if (drag.current === 'L') {
      const newL = clamp(x, 0, pxR.current - MIN_SEL_PX);
      pxL.current = newL; aPxL.setValue(newL);
      const ms = pxToMs(newL);
      startMsRef.current = ms; setStartMs(ms); onSeek?.(ms);
    } else if (drag.current === 'R') {
      const newR = clamp(x, pxL.current + MIN_SEL_PX, w);
      pxR.current = newR; aPxR.setValue(newR);
      const ms = pxToMs(newR);
      endMsRef.current = ms; setEndMs(ms); onSeek?.(ms);
    } else {
      const dx = x - lastX.current;
      const sw = slideSelW.current;
      const newL = clamp(pxL.current + dx, 0, w - sw);
      const newR = newL + sw;
      pxL.current = newL; aPxL.setValue(newL);
      pxR.current = newR; aPxR.setValue(newR);
      const sMs = pxToMs(newL), eMs = pxToMs(newR);
      startMsRef.current = sMs; setStartMs(sMs);
      endMsRef.current = eMs; setEndMs(eMs);
      onSeek?.(sMs);
      lastX.current = x;
    }
  };

  const onRelease = () => {
    drag.current = null;
    const r = getRange();
    setStartMs(r.startMs);
    setEndMs(r.endMs);
  };

  const cutPh = (() => {
    if (endMsRef.current <= startMsRef.current) return pxL.current + HW;
    const cur = (playheadPos ?? 0) * durationMs;
    const frac = (cur - startMsRef.current) / (endMsRef.current - startMsRef.current);
    return clamp(
      pxL.current + HW + frac * (pxR.current - HW - (pxL.current + HW)),
      pxL.current + HW,
      pxR.current - HW
    );
  })();

  const selectedDurMs = Math.max(0, endMs - startMs);

  return (
    <View style={s.container}>
      <Text style={s.hint}>{fmtSec(selectedDurMs)}</Text>
      <View
        style={s.trackOuter}
        onLayout={(e) => onTrackLayout(e.nativeEvent.layout.width)}
        onStartShouldSetResponder={() => true}
        onStartShouldSetResponderCapture={() => true}
        onMoveShouldSetResponder={() => true}
        onMoveShouldSetResponderCapture={() => true}
        onResponderGrant={onGrant}
        onResponderMove={onMove}
        onResponderRelease={onRelease}
        onResponderTerminate={onRelease}
      >
        {/* Thumbnail strip */}
        <View pointerEvents="none" style={[s.framesRow, { height: BAR_H, width: trackW || '100%' }]}>
          {Array.from({ length: FC }).map((_, i) => (
            <View key={i} style={s.frameCell}>
              {frames[i]
                ? <Image source={{ uri: frames[i]! }} style={{ width: '100%', height: '100%' }} resizeMode="cover" />
                : <View style={{ flex: 1, backgroundColor: '#1A1A1A' }} />}
            </View>
          ))}
        </View>

        {trackW > 0 && (<>
          <Animated.View pointerEvents="none" style={[s.dimOverlay, { left: 0, width: aPxL }]} />
          <Animated.View pointerEvents="none" style={[s.dimOverlay, { left: aPxR, width: aDimRW }]} />
          <Animated.View pointerEvents="none" style={{ position: 'absolute', top: 0, height: BORD, left: aInnerL, width: aInnerW, backgroundColor: '#FFF', zIndex: 3 }} />
          <Animated.View pointerEvents="none" style={{ position: 'absolute', bottom: 0, height: BORD, left: aInnerL, width: aInnerW, backgroundColor: '#FFF', zIndex: 3 }} />
          <Animated.View pointerEvents="none" style={{ position: 'absolute', top: 0, left: aPxL, width: HW, height: BAR_H, zIndex: 10, backgroundColor: '#FFF', alignItems: 'center', justifyContent: 'center' }}>
            <Ionicons name="chevron-back" size={13} color="#1C1C1E" />
          </Animated.View>
          <Animated.View pointerEvents="none" style={{ position: 'absolute', top: 0, left: aHandleRLeft, width: HW, height: BAR_H, zIndex: 10, backgroundColor: '#FFF', alignItems: 'center', justifyContent: 'center' }}>
            <Ionicons name="chevron-forward" size={13} color="#1C1C1E" />
          </Animated.View>
          <View pointerEvents="none" style={{ position: 'absolute', top: BORD, bottom: BORD, left: cutPh - 1, width: 2, zIndex: 9, backgroundColor: '#FFF', borderRadius: 1 }} />
        </>)}
      </View>
    </View>
  );
};

const s = StyleSheet.create({
  container: {
    backgroundColor: '#000',
    paddingBottom: Platform.OS === 'ios' ? 6 : 4,
    paddingTop: 12,
  },
  hint: {
    color: '#EBEBF5CC',
    fontSize: 13,
    fontWeight: '500',
    textAlign: 'left',
    paddingHorizontal: 16,
    marginBottom: 10,
  },
  trackOuter: {
    marginHorizontal: TRIM_H_MARGIN,
    height: BAR_H,
    position: 'relative',
    borderRadius: 4,
    overflow: 'hidden',
  },
  framesRow: {
    flexDirection: 'row',
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    overflow: 'hidden',
  },
  frameCell: {
    flex: 1,
    overflow: 'hidden',
    borderRightWidth: 1,
    borderColor: 'rgba(0,0,0,0.2)',
  },
  dimOverlay: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.55)',
    zIndex: 2,
  },
});

export default VideoTrimBar;
