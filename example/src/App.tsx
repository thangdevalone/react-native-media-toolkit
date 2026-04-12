import * as ImagePicker from 'expo-image-picker';
import { useVideoPlayer, VideoView } from 'expo-video';
import { Ionicons } from '@expo/vector-icons';
import React, { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Dimensions,
  Image,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
  TouchableOpacity,
} from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { MediaToolkit } from 'react-native-media-toolkit';
import type { MediaResult } from 'react-native-media-toolkit';

import ActionBtn from './components/ActionBtn';
import CropImageScreen from './screens/CropImageScreen';
import CropVideoScreen from './screens/CropVideoScreen';
import TrimAndCropVideoScreen from './screens/TrimAndCropVideoScreen';
import TrimVideoScreen from './screens/TrimVideoScreen';
import RecordVideoScreen from './screens/RecordVideoScreen';
import { T, fmtMs, fmtSize } from './theme';
import { DEF_CROP, type CropBox, type Screen } from './types';

const { width: SW } = Dimensions.get('window');

// ── Utility: compute letterboxed video rect inside a container ───────────────
const getContainRect = (natW: number, natH: number, containerW: number, containerH: number) => {
  if (natW <= 0 || natH <= 0) return { x: 0, y: 0, w: containerW, h: containerH };
  const scale = Math.min(containerW / natW, containerH / natH);
  const w = natW * scale, h = natH * scale;
  return { x: (containerW - w) / 2, y: (containerH - h) / 2, w, h };
};

