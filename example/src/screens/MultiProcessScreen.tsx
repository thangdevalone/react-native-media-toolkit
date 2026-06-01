import { Ionicons } from '@expo/vector-icons';
import { VideoView, type VideoPlayer } from 'expo-video';
import { useState, useEffect, useRef } from 'react';
import {
  ActivityIndicator,
  Image,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MediaToolkit } from 'react-native-media-toolkit';
import CropOverlay from '../components/CropOverlay';
import VideoTrimBar from '../components/VideoTrimBar';
import { T } from '../theme';
import type { CropBox } from '../types';

const DEF_CROP: CropBox = { x: 0, y: 0, w: 1, h: 1 };

const getContainRect = (natW: number, natH: number, containerW: number, containerH: number) => {
  if (natW <= 0 || natH <= 0 || containerW <= 0 || containerH <= 0) return { x: 0, y: 0, w: containerW, h: containerH };
  const scale = Math.min(containerW / natW, containerH / natH);
  const w = natW * scale, h = natH * scale;
  return { x: (containerW - w) / 2, y: (containerH - h) / 2, w, h };
};

interface Props {
  srcUri: string;
  srcType: 'image' | 'video';
  durationMs: number;
  player: VideoPlayer | null;
  loading: boolean;
  opLabel: string;
  onBack: () => void;
  onApply: (opts: {
    startMs: number;
    endMs: number;
    cropX: number;
    cropY: number;
    cropW: number;
    cropH: number;
    flip?: string;
    rotation: number;
    lutUri?: string;
  }) => void;
}

const LUTS = [
  { id: 'none', label: 'No LUT', source: null },
  { id: 'lut1', label: 'Beauty 1', source: require('../assets/luts/SY-Beauty_Portrait-1.png') },
  { id: 'lut2', label: 'Beauty 2', source: require('../assets/luts/SY-Beauty_Portrait-2.png') },
  { id: 'lut3', label: 'Beauty 3', source: require('../assets/luts/SY-Beauty_Portrait-3.png') },
  { id: 'lut4', label: 'Beauty 4', source: require('../assets/luts/SY-Beauty_Portrait-4.png') },
  { id: 'lut5', label: 'Beauty 5', source: require('../assets/luts/SY-Beauty_Portrait-5.png') },
  { id: 'lut6', label: 'Beauty 6', source: require('../assets/luts/SY-Beauty_Portrait-6.png') },
  { id: 'lut7', label: 'Beauty 7', source: require('../assets/luts/SY-Beauty_Portrait-7.png') },
  { id: 'lut8', label: 'Beauty 8', source: require('../assets/luts/SY-Beauty_Portrait-8.png') },
  { id: 'lut9', label: 'Beauty 9', source: require('../assets/luts/SY-Beauty_Portrait-9.png') },
  { id: 'lut10', label: 'Beauty 10', source: require('../assets/luts/SY-Beauty_Portrait-10.png') },
  { id: 'lut11', label: 'Beauty 11', source: require('../assets/luts/SY-Beauty_Portrait-11.png') },
  { id: 'lut12', label: 'Beauty 12', source: require('../assets/luts/SY-Beauty_Portrait-12.png') },
  { id: 'lut13', label: 'Beauty 13', source: require('../assets/luts/SY-Beauty_Portrait-13.png') },
  { id: 'lut14', label: 'Beauty 14', source: require('../assets/luts/SY-Beauty_Portrait-14.png') },
  { id: 'lut15', label: 'Beauty 15', source: require('../assets/luts/SY-Beauty_Portrait-15.png') },
  { id: 'lut16', label: 'Beauty 16', source: require('../assets/luts/SY-Beauty_Portrait-16.png') },
  { id: 'lut17', label: 'Beauty 17', source: require('../assets/luts/SY-Beauty_Portrait-17.png') },
  { id: 'lut18', label: 'Beauty 18', source: require('../assets/luts/SY-Beauty_Portrait-18.png') },
];

