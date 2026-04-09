import { Ionicons } from '@expo/vector-icons';
import { VideoView, type VideoPlayer } from 'expo-video';
import { useCallback, useRef, useState, useEffect } from 'react';
import {
  ActivityIndicator,
  StatusBar,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import VideoTrimBar from '../components/VideoTrimBar';
import { T } from '../theme';

interface Props {
  player: VideoPlayer | null;
  srcUri: string;
  durationMs: number;
  loading: boolean;
  opLabel: string;
  onBack: () => void;
  onApply: (startMs: number, endMs: number) => void;
}

export default function TrimVideoScreen({
  player,
  srcUri,
  durationMs,
  loading,
  opLabel,
  onBack,
  onApply,
}: Props) {
  const trimBarRef = useRef<{
    getRange: () => { startMs: number; endMs: number };
  } | null>(null);
  const [isPlaying, setIsPlaying] = useState(true);
  const [playheadPos, setPlayheadPos] = useState(0);

  useEffect(() => {
    if (player) {
      player.loop = true;
      player.play();
    }
  }, [player]);

  const handleSeek = useCallback(
    (ms: number) => {
      player.currentTime = ms / 1000;
    },
    [player]
  );

  const togglePlay = useCallback(() => {
    if (player.playing) {
      player.pause();
      setIsPlaying(false);
    } else {
      player.play();
      setIsPlaying(true);
    }
  }, [player]);

  useEffect(() => {
    const itv = setInterval(() => {
      setIsPlaying(player.playing);
      if (durationMs > 0) {
        setPlayheadPos((player.currentTime * 1000) / durationMs);
      }
    }, 100);
    return () => clearInterval(itv);
  }, [player, durationMs]);

  return (
    <View style={s.root}>
      <StatusBar
        barStyle="light-content"
        backgroundColor="#000"
        translucent={false}
      />
      <SafeAreaView style={s.safe}>
        <View style={s.header}>
          <TouchableOpacity style={s.backBtn} onPress={onBack}>
            <Ionicons name="chevron-back" size={24} color={T.text} />
          </TouchableOpacity>
          <Text style={s.title}>VIDEO</Text>
          <TouchableOpacity
            style={s.nextBtn}
            onPress={() => {
              const range = trimBarRef.current?.getRange();
              if (range) onApply(range.startMs, range.endMs);
            }}
          >
            <Text style={s.nextTxt}>Apply</Text>
          </TouchableOpacity>
        </View>

        <View style={s.preview}>
          <VideoView
            player={player}
            style={StyleSheet.absoluteFill}
            contentFit="contain"
            nativeControls={false}
          />
          <TouchableOpacity
            style={s.playBtn}
            onPress={togglePlay}
            activeOpacity={0.85}
          >
            {!isPlaying && (
              <View style={s.playCircle}>
                <Ionicons
                  name="play"
                  size={32}
                  color="#FFF"
                  style={{ marginLeft: 4 }}
                />
              </View>
            )}
          </TouchableOpacity>
        </View>

        <VideoTrimBar
          videoUri={srcUri}
          durationMs={durationMs}
          trimBarRef={trimBarRef}
          onSeek={handleSeek}
          playheadPos={playheadPos}
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
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  backBtn: { padding: 8 },
  title: {
    color: '#EBEBF5CC',
    fontSize: 14,
    fontWeight: '600',
    letterSpacing: 1,
  },
  nextBtn: {
    backgroundColor: T.accent,
    borderRadius: 20,
    paddingHorizontal: 20,
    paddingVertical: 8,
  },
  nextTxt: { color: '#fff', fontWeight: '700', fontSize: 15 },
  preview: { flex: 1, backgroundColor: '#000' },
  playBtn: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 10,
  },
  playCircle: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: 'rgba(0,0,0,0.45)',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1.5,
    borderColor: 'rgba(255,255,255,0.5)',
  },
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.78)',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 99,
  },
  loadingTxt: { color: 'rgba(255,255,255,0.7)', fontSize: 14, marginTop: 14 },
});
