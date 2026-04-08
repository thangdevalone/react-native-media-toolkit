import { Ionicons } from '@expo/vector-icons';
import { useVideoPlayer, VideoView } from 'expo-video';
import React, { useEffect } from 'react';
import {
  ActivityIndicator,
  StatusBar,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import CropOverlay from '../components/CropOverlay';
import VideoTrimBar from '../components/VideoTrimBar';
import { T } from '../theme';
import type { CropBox } from '../types';

interface Props {
  srcUri: string;
  durationMs: number;
  tcCrop: CropBox;
  tcPrevSz: { w: number; h: number };
  tcVidNat: { w: number; h: number };
  loading: boolean;
  opLabel: string;
  onBack: () => void;
  onApply: (startMs: number, endMs: number) => void;
  onLayout: (w: number, h: number) => void;
  onNatSize: (w: number, h: number) => void;
  onCropCommit: (c: CropBox) => void;
  getContainRect: (nW: number, nH: number, cW: number, cH: number) => { x: number; y: number; w: number; h: number };
}

export default function TrimAndCropVideoScreen({
  srcUri, durationMs, tcCrop, tcPrevSz, tcVidNat, loading, opLabel,
  onBack, onApply, onLayout, onNatSize, onCropCommit, getContainRect,
}: Props) {
  const trimBarRef = React.useRef<{ getRange: () => { startMs: number; endMs: number } } | null>(null);
  const player = useVideoPlayer(srcUri, p => { p.loop = true; p.play(); });
  
  useEffect(() => {
    // Polling for video dimensions as expo-video loads them async
    const itv = setInterval(() => {
      if (player.videoTrack?.size?.width && player.videoTrack.size.width > 0) {
        onNatSize(player.videoTrack.size.width, player.videoTrack.size.height);
        clearInterval(itv);
      }
    }, 100);
    return () => clearInterval(itv);
  }, [player, onNatSize]);

  return (
    <View style={s.root}>
      <StatusBar barStyle="light-content" backgroundColor="#000" translucent={false} />
      <SafeAreaView style={s.safe}>
        <View style={s.header}>
          <TouchableOpacity style={s.backBtn} onPress={onBack}>
            <Ionicons name="chevron-back" size={24} color={T.text} />
          </TouchableOpacity>
          <Text style={s.title}>TRIM + CROP</Text>
          <TouchableOpacity
            style={s.nextBtn}
            onPress={() => {
              const range = trimBarRef.current?.getRange() ?? { startMs: 0, endMs: durationMs };
              onApply(range.startMs, range.endMs);
            }}
          >
            <Text style={s.nextTxt}>Apply</Text>
          </TouchableOpacity>
        </View>

        {/* Video preview with crop overlay */}
        <View
          style={{ flex: 1 }}
          onLayout={(e) => onLayout(e.nativeEvent.layout.width, e.nativeEvent.layout.height)}
        >
          <VideoView
            player={player}
            style={StyleSheet.absoluteFill}
            contentFit="contain"
            nativeControls
          />
          {tcPrevSz.w > 0 && tcVidNat.w > 0 && (() => {
            const vr = getContainRect(tcVidNat.w, tcVidNat.h, tcPrevSz.w, tcPrevSz.h);
            return (
              <CropOverlay
                initialCrop={tcCrop}
                containerW={vr.w}
                containerH={vr.h}
                offsetX={vr.x}
                offsetY={vr.y}
                onCommit={(c) => onCropCommit({
                  x: (c.x * vr.w + vr.x) / tcPrevSz.w,
                  y: (c.y * vr.h + vr.y) / tcPrevSz.h,
                  w: (c.w * vr.w) / tcPrevSz.w,
                  h: (c.h * vr.h) / tcPrevSz.h,
                })}
                accentColor="#FF9500"
              />
            );
          })()}
          {/* Hint */}
          <View style={s.hintWrap} pointerEvents="none">
            <View style={s.hintBg}>
              <Text style={s.hintTxt}>Drag corners to select crop region</Text>
            </View>
          </View>
        </View>

        <VideoTrimBar
          videoUri={srcUri}
          durationMs={durationMs}
          trimBarRef={trimBarRef}
          onSeek={() => {}}
        />

        {loading && (
          <View style={s.loadingOverlay}>
            <ActivityIndicator size="large" color="#FFF" />
            <Text style={s.loadingTxt}>{opLabel || 'Processing...'}</Text>
          </View>
        )}
      </SafeAreaView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000' },
  safe: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 12, paddingVertical: 8 },
  backBtn: { padding: 8 },
  title: { color: '#EBEBF5CC', fontSize: 14, fontWeight: '600', letterSpacing: 1 },
  nextBtn: { backgroundColor: T.accent, borderRadius: 20, paddingHorizontal: 20, paddingVertical: 8 },
  nextTxt: { color: '#fff', fontWeight: '700', fontSize: 15 },
  hintWrap: { position: 'absolute', bottom: 8, left: 0, right: 0, alignItems: 'center' },
  hintBg: { backgroundColor: 'rgba(0,0,0,0.55)', paddingHorizontal: 12, paddingVertical: 4, borderRadius: 8 },
  hintTxt: { color: '#fff', fontSize: 12, fontWeight: '600' },
  loadingOverlay: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.78)', alignItems: 'center', justifyContent: 'center', zIndex: 99 },
  loadingTxt: { color: 'rgba(255,255,255,0.7)', fontSize: 14, marginTop: 14 },
});
