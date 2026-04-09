import { Ionicons } from '@expo/vector-icons';
import { VideoView, type VideoPlayer } from 'expo-video';
import { useEffect } from 'react';
import {
  ActivityIndicator,
  StatusBar,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MediaToolkit } from 'react-native-media-toolkit';
import CropOverlay from '../components/CropOverlay';
import { T } from '../theme';
import type { CropBox } from '../types';

interface Props {
  player: VideoPlayer | null;
  srcUri: string;
  vcrop: CropBox;
  vPrevSz: { w: number; h: number };
  vidNat: { w: number; h: number };
  loading: boolean;
  opLabel: string;
  onBack: () => void;
  onApply: () => void;
  onLayout: (w: number, h: number) => void;
  onNatSize: (w: number, h: number) => void;
  onCropCommit: (c: CropBox) => void;
  getContainRect: (nW: number, nH: number, cW: number, cH: number) => { x: number; y: number; w: number; h: number };
}

export default function CropVideoScreen({
  player, srcUri, vcrop, vPrevSz, vidNat, loading, opLabel,
  onBack, onApply, onLayout, onNatSize, onCropCommit, getContainRect,
}: Props) {
  useEffect(() => {
    if (player) {
      player.loop = true;
      player.play();
    }
  }, [player]);
  
  useEffect(() => {
    let active = true;
    MediaToolkit.getThumbnail(srcUri, { timeMs: 0 })
      .then((res) => {
        if (active && res.width > 0 && res.height > 0) {
          onNatSize(res.width, res.height);
        }
      })
      .catch((err) => {
        console.warn('Failed to get thumbnail for dimension detection:', err);
      });
    return () => {
      active = false;
    };
  }, [srcUri, onNatSize]);

  return (
    <View style={{ flex: 1, backgroundColor: '#000' }}>
      <StatusBar barStyle="light-content" backgroundColor="#000" translucent={false} />
      <SafeAreaView style={{ flex: 1 }}>
        <View style={s.header}>
          <TouchableOpacity style={s.backBtn} onPress={onBack}>
            <Ionicons name="chevron-back" size={24} color={T.text} />
          </TouchableOpacity>
          <Text style={s.title}>CROP VIDEO</Text>
          <TouchableOpacity style={s.nextBtn} onPress={onApply}>
            <Text style={s.nextTxt}>Apply</Text>
          </TouchableOpacity>
        </View>

        <View
          style={{ flex: 1 }}
          onLayout={(e) => onLayout(e.nativeEvent.layout.width, e.nativeEvent.layout.height)}
        >
          <VideoView
            player={player}
            style={StyleSheet.absoluteFill}
            contentFit="contain"
            nativeControls={false}
          />
          {vPrevSz.w > 0 && vidNat.w > 0 && (
            <CropOverlay
              initialCrop={vcrop}
              containerW={getContainRect(vidNat.w, vidNat.h, vPrevSz.w, vPrevSz.h).w}
              containerH={getContainRect(vidNat.w, vidNat.h, vPrevSz.w, vPrevSz.h).h}
              offsetX={getContainRect(vidNat.w, vidNat.h, vPrevSz.w, vPrevSz.h).x}
              offsetY={getContainRect(vidNat.w, vidNat.h, vPrevSz.w, vPrevSz.h).y}
              onCommit={(c) => {
                const vr = getContainRect(vidNat.w, vidNat.h, vPrevSz.w, vPrevSz.h);
                onCropCommit({
                  x: (c.x * vr.w + vr.x) / vPrevSz.w,
                  y: (c.y * vr.h + vr.y) / vPrevSz.h,
                  w: (c.w * vr.w) / vPrevSz.w,
                  h: (c.h * vr.h) / vPrevSz.h,
                });
              }}
              accentColor={T.accent}
            />
          )}
        </View>

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
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 12, paddingVertical: 8 },
  backBtn: { padding: 8 },
  title: { color: '#EBEBF5CC', fontSize: 14, fontWeight: '600', letterSpacing: 1 },
  nextBtn: { backgroundColor: T.accent, borderRadius: 20, paddingHorizontal: 20, paddingVertical: 8 },
  nextTxt: { color: '#fff', fontWeight: '700', fontSize: 15 },
  loadingOverlay: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.78)', alignItems: 'center', justifyContent: 'center', zIndex: 99 },
  loadingTxt: { color: 'rgba(255,255,255,0.7)', fontSize: 14, marginTop: 14 },
});
