import React, { useRef, useState, useEffect, useCallback } from 'react';
import { StyleSheet, View, Text, TouchableOpacity, ActivityIndicator, Platform } from 'react-native';
import { Camera, useCameraDevice, useCameraPermission, useMicrophonePermission } from 'react-native-vision-camera';
import { Ionicons } from '@expo/vector-icons';
import { SafeAreaView } from 'react-native-safe-area-context';
import { T } from '../theme';

interface RecordVideoScreenProps {
  onBack: () => void;
  onRecord: (uri: string, durationMs: number, width: number, height: number) => void;
}

export default function RecordVideoScreen({ onBack, onRecord }: RecordVideoScreenProps) {
  const device = useCameraDevice('back');
  const { hasPermission, requestPermission } = useCameraPermission();
  const { hasPermission: hasMicPermission, requestPermission: requestMicPermission } = useMicrophonePermission();

  const camera = useRef<Camera>(null);
  const [isRecording, setIsRecording] = useState(false);
  const [saving, setSaving] = useState(false);
  const [elapsed, setElapsed] = useState(0);

  // Use ref for startTime to avoid stale closure in onRecordingFinished
  const startTimeRef = useRef<number>(0);
  const stopTimeRef = useRef<number>(0);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    (async () => {
      if (!hasPermission) await requestPermission();
      if (!hasMicPermission) await requestMicPermission();
    })();
  }, [hasPermission, hasMicPermission, requestPermission, requestMicPermission]);

  // Cleanup timer on unmount
  useEffect(() => {
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, []);

  const fmtTime = (ms: number) => {
    const s = Math.floor(ms / 1000);
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${m}:${sec.toString().padStart(2, '0')}`;
  };

  const startRecording = useCallback(() => {
    if (!camera.current) return;
    startTimeRef.current = Date.now();
    setIsRecording(true);
    setElapsed(0);

    // Start elapsed timer
    timerRef.current = setInterval(() => {
      setElapsed(Date.now() - startTimeRef.current);
    }, 200);

    camera.current.startRecording({
      onRecordingFinished: (video) => {
        if (timerRef.current) clearInterval(timerRef.current);
        // Use VisionCamera's video.duration (actual file duration) as primary.
        // Manual timer includes camera startup delay so it's always longer.
        // video.duration is in seconds → convert to ms.
        const vcDurMs = video.duration > 0 ? Math.round(video.duration * 1000) : 0;
        const manualDurMs = stopTimeRef.current > 0
          ? stopTimeRef.current - startTimeRef.current
          : Date.now() - startTimeRef.current;
        const durMs = vcDurMs > 0 ? vcDurMs : manualDurMs;

        // VisionCamera returns a plain path (no file:// prefix)
        const uri = video.path.startsWith('file://') ? video.path : `file://${video.path}`;
        onRecord(uri, durMs, video.width, video.height);
      },
      onRecordingError: (error) => {
        if (timerRef.current) clearInterval(timerRef.current);
        console.error('Recording error:', error);
        setIsRecording(false);
        setElapsed(0);
      },
    });
  }, [onRecord]);

  const stopRecording = useCallback(() => {
    stopTimeRef.current = Date.now();  // Capture EXACT stop moment for duration
    camera.current?.stopRecording();
    setIsRecording(false);
    setSaving(true);  // Show processing indicator until onRecordingFinished
  }, []);

  if (!hasPermission || !hasMicPermission) {
    return (
      <SafeAreaView style={styles.safe}>
        <View style={styles.center}>
          <ActivityIndicator size="large" color={T.teal} />
          <Text style={styles.loadingTxt}>Requesting Camera & Mic Permissions...</Text>
        </View>
        <TouchableOpacity style={styles.backBtn} onPress={onBack}>
          <Ionicons name="arrow-back" size={24} color="#FFF" />
        </TouchableOpacity>
      </SafeAreaView>
    );
  }

  if (!device) {
    return (
      <SafeAreaView style={styles.safe}>
        <View style={styles.center}>
          <Ionicons name="alert-circle-outline" size={48} color={T.accent} />
          <Text style={styles.loadingTxt}>No camera device found</Text>
        </View>
        <TouchableOpacity style={styles.backBtn} onPress={onBack}>
          <Ionicons name="arrow-back" size={24} color="#FFF" />
        </TouchableOpacity>
      </SafeAreaView>
    );
  }

  return (
    <View style={styles.container}>
      <Camera
        ref={camera}
        style={StyleSheet.absoluteFill}
        device={device}
        isActive={true}
        video={true}
        audio={true}
        videoStabilizationMode="auto"
        orientation="portrait"
      />

      {/* Overlay UI */}
      <SafeAreaView style={styles.overlay} edges={['top', 'bottom']}>
        {/* Top bar */}
        <View style={styles.header}>
          <TouchableOpacity
            style={styles.iconBtn}
            onPress={onBack}
            disabled={isRecording || saving}
          >
            <Ionicons name="close" size={24} color={(isRecording || saving) ? '#666' : '#FFF'} />
          </TouchableOpacity>

          {isRecording && (
            <View style={styles.timerBadge}>
              <View style={styles.recDot} />
              <Text style={styles.timerTxt}>{fmtTime(elapsed)}</Text>
            </View>
          )}

          <View style={{ width: 44 }} />
        </View>

        {/* Bottom bar */}
        <View style={styles.footer}>
          {saving ? (
            <>
              <ActivityIndicator size="large" color="#FFF" />
              <Text style={[styles.hint, { marginTop: 12 }]}>Saving video...</Text>
            </>
          ) : (
            <>
              <Text style={styles.hint}>
                {isRecording ? 'Tap to stop' : 'Tap to record'}
              </Text>
              <TouchableOpacity
                style={[styles.recBtn, isRecording && styles.recBtnActive]}
                onPress={isRecording ? stopRecording : startRecording}
                activeOpacity={0.7}
              >
                <View style={[styles.recInner, isRecording && styles.recInnerActive]} />
              </TouchableOpacity>
            </>
          )}
        </View>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  safe: { flex: 1, backgroundColor: '#000' },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  loadingTxt: { color: '#AAA', marginTop: 12, fontSize: 14 },
  overlay: { flex: 1, justifyContent: 'space-between' },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 10,
  },
  iconBtn: {
    width: 44, height: 44,
    backgroundColor: 'rgba(0,0,0,0.45)',
    borderRadius: 22,
    justifyContent: 'center', alignItems: 'center',
  },
  backBtn: {
    position: 'absolute', top: 50, left: 16,
    padding: 10, backgroundColor: 'rgba(0,0,0,0.4)', borderRadius: 20,
  },
  timerBadge: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: 'rgba(0,0,0,0.6)',
    paddingHorizontal: 12, paddingVertical: 6,
    borderRadius: 20,
  },
  recDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#FF3B30' },
  timerTxt: { color: '#FFF', fontSize: 14, fontWeight: '600', fontVariant: ['tabular-nums'] },
  footer: { alignItems: 'center', paddingBottom: 40 },
  hint: { color: 'rgba(255,255,255,0.6)', fontSize: 12, marginBottom: 16 },
  recBtn: {
    width: 76, height: 76,
    borderRadius: 38,
    borderWidth: 4, borderColor: '#FFF',
    justifyContent: 'center', alignItems: 'center',
  },
  recBtnActive: { borderColor: '#FF3B30' },
  recInner: { width: 58, height: 58, borderRadius: 29, backgroundColor: '#FF3B30' },
  recInnerActive: { width: 30, height: 30, borderRadius: 6 },
});