export default function MultiProcessScreen({
  srcUri, srcType, durationMs, player, loading, opLabel, onBack, onApply,
}: Props) {
  // Transform State
  const [rotation, setRotation] = useState(0);
  const [flip, setFlip] = useState<'none' | 'horizontal' | 'vertical'>('none');
  const [selectedLut, setSelectedLut] = useState<string>('none');
  
  // Crop State
  const [cropBox, setCropBox] = useState<CropBox>(DEF_CROP);
  const [resetKey, setResetKey] = useState(0);
  
  // Trim State
  const trimBarRef = useRef<{ getRange: () => { startMs: number; endMs: number } } | null>(null);
  const [playheadPos, setPlayheadPos] = useState(0);

  // Dimensions
  const [natSz, setNatSz] = useState({ w: 0, h: 0 });
  const [prevSz, setPrevSz] = useState({ w: 0, h: 0 });

  // Preview State
  const [previewUri, setPreviewUri] = useState<string | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [basePreviewUri, setBasePreviewUri] = useState<string>(srcUri); // Holds thumbnail for video

  useEffect(() => {
    let isCancelled = false;
    
    if (selectedLut === 'none') {
      setPreviewUri(null);
      return;
    }
    
    const applyPreview = async () => {
      setPreviewLoading(true);
      if (player && player.playing) player.pause();
      try {
        let currentBase = basePreviewUri;
        // If it's a video and we haven't extracted a thumbnail yet
        if (srcType === 'video' && currentBase === srcUri) {
           const timeMs = player ? player.currentTime * 1000 : 0;
           const thumb = await MediaToolkit.getThumbnail(srcUri, { timeMs, quality: 100 });
           currentBase = thumb.uri;
           if (!isCancelled) setBasePreviewUri(currentBase);
        }
        
        const lutObj = LUTS.find(l => l.id === selectedLut);
        if (lutObj && lutObj.source) {
          const lutUri = Image.resolveAssetSource(lutObj.source as any)?.uri;
          const res = await MediaToolkit.processImage(currentBase, {
            lutUri,
          });
          if (!isCancelled) setPreviewUri(res.uri);
        }
      } catch (e) {
        console.warn('Preview error:', e);
      } finally {
        if (!isCancelled) setPreviewLoading(false);
      }
    };
    
    applyPreview();
    
    return () => { isCancelled = true; };
  }, [selectedLut, basePreviewUri, srcType, srcUri, player]);

  useEffect(() => {
    let active = true;
    if (srcType === 'video') {
      MediaToolkit.getThumbnail(srcUri, { timeMs: 0 })
        .then((res) => { if (active && res.width) setNatSz({ w: res.width, h: res.height }); })
        .catch(() => {});
    } else {
      Image.getSize(
        srcUri, 
        (w, h) => { if (active) setNatSz({ w, h }); },
        (e) => { console.warn('getSize err:', e); if (active) setNatSz({ w: 1000, h: 1000 }); }
      );
    }
    return () => { active = false; };
  }, [srcUri, srcType]);

  useEffect(() => {
    if (player) {
      player.loop = true;
      player.play();
    }
  }, [player]);

  useEffect(() => {
    if (srcType !== 'video') return;
    const itv = setInterval(() => {
      if (player && durationMs > 0) setPlayheadPos((player.currentTime * 1000) / durationMs);
    }, 100);
    return () => clearInterval(itv);
  }, [player, durationMs, srcType]);

  const handleSeek = (ms: number) => {
    if (player) player.currentTime = ms / 1000;
  };

  const applyChanges = () => {
    let startMs = 0;
    let endMs = durationMs;
    if (srcType === 'video' && trimBarRef.current) {
      const r = trimBarRef.current.getRange();
      startMs = r.startMs;
      endMs = r.endMs;
    }
    
    // Map visual cropBox back to original unrotated image coordinates
    let { x, y, w, h } = cropBox;
    
    // Un-flip
    if (flip === 'horizontal') x = 1 - x - w;
    if (flip === 'vertical') y = 1 - y - h;

    // Un-rotate
    const rot = ((rotation % 360) + 360) % 360; // Normalize to positive degrees
    let ox = x, oy = y, ow = w, oh = h;
    if (rot === 90) {
      ox = y;
      oy = 1 - x - w;
      ow = h;
      oh = w;
    } else if (rot === 180) {
      ox = 1 - x - w;
      oy = 1 - y - h;
    } else if (rot === 270) {
      ox = 1 - y - h;
      oy = x;
      ow = h;
      oh = w;
    }

    onApply({
      startMs, endMs,
      cropX: ox, cropY: oy, cropW: ow, cropH: oh,
      flip: flip === 'none' ? undefined : flip,
      rotation,
      lutUri: selectedLut !== 'none' ? Image.resolveAssetSource(LUTS.find(l => l.id === selectedLut)?.source as any)?.uri : undefined,
    });
  };

  // Calculate dynamic dimensions for visual rotation
  const isRot = Math.abs(rotation) % 180 !== 0;
  const vNatW = isRot ? natSz.h : natSz.w;
  const vNatH = isRot ? natSz.w : natSz.h;
  const vr = getContainRect(vNatW, vNatH, prevSz.w, prevSz.h);

  return (
    <View style={s.root}>
      <SafeAreaView style={s.safe}>
        {/* Header */}
        <View style={s.header}>
          <TouchableOpacity style={s.backBtn} onPress={onBack}>
            <Ionicons name="close" size={28} color="#FFF" />
          </TouchableOpacity>
          <Text style={s.title}>EDITOR</Text>
          <TouchableOpacity style={s.applyBtn} onPress={applyChanges}>
            <Ionicons name="checkmark" size={28} color={T.teal} />
          </TouchableOpacity>
        </View>

        {/* Preview Area */}
        <View 
          style={s.previewWrapper} 
          onLayout={(e) => setPrevSz({ w: e.nativeEvent.layout.width, h: e.nativeEvent.layout.height })}
        >
          {natSz.w > 0 && prevSz.w > 0 && (
            <View style={[StyleSheet.absoluteFill, { overflow: 'hidden', alignItems: 'center', justifyContent: 'center' }]}>
              <View style={{ width: vr.w, height: vr.h, alignItems: 'center', justifyContent: 'center' }}>
                {/* Transformed Image Container */}
                <View style={{ 
                  width: isRot ? vr.h : vr.w, 
                  height: isRot ? vr.w : vr.h, 
                  transform: [
                    { rotate: `${rotation}deg` }, 
                    { scaleX: flip === 'horizontal' ? -1 : 1 }, 
                    { scaleY: flip === 'vertical' ? -1 : 1 }
                  ]
                }}>
                  {previewUri ? (
                    <Image source={{ uri: previewUri }} style={StyleSheet.absoluteFill} resizeMode="stretch" />
                  ) : (srcType === 'video' && player ? (
                    <VideoView player={player} style={StyleSheet.absoluteFill} contentFit="fill" nativeControls={false} />
                  ) : (
                    <Image source={{ uri: srcUri }} style={StyleSheet.absoluteFill} resizeMode="stretch" />
                  ))}
                </View>

                {previewLoading && (
                  <View style={[StyleSheet.absoluteFill, { backgroundColor: 'rgba(0,0,0,0.3)', alignItems: 'center', justifyContent: 'center' }]}>
                    <ActivityIndicator size="small" color="#FFF" />
                  </View>
                )}

                {/* Constant Crop Overlay mapping to visual bounds */}
                <CropOverlay
                  key={`crop-${resetKey}-${rotation}-${flip}`}
                  initialCrop={cropBox}
                  containerW={vr.w} containerH={vr.h}
                  onCommit={(c) => setCropBox(c)}
                  accentColor={T.teal}
                />
              </View>
            </View>
          )}
        </View>

        {/* Unified Tools Area */}
        <View style={s.toolsArea}>
          {srcType === 'video' && (
            <View style={{ marginBottom: 16, paddingHorizontal: 24 }}>
              <VideoTrimBar
                videoUri={srcUri}
                durationMs={durationMs}
                trimBarRef={trimBarRef}
                onSeek={handleSeek}
                playheadPos={playheadPos}
              />
            </View>
          )}

          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.toolbar}>
            <TouchableOpacity style={s.toolBtn} onPress={() => {
               setCropBox(DEF_CROP);
               setResetKey(k => k + 1);
            }}>
              <Ionicons name="crop" size={24} color="#FFF" />
              <Text style={s.toolLbl}>Reset Crop</Text>
            </TouchableOpacity>

            <View style={s.div} />

            <TouchableOpacity style={s.toolBtn} onPress={() => {
              setRotation(r => r - 90);
              setCropBox(c => ({ x: c.y, y: 1 - c.x - c.w, w: c.h, h: c.w }));
            }}>
              <Ionicons name="refresh" size={24} color="#FFF" style={{ transform: [{ scaleX: -1 }] }} />
              <Text style={s.toolLbl}>Rotate L</Text>
            </TouchableOpacity>

            <TouchableOpacity style={s.toolBtn} onPress={() => {
              setRotation(r => r + 90);
              setCropBox(c => ({ x: 1 - c.y - c.h, y: c.x, w: c.h, h: c.w }));
            }}>
              <Ionicons name="refresh" size={24} color="#FFF" />
              <Text style={s.toolLbl}>Rotate R</Text>
            </TouchableOpacity>

            <View style={s.div} />

            <TouchableOpacity style={[s.toolBtn, flip === 'horizontal' && s.toolActive]} onPress={() => {
              setFlip(f => f === 'horizontal' ? 'none' : 'horizontal');
              setCropBox(c => ({ ...c, x: 1 - c.x - c.w }));
            }}>
              <Ionicons name="swap-horizontal" size={24} color={flip === 'horizontal' ? T.teal : '#FFF'} />
              <Text style={[s.toolLbl, flip === 'horizontal' && {color: T.teal}]}>Flip H</Text>
            </TouchableOpacity>

            <TouchableOpacity style={[s.toolBtn, flip === 'vertical' && s.toolActive]} onPress={() => {
              setFlip(f => f === 'vertical' ? 'none' : 'vertical');
              setCropBox(c => ({ ...c, y: 1 - c.y - c.h }));
            }}>
              <Ionicons name="swap-vertical" size={24} color={flip === 'vertical' ? T.teal : '#FFF'} />
              <Text style={[s.toolLbl, flip === 'vertical' && {color: T.teal}]}>Flip V</Text>
            </TouchableOpacity>
          </ScrollView>

          {/* LUT Selector */}
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={[s.toolbar, { marginTop: 16 }]}>
            <Text style={{ color: '#FFF', fontSize: 12, fontWeight: 'bold', marginRight: 8 }}>LUTs:</Text>
            {LUTS.map((lut) => (
              <TouchableOpacity 
                key={lut.id}
                style={[s.lutBtn, selectedLut === lut.id && s.toolActive]}
                onPress={() => setSelectedLut(lut.id)}
              >
                <Text style={[s.toolLbl, selectedLut === lut.id && {color: T.teal}, {marginTop: 0}]}>{lut.label}</Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
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
  root: { flex: 1, backgroundColor: '#000' },
  safe: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 12, paddingVertical: 8 },
  backBtn: { padding: 8 },
  applyBtn: { padding: 8 },
  title: { color: '#FFF', fontSize: 16, fontWeight: '800', letterSpacing: 1 },
  
  previewWrapper: { flex: 1, backgroundColor: '#111', margin: 16 },

  toolsArea: { paddingVertical: 16, paddingBottom: 24 },
  toolbar: { paddingHorizontal: 24, alignItems: 'center', gap: 12 },
  toolBtn: { alignItems: 'center', justifyContent: 'center', padding: 8, minWidth: 64 },
  toolActive: { backgroundColor: 'rgba(50, 215, 75, 0.15)', borderRadius: 12 },
  toolLbl: { color: '#8E8E93', fontSize: 11, fontWeight: '600', marginTop: 6, textAlign: 'center' },
  div: { width: 1, height: 32, backgroundColor: '#333', marginHorizontal: 4 },
  lutBtn: { paddingHorizontal: 12, paddingVertical: 8, borderRadius: 16, backgroundColor: '#222' },

  loadingOverlay: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.85)', alignItems: 'center', justifyContent: 'center', zIndex: 99 },
  loadingTxt: { color: '#FFF', fontSize: 14, marginTop: 14, fontWeight: '600' },
});
