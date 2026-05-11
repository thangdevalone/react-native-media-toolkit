import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  StatusBar,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { T, fmtMs } from '../theme';

export interface ConcatClip {
  uri: string;
  fileName: string;
  durationMs: number;
  /** When true, audio will be stripped via compressVideo({muteAudio:true}) before concat. */
  stripAudio: boolean;
}

interface Props {
  loading: boolean;
  opLabel: string;
  onBack: () => void;
  onApply: (clips: ConcatClip[]) => void;
}

export default function ConcatVideosScreen({
  loading,
  opLabel,
  onBack,
  onApply,
}: Props) {
  const [clips, setClips] = useState<ConcatClip[]>([]);

  const pickClips = useCallback(async () => {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') return Alert.alert('Permission required');
    const r = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['videos'],
      allowsMultipleSelection: true,
      selectionLimit: 0,
      quality: 1,
    });
    if (r.canceled) return;
    const additions: ConcatClip[] = r.assets.map((a) => ({
      uri: a.uri,
      fileName: a.fileName ?? a.uri.split('/').pop() ?? 'clip',
      durationMs: Math.round(a.duration ?? 0),
      stripAudio: false,
    }));
    setClips((prev) => [...prev, ...additions]);
  }, []);

  const removeClip = useCallback((idx: number) => {
    setClips((prev) => prev.filter((_, i) => i !== idx));
  }, []);

  const toggleMute = useCallback((idx: number) => {
    setClips((prev) =>
      prev.map((c, i) => (i === idx ? { ...c, stripAudio: !c.stripAudio } : c))
    );
  }, []);

  const moveClip = useCallback((idx: number, delta: -1 | 1) => {
    setClips((prev) => {
      const next = [...prev];
      const j = idx + delta;
      if (j < 0 || j >= next.length) return prev;
      [next[idx], next[j]] = [next[j]!, next[idx]!];
      return next;
    });
  }, []);

  const apply = useCallback(() => {
    if (clips.length < 2) {
      return Alert.alert(
        'Need at least 2 clips',
        'Pick two or more clips to concatenate.'
      );
    }
    onApply(clips);
  }, [clips, onApply]);

  const hasMixedAudio = (() => {
    if (clips.length < 2) return false;
    const muted = clips.some((c) => c.stripAudio);
    const audible = clips.some((c) => !c.stripAudio);
    return muted && audible;
  })();

  return (
    <View style={s.root}>
      <StatusBar
        barStyle="light-content"
        backgroundColor={T.bg}
        translucent={false}
      />
      <SafeAreaView style={s.safe}>
        <View style={s.header}>
          <TouchableOpacity style={s.backBtn} onPress={onBack}>
            <Ionicons name="chevron-back" size={24} color={T.text} />
          </TouchableOpacity>
          <Text style={s.title}>CONCAT VIDEOS</Text>
          <TouchableOpacity
            style={[s.applyBtn, clips.length < 2 && { opacity: 0.4 }]}
            onPress={apply}
            disabled={clips.length < 2}
          >
            <Text style={s.applyTxt}>Apply</Text>
          </TouchableOpacity>
        </View>

        <View style={s.body}>
          <Text style={s.hint}>
            Pick 2+ clips to concatenate. Toggle the mute icon on a clip to strip
            its audio before concat — useful for testing heterogeneous track
            scenarios (Media3 Transformer is sensitive to mismatched track types
            across items).
          </Text>

          {hasMixedAudio && (
            <View style={s.banner}>
              <Ionicons name="warning-outline" size={16} color={T.orange} />
              <Text style={s.bannerTxt}>
                Mixed audio/no-audio clips queued — exercises the
                EditedMediaItemSequence mismatch path on Android.
              </Text>
            </View>
          )}

          <FlatList
            data={clips}
            keyExtractor={(item, i) => `${i}-${item.uri}`}
            ListEmptyComponent={
              <View style={s.empty}>
                <Ionicons
                  name="film-outline"
                  size={36}
                  color={T.textMuted}
                />
                <Text style={s.emptyTxt}>No clips yet</Text>
              </View>
            }
            contentContainerStyle={{ paddingVertical: 8, gap: 8 }}
            renderItem={({ item, index }) => (
              <View style={s.clipRow}>
                <View style={s.clipIdx}>
                  <Text style={s.clipIdxTxt}>{index + 1}</Text>
                </View>
                <View style={{ flex: 1, paddingHorizontal: 10 }}>
                  <Text style={s.clipName} numberOfLines={1}>
                    {item.fileName}
                  </Text>
                  <Text style={s.clipMeta}>
                    {fmtMs(item.durationMs)} ·{' '}
                    {item.stripAudio ? 'audio stripped' : 'with audio'}
                  </Text>
                </View>
                <TouchableOpacity
                  style={s.iconBtn}
                  onPress={() => moveClip(index, -1)}
                  disabled={index === 0}
                >
                  <Ionicons
                    name="arrow-up"
                    size={16}
                    color={index === 0 ? T.textMuted : T.text}
                  />
                </TouchableOpacity>
                <TouchableOpacity
                  style={s.iconBtn}
                  onPress={() => moveClip(index, 1)}
                  disabled={index === clips.length - 1}
                >
                  <Ionicons
                    name="arrow-down"
                    size={16}
                    color={index === clips.length - 1 ? T.textMuted : T.text}
                  />
                </TouchableOpacity>
                <TouchableOpacity
                  style={[
                    s.iconBtn,
                    item.stripAudio && { backgroundColor: T.orange + '33' },
                  ]}
                  onPress={() => toggleMute(index)}
                >
                  <Ionicons
                    name={
                      item.stripAudio
                        ? 'volume-mute'
                        : 'volume-medium-outline'
                    }
                    size={16}
                    color={item.stripAudio ? T.orange : T.text}
                  />
                </TouchableOpacity>
                <TouchableOpacity
                  style={s.iconBtn}
                  onPress={() => removeClip(index)}
                >
                  <Ionicons name="close" size={16} color={T.accent} />
                </TouchableOpacity>
              </View>
            )}
          />

          <Pressable
            style={({ pressed }) => [
              s.addBtn,
              { opacity: pressed ? 0.7 : 1 },
            ]}
            onPress={pickClips}
          >
            <Ionicons name="add" size={20} color={T.teal} />
            <Text style={s.addTxt}>Add Clips</Text>
          </Pressable>
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
  root: { flex: 1, backgroundColor: T.bg },
  safe: { flex: 1 },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderColor: T.border,
  },
  backBtn: { padding: 8 },
  title: {
    color: '#EBEBF5CC',
    fontSize: 14,
    fontWeight: '600',
    letterSpacing: 1,
  },
  applyBtn: {
    backgroundColor: T.teal,
    borderRadius: 20,
    paddingHorizontal: 20,
    paddingVertical: 8,
  },
  applyTxt: { color: '#000', fontWeight: '700', fontSize: 15 },
  body: { flex: 1, paddingHorizontal: 14, paddingTop: 12 },
  hint: { color: T.textMuted, fontSize: 12, lineHeight: 17, marginBottom: 10 },
  banner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: T.orange + '15',
    borderColor: T.orange + '55',
    borderWidth: 1,
    borderRadius: 10,
    padding: 10,
    marginBottom: 8,
  },
  bannerTxt: { color: T.text, fontSize: 11, flex: 1, lineHeight: 15 },
  empty: {
    height: 140,
    borderRadius: 12,
    backgroundColor: T.card,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 12,
  },
  emptyTxt: { color: T.textMuted, fontSize: 13, marginTop: 8 },
  clipRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: T.surface,
    borderRadius: 12,
    paddingHorizontal: 8,
    paddingVertical: 8,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: T.border,
  },
  clipIdx: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: T.bg,
    alignItems: 'center',
    justifyContent: 'center',
  },
  clipIdxTxt: { color: T.teal, fontSize: 12, fontWeight: '700' },
  clipName: { color: T.text, fontSize: 13, fontWeight: '600' },
  clipMeta: { color: T.textMuted, fontSize: 11, marginTop: 2 },
  iconBtn: {
    width: 32,
    height: 32,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    marginLeft: 4,
  },
  addBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: 14,
    borderRadius: 12,
    backgroundColor: T.card,
    borderWidth: 1,
    borderColor: T.teal + '55',
    marginTop: 12,
    marginBottom: 16,
  },
  addTxt: { color: T.teal, fontSize: 14, fontWeight: '700' },
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.78)',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 99,
  },
  loadingTxt: { color: 'rgba(255,255,255,0.7)', fontSize: 14, marginTop: 14 },
});