export default function App() {
  const [screen, setScreen] = useState<Screen>('home');

  // ── Source media ─────────────────────────────────────────────────────────
  const [srcUri, setSrcUri]   = useState<string | null>(null);
  const [srcType, setSrcType] = useState<'image' | 'video' | null>(null);
  const [srcMeta, setSrcMeta] = useState<any>(null);
  const [vidDur, setVidDur]   = useState(0);

  // ── Result & UI state ────────────────────────────────────────────────────
  const [result, setResult]   = useState<MediaResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [log, setLog]         = useState<string[]>([]);
  const [opLabel, setOpLabel] = useState('');
  
  // ── Compress options states ─────────────────────────────────────────────
  const [targetSize, setTargetSize] = useState('8.0');
  const [minRes, setMinRes] = useState('720');
  const [muteAudio, setMuteAudio] = useState(false);
  const [imgQuality, setImgQuality] = useState('80');
  const [imgMaxWidth, setImgMaxWidth] = useState('1080');

  const srcPlayer = useVideoPlayer(srcUri, player => { player.loop = true; });
  const resPlayer = useVideoPlayer(result?.uri ?? null, player => { player.loop = true; });

  React.useEffect(() => { if (srcUri && srcType === 'video') srcPlayer.play(); }, [srcUri, srcType, srcPlayer]);
  React.useEffect(() => { if (result?.uri && result.mime?.startsWith('video')) resPlayer.play(); }, [result, resPlayer]);

  // ── Image crop state ─────────────────────────────────────────────────────
  const [crop,   setCrop]   = useState<CropBox>(DEF_CROP);
  const [prevSz, setPrevSz] = useState({ w: 0, h: 0 });

  // ── Video crop state ─────────────────────────────────────────────────────
  const [vcrop,   setVcrop]   = useState<CropBox>(DEF_CROP);
  const [vPrevSz, setVPrevSz] = useState({ w: 0, h: 0 });
  const [vidNat,  setVidNat]  = useState({ w: 0, h: 0 });



  // ── Trim+Crop state ───────────────────────────────────────────────────────
  const [tcCrop,   setTcCrop]   = useState<CropBox>(DEF_CROP);
  const [tcPrevSz, setTcPrevSz] = useState({ w: 0, h: 0 });
  const [tcVidNat, setTcVidNat] = useState({ w: 0, h: 0 });

  // ── Helpers ───────────────────────────────────────────────────────────────
  const addLog = useCallback((m: string) => setLog((p) => [m, ...p].slice(0, 12)), []);

  const doOp = useCallback(async (label: string, fn: () => Promise<MediaResult>) => {
    if (srcPlayer?.playing) srcPlayer.pause();
    if (resPlayer?.playing) resPlayer.pause();
    
    setLoading(true); setResult(null); setOpLabel(label);
    try {
      const r = await fn();
      setResult(r);
      addLog(`✅ ${label} → ${fmtSize(r.size)}`);
    } catch (e: any) {
      addLog(`❌ ${label}: ${e?.message ?? e}`);
      Alert.alert(label + ' failed', e?.message ?? String(e));
    } finally { setLoading(false); setOpLabel(''); }
  }, [addLog, srcPlayer, resPlayer]);

  // ── Pick media ───────────────────────────────────────────────────────────
  const pickImage = async () => {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') return Alert.alert('Permission required');
    const r = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 1 });
    if (!r.canceled && r.assets[0]) {
      const a = r.assets[0];
      setSrcUri(a.uri); setSrcType('image');
      setSrcMeta({ fileName: a.fileName, fileSize: a.fileSize, width: a.width, height: a.height });
      setResult(null); setCrop(DEF_CROP);
      addLog(`📷 ${a.fileName ?? 'image'}`);
    }
  };

  const pickVideo = async () => {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') return Alert.alert('Permission required');
    const r = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['videos'], quality: 1 });
    if (!r.canceled && r.assets[0]) {
      const a = r.assets[0];
      setSrcUri(a.uri); setSrcType('video'); setResult(null);
      setSrcMeta({ fileName: a.fileName, fileSize: a.fileSize, width: a.width, height: a.height, duration: a.duration });
      setVcrop(DEF_CROP); setVidNat({ w: 0, h: 0 });
      const d = Math.round(a.duration ?? 0);
      setVidDur(d > 0 ? d : 30000);
      addLog(`🎬 ${a.fileName ?? 'video'} · ${fmtMs(d)}`);
    }
  };

  const handleRecordComplete = (uri: string, durationMs: number, width: number, height: number) => {
    setScreen('home');
    setSrcUri(uri); setSrcType('video'); setResult(null);
    setVcrop(DEF_CROP); setVidNat({ w: 0, h: 0 });
    setVidDur(durationMs > 0 ? durationMs : 30000);

    // Set initial metadata immediately — will be refined by getThumbnail
    setSrcMeta({ fileName: 'recorded_video.mp4', fileSize: 0, width, height, duration: durationMs });
    addLog(`🎥 recorded · ${fmtMs(durationMs)}`);

    // getThumbnail → returns SOURCE VIDEO metadata: dimensions + file size + duration
    MediaToolkit.getThumbnail(uri, { timeMs: 0, quality: 30, maxWidth: 120 })
      .then((thumb) => {
        const realDur = thumb.duration > 0 ? thumb.duration : durationMs;
        setSrcMeta((prev: any) => ({
          ...prev,
          fileSize: thumb.size > 0 ? thumb.size : prev.fileSize,
          width: thumb.width > 0 ? thumb.width : prev.width,
          height: thumb.height > 0 ? thumb.height : prev.height,
          duration: realDur,
        }));
        setVidDur(realDur);
        if (thumb.size > 0) addLog(`📦 ${fmtSize(thumb.size)} · ${fmtMs(realDur)}`);
      })
      .catch(() => {});
  };

  // ── Operations ───────────────────────────────────────────────────────────
  const applyTrim = (startMs: number, endMs: number) => {
    setScreen('home');
    doOp('Trim', () => MediaToolkit.trimVideo(srcUri!, { startTime: startMs, endTime: endMs }));
  };

  const applyImageCrop = () => {
    setScreen('home');
    doOp('Crop Image', () => MediaToolkit.cropImage(srcUri!, { x: crop.x, y: crop.y, width: crop.w, height: crop.h }));
  };

  const applyVideoCrop = () => {
    const vr = getContainRect(vidNat.w, vidNat.h, vPrevSz.w, vPrevSz.h);
    const c = vr.w > 0 ? {
      x: Math.max(0, (vcrop.x * vPrevSz.w - vr.x) / vr.w),
      y: Math.max(0, (vcrop.y * vPrevSz.h - vr.y) / vr.h),
      w: Math.min(1, (vcrop.w * vPrevSz.w) / vr.w),
      h: Math.min(1, (vcrop.h * vPrevSz.h) / vr.h),
    } : vcrop;
    setScreen('home');
    doOp('Crop Video', () => MediaToolkit.cropVideo(srcUri!, { x: c.x, y: c.y, width: c.w, height: c.h }));
  };

  const applyTrimAndCrop = (startMs: number, endMs: number) => {
    const vr = getContainRect(tcVidNat.w, tcVidNat.h, tcPrevSz.w, tcPrevSz.h);
    const c = vr.w > 0 ? {
      x: Math.max(0, (tcCrop.x * tcPrevSz.w - vr.x) / vr.w),
      y: Math.max(0, (tcCrop.y * tcPrevSz.h - vr.y) / vr.h),
      w: Math.min(1, (tcCrop.w * tcPrevSz.w) / vr.w),
      h: Math.min(1, (tcCrop.h * tcPrevSz.h) / vr.h),
    } : tcCrop;
    setScreen('home');
    doOp('Trim+Crop', () =>
      MediaToolkit.trimAndCropVideo(srcUri!, { startTime: startMs, endTime: endMs, x: c.x, y: c.y, width: c.w, height: c.h })
    );
  };

  const compressImg = () => {
    setScreen('home');
    const q = parseInt(imgQuality) || 80;
    const w = parseInt(imgMaxWidth) || 1080;
    doOp('Compress Image', () => MediaToolkit.compressImage(srcUri!, { quality: q, maxWidth: w, format: 'jpeg' }));
  };

  const compressVid = () => {
    setScreen('home');
    const size = parseFloat(targetSize) || 8.0;
    const res = parseInt(minRes) || 720;
    doOp('Smart Compress Video', () => 
      MediaToolkit.compressVideo(srcUri!, { 
        targetSizeInMB: size, 
        minResolution: res,
        muteAudio: muteAudio 
      })
    );
  };

  const extractThumb = () => {
    doOp('Get Thumbnail', async () => {
      const r = await MediaToolkit.getThumbnail(srcUri!, { timeMs: 0, quality: 85, maxWidth: 720 });
      return { ...r, duration: 0, mime: 'image/jpeg' } as any;
    });
  };

  // ── Screen routing ────────────────────────────────────────────────────────
  if (screen === 'recordVideo') {
    return (
      <RecordVideoScreen
        onBack={() => setScreen('home')}
        onRecord={handleRecordComplete}
      />
    );
  }

  if (screen === 'trimVideo' && srcUri && srcType === 'video') {
    return (
      <TrimVideoScreen
        player={srcPlayer}
        srcUri={srcUri}
        durationMs={vidDur}
        loading={loading}
        opLabel={opLabel}
        onBack={() => setScreen('home')}
        onApply={applyTrim}
      />
    );
  }

  if (screen === 'cropImage' && srcUri && srcType === 'image') {
    return (
      <CropImageScreen
        srcUri={srcUri}
        crop={crop}
        prevSz={prevSz}
        loading={loading}
        opLabel={opLabel}
        onBack={() => setScreen('home')}
        onApply={applyImageCrop}
        onLayout={(w, h) => setPrevSz({ w, h })}
        onCropCommit={setCrop}
      />
    );
  }

  if (screen === 'cropVideo' && srcUri && srcType === 'video') {
    return (
      <CropVideoScreen
        player={srcPlayer}
        srcUri={srcUri}
        vcrop={vcrop}
        vPrevSz={vPrevSz}
        vidNat={vidNat}
        loading={loading}
        opLabel={opLabel}
        onBack={() => setScreen('home')}
        onApply={applyVideoCrop}
        onLayout={(w, h) => setVPrevSz({ w, h })}
        onNatSize={(w, h) => setVidNat({ w, h })}
        onCropCommit={setVcrop}
        getContainRect={getContainRect}
      />
    );
  }

  if (screen === 'trimAndCropVideo' && srcUri && srcType === 'video') {
    return (
      <TrimAndCropVideoScreen
        player={srcPlayer}
        srcUri={srcUri}
        durationMs={vidDur}
        tcCrop={tcCrop}
        tcPrevSz={tcPrevSz}
        tcVidNat={tcVidNat}
        loading={loading}
        opLabel={opLabel}
        onBack={() => setScreen('home')}
        onApply={applyTrimAndCrop}
        onLayout={(w, h) => setTcPrevSz({ w, h })}
        onNatSize={(w, h) => setTcVidNat({ w, h })}
        onCropCommit={setTcCrop}
        getContainRect={getContainRect}
      />
    );
  }

  // ── Home Screen ───────────────────────────────────────────────────────────
  const dispUri = result?.mime?.startsWith('image') ? result.uri : srcUri;

  return (
    <SafeAreaProvider>
      <SafeAreaView style={h.safe} edges={['top', 'left', 'right']}>
        <StatusBar barStyle="light-content" backgroundColor={T.bg} translucent={false} />

      <View style={h.header}>
        <View>
          <Text style={h.title}>MediaToolkit</Text>
          <Text style={h.sub}>react-native-media-toolkit · Nitro</Text>
        </View>
        <View style={[h.tag, { backgroundColor: T.green + '22' }]}>
          <Text style={[h.tagTxt, { color: T.green }]}>New Arch</Text>
        </View>
      </View>

      <ScrollView style={{ flex: 1 }} contentContainerStyle={h.scroll} showsVerticalScrollIndicator={false}>

        {/* Source picker */}
        <View style={h.card}>
          <Text style={h.lbl}>SOURCE MEDIA</Text>
          <View style={h.row}>
            <Pressable style={({ pressed }) => [h.pickBtn, { opacity: pressed ? 0.7 : 1 }]} onPress={pickImage}>
              <Ionicons name="image-outline" size={20} color={T.teal} />
              <Text style={[h.pickTxt, { color: T.teal }]}>Image</Text>
            </Pressable>
            <Pressable style={({ pressed }) => [h.pickBtn, h.pickBtnV, { opacity: pressed ? 0.7 : 1 }]} onPress={pickVideo}>
              <Ionicons name="videocam-outline" size={22} color={T.orange} />
              <Text style={[h.pickTxt, { color: T.orange }]}>Video</Text>
            </Pressable>
            <Pressable style={({ pressed }) => [h.pickBtn, { opacity: pressed ? 0.7 : 1, borderColor: '#FF3B30', backgroundColor: '#FF3B3011' }]} onPress={() => setScreen('recordVideo')}>
              <Ionicons name="camera-outline" size={22} color="#FF3B30" />
              <Text style={[h.pickTxt, { color: '#FF3B30' }]}>Record</Text>
            </Pressable>
          </View>

          {/* Preview */}
          {srcUri && srcType === 'image' && dispUri && (
            <View style={h.prev}>
              <Image source={{ uri: dispUri }} style={{ width: '100%', height: '100%' }} resizeMode="contain" />
            </View>
          )}
          {srcUri && srcType === 'video' && (
            <View style={h.prev}>
              <VideoView player={srcPlayer} style={StyleSheet.absoluteFill} contentFit="contain" nativeControls />
            </View>
          )}
          {srcMeta && (
            <View style={{ gap: 6, marginTop: 12 }}>
              {[
                ['File', srcMeta.fileName ?? srcUri?.split('/').pop() ?? ''],
                ...(srcMeta.fileSize ? [['Size', fmtSize(srcMeta.fileSize)]] : []),
                ...(srcMeta.width && srcMeta.height ? [['Dim', `${srcMeta.width}×${srcMeta.height}`]] : []),
                ...(srcMeta.duration > 0 ? [['Dur', fmtMs(srcMeta.duration)]] : []),
              ].map(([k, v]) => (
                <View key={k} style={h.metaRow}>
                  <Text style={h.metaK}>{k}</Text>
                  <Text style={h.metaV} numberOfLines={1}>{v}</Text>
                </View>
              ))}
            </View>
          )}
          {!srcUri && (
            <View style={h.empty}>
              <Ionicons name="albums-outline" size={36} color={T.textMuted} />
              <Text style={{ color: T.textMuted, fontSize: 13, marginTop: 8 }}>No media selected</Text>
            </View>
          )}
        </View>

        {/* Image ops */}
        {srcType === 'image' && srcUri && (
          <View style={h.card}>
            <Text style={h.lbl}>IMAGE OPS</Text>
            <View style={h.opRow}>
              <View style={{ flex: 1 }}>
                <Text style={h.opTitle}>Crop</Text>
                <Text style={h.opHint}>Draw a crop region</Text>
              </View>
              <ActionBtn label="Crop" icon="crop" color={T.teal} onPress={() => setScreen('cropImage')} disabled={loading} />
            </View>
            <View style={h.divider} />
            <View style={[h.opRow, { alignItems: 'flex-start' }]}>
              <View style={{ flex: 1, paddingRight: 12 }}>
                <Text style={h.opTitle}>Compress</Text>
                
                <View style={{ marginTop: 8, marginBottom: 12 }}>
                  <Text style={[h.opHint, { marginBottom: 6 }]}>Quality (0-100)</Text>
                  <View style={{ flexDirection: 'row', alignItems: 'center', backgroundColor: T.bg, borderWidth: 1, borderColor: T.border, borderRadius: 8, paddingHorizontal: 10 }}>
                    <TextInput 
                      style={[{ flex: 1, color: T.text, fontSize: 13, height: 36 }]} 
                      value={imgQuality} 
                      onChangeText={setImgQuality} 
                      keyboardType="number-pad" 
                      placeholderTextColor={T.textMuted}
                    />
                    <Text style={{ fontSize: 11, color: T.textMuted, fontWeight: '700' }}>%</Text>
                  </View>
                </View>
                
                <View style={{ marginBottom: 4 }}>
                    <Text style={[h.opHint, { marginBottom: 6 }]}>Max Width (px)</Text>
                    <View style={{ flexDirection: 'row', gap: 6 }}>
                      {['720', '1080', '1440', '2160'].map(res => (
                        <TouchableOpacity 
                          key={res}
                          onPress={() => setImgMaxWidth(res)}
                          style={{
                            paddingHorizontal: 8, paddingVertical: 4, borderRadius: 6,
                            backgroundColor: imgMaxWidth === res ? T.accent : T.bg,
                            borderWidth: 1, borderColor: imgMaxWidth === res ? T.accent : T.border
                          }}
                        >
                          <Text style={{ fontSize: 11, color: imgMaxWidth === res ? '#fff' : T.textMuted, fontWeight: '600' }}>{res}</Text>
                        </TouchableOpacity>
                      ))}
                    </View>
                </View>
              </View>
              <ActionBtn label="Compress" icon="archive" color={T.accent} onPress={compressImg} disabled={loading} />
            </View>
          </View>
        )}

        {/* Video ops */}
        {srcType === 'video' && srcUri && (
          <View style={h.card}>
            <Text style={h.lbl}>VIDEO OPS</Text>
            <View style={h.opRow}>
              <Ionicons name="cut-outline" size={20} color={T.orange} />
              <View style={{ flex: 1, marginLeft: 10 }}>
                <Text style={h.opTitle}>Trim</Text>
                <Text style={h.opHint}>Select a segment to keep</Text>
              </View>
              <ActionBtn label="Trim" icon="cut" color={T.orange} onPress={() => setScreen('trimVideo')} disabled={loading} />
            </View>
            <View style={h.divider} />
            <View style={h.opRow}>
              <Ionicons name="scan-outline" size={20} color={T.accent} />
              <View style={{ flex: 1, marginLeft: 10 }}>
                <Text style={h.opTitle}>Crop</Text>
                <Text style={h.opHint}>Drag overlay on preview</Text>
              </View>
              <ActionBtn label="Crop" icon="crop" color={T.accent} onPress={() => setScreen('cropVideo')} disabled={loading} />
            </View>
            <View style={h.divider} />
            <View style={h.opRow}>
              <Ionicons name="git-branch-outline" size={20} color="#FF9500" />
              <View style={{ flex: 1, marginLeft: 10 }}>
                <Text style={h.opTitle}>Trim + Crop</Text>
                <Text style={h.opHint}>Trim time range & select crop region</Text>
              </View>
              <ActionBtn
                label="Trim+Crop"
                icon="options"
                color="#FF9500"
                onPress={() => {
                  setTcCrop(DEF_CROP); setTcVidNat({ w: 0, h: 0 });
                  setScreen('trimAndCropVideo');
                }}
                disabled={loading}
              />
            </View>
            <View style={h.divider} />
            <View style={[h.opRow, { alignItems: 'flex-start' }]}>
              <Ionicons name="layers-outline" size={20} color={T.teal} style={{ marginTop: 4 }} />
              <View style={{ flex: 1, marginLeft: 10 }}>
                <Text style={h.opTitle}>Smart Compress</Text>
                <View style={{ marginTop: 8, marginBottom: 12 }}>
                  <Text style={[h.opHint, { marginBottom: 6 }]}>Target Size</Text>
                  <View style={{ flexDirection: 'row', alignItems: 'center', backgroundColor: T.bg, borderWidth: 1, borderColor: T.border, borderRadius: 8, paddingHorizontal: 10 }}>
                    <TextInput 
                      style={[{ flex: 1, color: T.text, fontSize: 13, height: 36 }]} 
                      value={targetSize} 
                      onChangeText={setTargetSize} 
                      keyboardType="decimal-pad" 
                      placeholderTextColor={T.textMuted}
                    />
                    <Text style={{ fontSize: 11, color: T.textMuted, fontWeight: '700' }}>MB</Text>
                  </View>
                </View>
                
                <View style={{ marginBottom: 12 }}>
                    <Text style={[h.opHint, { marginBottom: 6 }]}>Min Resolution Bounds</Text>
                    <View style={{ flexDirection: 'row', gap: 6 }}>
                      {['480', '540', '720', '1080'].map(res => (
                        <Pressable 
                          key={res} 
                          onPress={() => setMinRes(res)}
                          style={{ 
                            paddingHorizontal: 10, paddingVertical: 6, borderRadius: 6,
                            backgroundColor: minRes === res ? T.teal : T.bg,
                            borderWidth: 1, borderColor: minRes === res ? T.teal : T.border
                          }}
                        >
                          <Text style={{ fontSize: 11, fontWeight: '700', color: minRes === res ? '#000' : T.text }}>{res}p</Text>
                        </Pressable>
                      ))}
                    </View>
                </View>

                <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
                  <Text style={[h.opHint, { flex: 1 }]}>Mute (Remove Audio Track)</Text>
                  <Switch 
                    value={muteAudio} 
                    onValueChange={setMuteAudio}
                    trackColor={{ false: T.border, true: T.teal }}
                    thumbColor="#FFF"
                    style={{ transform: [{ scale: 0.8 }] }}
                  />
                </View>
              </View>
              <ActionBtn label="Compress" icon="archive" color={T.teal} onPress={compressVid} disabled={loading} />
            </View>
            <View style={h.divider} />
            <View style={h.opRow}>
              <Ionicons name="image-outline" size={20} color={T.orange} />
              <View style={{ flex: 1, marginLeft: 10 }}>
                <Text style={h.opTitle}>Thumbnail</Text>
                <Text style={h.opHint}>Extract frame at 0s as JPEG</Text>
              </View>
              <ActionBtn label="Extract" icon="camera" color={T.orange} onPress={extractThumb} disabled={loading} />
            </View>
          </View>
        )}

        {/* Loading overlay (home-level ops) */}
        {loading && (
          <View style={[StyleSheet.absoluteFill, { backgroundColor: 'rgba(0,0,0,0.78)', alignItems: 'center', justifyContent: 'center', zIndex: 99 }]}>
            <ActivityIndicator size="large" color="#FFF" />
            <Text style={{ color: 'rgba(255,255,255,0.7)', fontSize: 14, marginTop: 14 }}>{opLabel || 'Processing...'}</Text>
          </View>
        )}

        {/* Result */}
        {result && (
          <View style={[h.card, { borderColor: T.green + '44' }]}>
            <Text style={[h.lbl, { color: T.green }]}>RESULT</Text>
            {result.mime?.startsWith('image') && (
              <Image source={{ uri: result.uri }} style={{ width: '100%', height: 180, borderRadius: 10, marginBottom: 12 }} resizeMode="contain" />
            )}
            {result.mime?.startsWith('video') && (
              <View style={{ width: '100%', height: SW * 0.58, borderRadius: 10, overflow: 'hidden', marginBottom: 12, backgroundColor: '#000' }}>
                <VideoView player={resPlayer} style={StyleSheet.absoluteFill} contentFit="contain" nativeControls />
              </View>
            )}
            <View style={{ gap: 6 }}>
              {[
                ['File', result.uri.split('/').pop() ?? ''],
                ['Size', fmtSize(result.size)],
                ['Dim', `${result.width}×${result.height}`],
                ...(result.duration > 0 ? [['Dur', fmtMs(result.duration)]] : []),
              ].map(([k, v]) => (
                <View key={k} style={h.metaRow}>
                  <Text style={h.metaK}>{k}</Text>
                  <Text style={h.metaV} numberOfLines={1}>{v}</Text>
                </View>
              ))}
            </View>
          </View>
        )}

        {/* Log */}
        {log.length > 0 && (
          <View style={h.card}>
            <Text style={h.lbl}>LOG</Text>
            {log.map((l, i) => (
              <Text key={i} style={[h.logLine, l.startsWith('❌') && { color: T.accent }]}>{l}</Text>
            ))}
          </View>
        )}

        <View style={{ height: 32 }} />
      </ScrollView>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const h = StyleSheet.create({
  safe:      { flex: 1, backgroundColor: T.bg },
  scroll:    { padding: 14 },
  header:    { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingTop: 8, paddingBottom: 14, borderBottomWidth: StyleSheet.hairlineWidth, borderColor: T.border },
  title:     { fontSize: 20, fontWeight: '800', color: T.text },
  sub:       { fontSize: 10, color: T.teal, marginTop: 2 },
  tag:       { borderRadius: 99, paddingHorizontal: 8, paddingVertical: 3 },
  tagTxt:    { fontSize: 10, fontWeight: '700' },
  card:      { backgroundColor: T.surface, borderRadius: 16, padding: 16, marginBottom: 12, borderWidth: StyleSheet.hairlineWidth, borderColor: T.border },
  lbl:       { fontSize: 10, fontWeight: '700', color: T.textMuted, letterSpacing: 1.2, marginBottom: 12 },
  row:       { flexDirection: 'row', gap: 10, marginBottom: 12 },
  pickBtn:   { flex: 1, flexDirection: 'row', gap: 8, alignItems: 'center', justifyContent: 'center', paddingVertical: 13, borderRadius: 12, backgroundColor: T.card, borderWidth: 1, borderColor: T.border },
  pickBtnV:  { backgroundColor: T.card, borderColor: T.border },
  pickTxt:   { fontSize: 13, fontWeight: '700', color: T.teal },
  prev:      { width: '100%', height: SW * 0.58, borderRadius: 12, overflow: 'hidden', backgroundColor: T.card },
  empty:     { height: 100, borderRadius: 12, backgroundColor: T.card, alignItems: 'center', justifyContent: 'center' },
  opRow:     { flexDirection: 'row', alignItems: 'center', gap: 10 },
  opTitle:   { color: T.text, fontSize: 14, fontWeight: '600', marginBottom: 2 },
  opHint:    { color: T.textMuted, fontSize: 11 },
  divider:   { height: StyleSheet.hairlineWidth, backgroundColor: T.border, marginVertical: 14 },
  metaRow:   { flexDirection: 'row', justifyContent: 'space-between' },
  metaK:     { color: T.textMuted, fontSize: 12 },
  metaV:     { color: T.text, fontSize: 12, fontWeight: '600', maxWidth: '60%', textAlign: 'right' },
  logLine:   { color: T.textSub, fontSize: 11, lineHeight: 20, fontFamily: 'monospace' },
  input:     { backgroundColor: T.bg, color: T.text, paddingHorizontal: 10, paddingVertical: 6, borderRadius: 6, fontSize: 12, borderWidth: 1, borderColor: T.border },
});
