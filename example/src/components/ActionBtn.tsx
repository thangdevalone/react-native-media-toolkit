import { Ionicons } from '@expo/vector-icons';

import { StyleSheet, Text, TouchableOpacity } from 'react-native';

interface Props {
  label: string;
  icon: string;
  color: string;
  onPress: () => void;
  disabled?: boolean;
}

export default function ActionBtn({ label, icon, color, onPress, disabled }: Props) {
  return (
    <TouchableOpacity
      style={[
        s.btn,
        {
          backgroundColor: color + '22',
          borderColor: color + '55',
          opacity: disabled ? 0.4 : 1,
        },
      ]}
      onPress={onPress}
      disabled={!!disabled}
      activeOpacity={0.7}
    >
      <Ionicons name={icon as any} size={14} color={color} />
      <Text style={[s.txt, { color }]}>{label}</Text>
    </TouchableOpacity>
  );
}

const s = StyleSheet.create({
  btn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderRadius: 10,
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderWidth: 1,
  },
  txt: { fontSize: 13, fontWeight: '700' },
});
