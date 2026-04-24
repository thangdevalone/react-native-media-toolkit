import { Ionicons } from '@expo/vector-icons';

import {
  ActivityIndicator,
  Image,
  StatusBar,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import CropOverlay from '../components/CropOverlay';
import { T } from '../theme';
import type { CropBox } from '../types';

interface Props {
  srcUri: string;
  crop: CropBox;
  prevSz: { w: number; h: number };
  loading: boolean;
  opLabel: string;
  onBack: () => void;
  onApply: () => void;
  onLayout: (w: number, h: number) => void;
  onCropCommit: (c: CropBox) => void;
}

export default function CropImageScreen({
  srcUri, crop, prevSz, loading, opLabel,
  onBack, onApply, onLayout, onCropCommit,
}: Props) {
  return (
    <View style={{ flex: 1, backgroundColor: '#000' }}>
      <StatusBar barStyle="light-content" backgroundColor="#000" translucent={false} />
      <SafeAreaView style={{ flex: 1 }}>
        <View style={s.header}>
          <TouchableOpacity style={s.backBtn} onPress={onBack}>
            <Ionicons name="chevron-back" size={24} color={T.text} />
          </TouchableOpacity>
          <Text style={s.title}>CROP IMAGE</Text>
          <TouchableOpacity style={s.nextBtn} onPress={onApply}>
            <Text style={s.nextTxt}>Apply</Text>
          </TouchableOpacity>
        </View>

        <View
          style={{ flex: 1 }}
          onLayout={(e) => onLayout(e.nativeEvent.layout.width, e.nativeEvent.layout.height)}
        >
          <Image source={{ uri: srcUri }} style={{ flex: 1 }} resizeMode="contain" />
          {prevSz.w > 0 && (
            <CropOverlay
              initialCrop={crop}
              containerW={prevSz.w}
              containerH={prevSz.h}
              onCommit={onCropCommit}
              accentColor={T.teal}
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
