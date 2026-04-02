import React, { useRef } from 'react';
import { Animated, PanResponder, StyleSheet, View } from 'react-native';
import type { CropBox } from '../types';

const MIN_PX = 44;

interface Props {
  initialCrop: CropBox;
  containerW: number;
  containerH: number;
  onCommit: (c: CropBox) => void;
  accentColor: string;
  offsetX?: number;
  offsetY?: number;
}

const CropOverlay = React.memo(
  ({
    initialCrop,
    containerW,
    containerH,
    onCommit,
    accentColor,
    offsetX = 0,
    offsetY = 0,
  }: Props) => {
    const W = containerW,
      H = containerH;
    const box = useRef({
      l: initialCrop.x * W,
      t: initialCrop.y * H,
      w: initialCrop.w * W,
      h: initialCrop.h * H,
    });
    const aL = useRef(new Animated.Value(box.current.l)).current;
    const aT = useRef(new Animated.Value(box.current.t)).current;
    const aW = useRef(new Animated.Value(box.current.w)).current;
    const aH = useRef(new Animated.Value(box.current.h)).current;

    const applyBox = () => {
      const b = box.current;
      aL.setValue(b.l);
      aT.setValue(b.t);
      aW.setValue(b.w);
      aH.setValue(b.h);
    };
    const notify = () => {
      const b = box.current;
      onCommit({ x: b.l / W, y: b.t / H, w: b.w / W, h: b.h / H });
    };

    // ── Box pan (move entire selection) ─────────────────────────────────────
    const ds = useRef({ l: 0, t: 0 });
    const boxPan = useRef(
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onStartShouldSetPanResponderCapture: () => true,
        onMoveShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponderCapture: () => true,
        onPanResponderGrant: () => {
          ds.current = { l: box.current.l, t: box.current.t };
        },
        onPanResponderMove: (_, g) => {
          const { w, h } = box.current;
          box.current.l = Math.max(0, Math.min(W - w, ds.current.l + g.dx));
          box.current.t = Math.max(0, Math.min(H - h, ds.current.t + g.dy));
          aL.setValue(box.current.l);
          aT.setValue(box.current.t);
        },
        onPanResponderRelease: notify,
        onPanResponderTerminate: notify,
      })
    ).current;

    // ── Corner resize handles ────────────────────────────────────────────────
    type Corner = 'tl' | 'tr' | 'bl' | 'br';
    const rs = useRef({ l: 0, t: 0, w: 0, h: 0 });
    const mkCP = (c: Corner) =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onStartShouldSetPanResponderCapture: () => true,
        onMoveShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponderCapture: () => true,
        onPanResponderGrant: () => {
          rs.current = { ...box.current };
        },
        onPanResponderMove: (_, g) => {
          const s = rs.current;
          let l = s.l, t = s.t, w = s.w, h = s.h;
          if (c === 'tl') {
            l = Math.max(0, Math.min(s.l + s.w - MIN_PX, s.l + g.dx));
            t = Math.max(0, Math.min(s.t + s.h - MIN_PX, s.t + g.dy));
            w = s.l + s.w - l;
            h = s.t + s.h - t;
          }
          if (c === 'tr') {
            t = Math.max(0, Math.min(s.t + s.h - MIN_PX, s.t + g.dy));
            w = Math.max(MIN_PX, Math.min(W - s.l, s.w + g.dx));
            h = s.t + s.h - t;
          }
          if (c === 'bl') {
            l = Math.max(0, Math.min(s.l + s.w - MIN_PX, s.l + g.dx));
            w = s.l + s.w - l;
            h = Math.max(MIN_PX, Math.min(H - s.t, s.h + g.dy));
          }
          if (c === 'br') {
            w = Math.max(MIN_PX, Math.min(W - s.l, s.w + g.dx));
            h = Math.max(MIN_PX, Math.min(H - s.t, s.h + g.dy));
          }
          box.current = { l, t, w, h };
          applyBox();
        },
        onPanResponderRelease: notify,
        onPanResponderTerminate: notify,
      });

    const tlP = useRef(mkCP('tl')).current;
    const trP = useRef(mkCP('tr')).current;
    const blP = useRef(mkCP('bl')).current;
    const brP = useRef(mkCP('br')).current;

    const HS = 32, BW = 3, BL = 22;

    return (
      <View
        style={[
          StyleSheet.absoluteFill,
          {
            left: offsetX,
            top: offsetY,
            right: undefined,
            bottom: undefined,
            width: W,
            height: H,
          },
        ]}
        pointerEvents="box-none"
      >
        {/* Vignette overlays */}
        <Animated.View style={[s.vig, { top: 0, left: 0, right: 0, height: aT }]} />
        <Animated.View style={[s.vig, { top: Animated.add(aT, aH), left: 0, right: 0, bottom: 0 }]} />
        <Animated.View style={[s.vig, { top: aT, left: 0, width: aL, height: aH }]} />
        <Animated.View style={[s.vig, { top: aT, left: Animated.add(aL, aW), right: 0, height: aH }]} />

        {/* Selection box with grid */}
        <Animated.View
          style={[s.box, { left: aL, top: aT, width: aW, height: aH, borderColor: accentColor }]}
          {...boxPan.panHandlers}
        >
          <View style={[s.grid, { top: '33%', left: 0, right: 0, height: 1 }]} />
          <View style={[s.grid, { top: '66%', left: 0, right: 0, height: 1 }]} />
          <View style={[s.grid, { left: '33%', top: 0, bottom: 0, width: 1 }]} />
          <View style={[s.grid, { left: '66%', top: 0, bottom: 0, width: 1 }]} />
          {(['tl', 'tr', 'bl', 'br'] as Corner[]).map((c) => {
            const iT = c[0] === 't', iL = c[1] === 'l';
            return (
              <React.Fragment key={c}>
                <View style={{ position: 'absolute', [iT ? 'top' : 'bottom']: 0, [iL ? 'left' : 'right']: 0, width: BL, height: BW, backgroundColor: accentColor }} />
                <View style={{ position: 'absolute', [iT ? 'top' : 'bottom']: 0, [iL ? 'left' : 'right']: 0, width: BW, height: BL, backgroundColor: accentColor }} />
              </React.Fragment>
            );
          })}
        </Animated.View>

        {/* Corner handles (larger hit area) */}
        {[
          { pos: { left: Animated.subtract(aL, HS / 2), top: Animated.subtract(aT, HS / 2) }, p: tlP },
          { pos: { left: Animated.subtract(Animated.add(aL, aW), HS / 2), top: Animated.subtract(aT, HS / 2) }, p: trP },
          { pos: { left: Animated.subtract(aL, HS / 2), top: Animated.subtract(Animated.add(aT, aH), HS / 2) }, p: blP },
          { pos: { left: Animated.subtract(Animated.add(aL, aW), HS / 2), top: Animated.subtract(Animated.add(aT, aH), HS / 2) }, p: brP },
        ].map((h, i) => (
          <Animated.View
            key={i}
            style={[s.handle, { width: HS, height: HS, ...h.pos, borderColor: accentColor }]}
            {...h.p.panHandlers}
          />
        ))}
      </View>
    );
  }
);

const s = StyleSheet.create({
  vig: { position: 'absolute', backgroundColor: 'rgba(0,0,0,0.55)' },
  box: { position: 'absolute', borderWidth: 1.5 },
  grid: { position: 'absolute', backgroundColor: 'rgba(255,255,255,0.15)' },
  handle: {
    position: 'absolute',
    borderRadius: 6,
    backgroundColor: 'rgba(255,255,255,0.12)',
    borderWidth: 2.5,
  },
});

export default CropOverlay;
