// Group chat: realtime messages with the sender's first name. Members only.

import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { FlatList, KeyboardAvoidingView, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Button, ErrorText } from '../../../components/ui';
import { useSession } from '../../../features/session/SessionProvider';
import { track } from '../../../lib/analytics';
import { api, type ChatMessage, type GroupDetail } from '../../../lib/api';
import { errorMessage } from '../../../lib/errors';
import { supabase } from '../../../lib/supabase';
import { useSubmit } from '../../../lib/useSubmit';
import { colors, font, radius, spacing } from '../../../theme';

export default function GroupChatScreen() {
  const { t } = useTranslation();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { profile } = useSession();
  const [group, setGroup] = useState<GroupDetail | null>(null);
  const [people, setPeople] = useState<Record<string, string>>({});
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState('');
  const { busy, error, run } = useSubmit();
  const conversationId = group?.conversation_id;

  const loadGroup = useCallback(() => {
    void api.getGroup(id).then(setGroup).catch(() => router.back());
  }, [id]);
  useEffect(loadGroup, [loadGroup]);

  useEffect(() => {
    if (!conversationId) return;
    void api.getMessages(conversationId).then(setMessages).catch(() => undefined);
    void api.getConversationPeople(conversationId).then(setPeople).catch(() => undefined);
    void api.markRead(conversationId).catch(() => undefined);
    const channel = supabase
      .channel(`group-${conversationId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages', filter: `conversation_id=eq.${conversationId}` }, (payload) => {
        const message = payload.new as ChatMessage;
        setMessages((prev) => (prev.some((m) => m.id === message.id) ? prev : [message, ...prev]));
        void api.markRead(conversationId).catch(() => undefined);
      })
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [conversationId]);

  const send = () =>
    run(async () => {
      if (!conversationId || !draft.trim()) return;
      await api.sendMessage(conversationId, draft.trim());
      track('message_sent', { kind: 'group' });
      setDraft('');
      setMessages(await api.getMessages(conversationId));
    });

  return (
    <SafeAreaView style={styles.safe} edges={['top', 'bottom']}>
      <View style={styles.header}>
        <Pressable accessibilityRole="button" onPress={() => router.back()} hitSlop={8}>
          <Text style={styles.headerLink}>{t('common.back')}</Text>
        </Pressable>
        <Text style={font.label} numberOfLines={1}>{group?.name ?? ''}</Text>
        <Pressable accessibilityRole="button" onPress={() => router.push({ pathname: '/group/[id]/info', params: { id } })} hitSlop={8}>
          <Text style={styles.headerLink}>{t('group.info')}</Text>
        </Pressable>
      </View>
      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <FlatList
          inverted
          data={messages}
          keyExtractor={(m) => String(m.id)}
          contentContainerStyle={styles.list}
          renderItem={({ item }) => {
            const mine = item.sender_id === profile?.id;
            return (
              <View style={[styles.bubble, mine ? styles.mine : styles.theirs]}>
                {!mine ? <Text style={styles.sender}>{people[item.sender_id] ?? '…'}</Text> : null}
                <Text style={[styles.body, mine && styles.bodyMine]}>{item.body}</Text>
              </View>
            );
          }}
        />
        <ErrorText message={error ? errorMessage(t, error) : null} />
        <View style={styles.composer}>
          <TextInput value={draft} onChangeText={setDraft} placeholder={t('group.placeholder')} placeholderTextColor={colors.textMuted} multiline maxLength={2000} style={styles.input} />
          <Button label={t('chat.send')} onPress={send} loading={busy} disabled={!draft.trim()} />
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.cream },
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.md, paddingHorizontal: spacing.lg, paddingVertical: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.border },
  headerLink: { color: colors.navy, fontWeight: '700', fontSize: 15 },
  list: { padding: spacing.md, gap: spacing.sm },
  bubble: { maxWidth: '80%', paddingHorizontal: spacing.md, paddingVertical: spacing.sm, borderRadius: radius.lg, gap: 2 },
  mine: { alignSelf: 'flex-end', backgroundColor: colors.coral },
  theirs: { alignSelf: 'flex-start', backgroundColor: colors.white },
  sender: { fontSize: 12, fontWeight: '700', color: colors.navy },
  body: { fontSize: 16, color: colors.text },
  bodyMine: { color: colors.white },
  composer: { flexDirection: 'row', alignItems: 'flex-end', gap: spacing.sm, padding: spacing.md, borderTopWidth: 1, borderTopColor: colors.border },
  input: { flex: 1, minHeight: 44, maxHeight: 120, borderRadius: radius.md, borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.white, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, fontSize: 16, color: colors.text },
});
