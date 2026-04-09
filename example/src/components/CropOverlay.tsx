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
      r: W - (initialCrop.x + initialCrop.w) * W,
      b: H - (initialCrop.y + initialCrop.h) * H,
    });
    const aL = useRef(new Animated.Value(box.current.l)).current;
    const aT = useRef(new Animated.Value(box.current.t)).current;
    const aR = useRef(new Animated.Value(box.current.r)).current;
    const aB = useRef(new Animated.Value(box.current.b)).current;

    const applyBox = () => {
      const b = box.current;
      aL.setValue(b.l);
      aT.setValue(b.t);
      aR.setValue(b.r);
      aB.setValue(b.b);
    };
    const notify = () => {
      const b = box.current;
      onCommit({ x: b.l / W, y: b.t / H, w: (W - b.l - b.r) / W, h: (H - b.t - b.b) / H });
    };

    // ── Box pan (move entire selection) ─────────────────────────────────────
    const ds = useRef({ l: 0, t: 0, r: 0, b: 0 });
    const boxPan = useRef(
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onStartShouldSetPanResponderCapture: () => true,
        onMoveShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponderCapture: () => true,
        onPanResponderGrant: () => {
          ds.current = { ...box.current };
        },
        onPanResponderMove: (_, g) => {
          const { l, t, r, b } = ds.current;
          const minDx = -l; // max left
          const maxDx = r;  // max right
          const dx = Math.max(minDx, Math.min(maxDx, g.dx));
          const minDy = -t; // max up
          const maxDy = b;  // max down
          const dy = Math.max(minDy, Math.min(maxDy, g.dy));
          
          box.current.l = l + dx;
          box.current.t = t + dy;
          box.current.r = r - dx;
          box.current.b = b - dy;
          applyBox();
        },
        onPanResponderRelease: notify,
        onPanResponderTerminate: notify,
      })
    ).current;

    // ── Corner resize handles ────────────────────────────────────────────────
    type Corner = 'tl' | 'tr' | 'bl' | 'br';
    const rs = useRef({ l: 0, t: 0, r: 0, b: 0 });
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
          let { l, t, r, b } = s;
          if (c === 'tl') {
            l = Math.max(0, Math.min(W - r - MIN_PX, s.l + g.dx));
            t = Math.max(0, Math.min(H - b - MIN_PX, s.t + g.dy));
          }
          if (c === 'tr') {
            t = Math.max(0, Math.min(H - b - MIN_PX, s.t + g.dy));
            r = Math.max(0, Math.min(W - l - MIN_PX, s.r - g.dx));
          }
          if (c === 'bl') {
            l = Math.max(0, Math.min(W - r - MIN_PX, s.l + g.dx));
            b = Math.max(0, Math.min(H - t - MIN_PX, s.b - g.dy));
          }
          if (c === 'br') {
            r = Math.max(0, Math.min(W - l - MIN_PX, s.r - g.dx));
            b = Math.max(0, Math.min(H - t - MIN_PX, s.b - g.dy));
          }
          box.current = { l, t, r, b };
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
        <Animated.View style={[s.vig, { bottom: 0, left: 0, right: 0, height: aB }]} />
        <Animated.View style={[s.vig, { top: aT, bottom: aB, left: 0, width: aL }]} />
        <Animated.View style={[s.vig, { top: aT, bottom: aB, right: 0, width: aR }]} />

        {/* Selection box with grid */}
        <Animated.View
          style={[s.box, { left: aL, top: aT, right: aR, bottom: aB, borderColor: accentColor }]}
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
          { pos: { left: aL, top: aT, marginLeft: -HS / 2, marginTop: -HS / 2 }, p: tlP },
          { pos: { right: aR, top: aT, marginRight: -HS / 2, marginTop: -HS / 2 }, p: trP },
          { pos: { left: aL, bottom: aB, marginLeft: -HS / 2, marginBottom: -HS / 2 }, p: blP },
          { pos: { right: aR, bottom: aB, marginRight: -HS / 2, marginBottom: -HS / 2 }, p: brP },
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
