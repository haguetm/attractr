// Match chat (spec §5): realtime messages, the 24 h first-message countdown with a
// one-time extension, and unmatch. Exists only inside a match (or a validated group).

import { timeLeft } from '@attractr/shared';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { FlatList, KeyboardAvoidingView, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Button, ErrorText, Note } from '../../components/ui';
import { useSession } from '../../features/session/SessionProvider';
import { api, type ChatMessage, type MatchOuting, type MatchSummary } from '../../lib/api';
import { errorCode, errorMessage } from '../../lib/errors';
import { formatDateTime } from '../../lib/format';
import { supabase } from '../../lib/supabase';
import { useSubmit } from '../../lib/useSubmit';
import { colors, font, radius, spacing } from '../../theme';

export default function ChatScreen() {
  const { t } = useTranslation();
  const { conversationId, matchId } = useLocalSearchParams<{ conversationId: string; matchId: string }>();
  const { profile } = useSession();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [match, setMatch] = useState<MatchSummary | null>(null);
  const [closed, setClosed] = useState(false);
  const [outing, setOuting] = useState<MatchOuting | null>(null);
  const [draft, setDraft] = useState('');
  const [menu, setMenu] = useState<'closed' | 'open' | 'unmatch' | 'block'>('closed');
  const { busy, error, run } = useSubmit();

  const refreshMatch = useCallback(async () => {
    const list = await api.getMyMatches();
    const found = list.find((m) => m.conversation_id === conversationId) ?? null;
    setMatch(found);
    setClosed(found === null);
  }, [conversationId]);

  useEffect(() => {
    void api.getMessages(conversationId).then(setMessages).catch(() => undefined);
    void refreshMatch().catch(() => undefined);
    void api.getMatchOuting(matchId).then(setOuting).catch(() => undefined);
    void api.markRead(conversationId).catch(() => undefined);

    // RLS on messages scopes realtime events to conversations the user belongs to.
    const channel = supabase
      .channel(`chat-${conversationId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'messages', filter: `conversation_id=eq.${conversationId}` },
        (payload) => {
          const message = payload.new as ChatMessage;
          setMessages((prev) => (prev.some((m) => m.id === message.id) ? prev : [message, ...prev]));
          void api.markRead(conversationId).catch(() => undefined);
        },
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [conversationId, matchId, refreshMatch]);

  const send = () =>
    run(async () => {
      const body = draft.trim();
      if (!body) return;
      try {
        await api.sendMessage(conversationId, body);
      } catch (e) {
        if (['match_expired', 'match_closed', 'conversation_not_found'].includes(errorCode(e))) setClosed(true);
        throw e;
      }
      setDraft('');
      setMessages(await api.getMessages(conversationId));
      await refreshMatch();
    });

  const extend = () =>
    run(async () => {
      await api.extendMatch(matchId);
      await refreshMatch();
    });

  const unmatch = () =>
    run(async () => {
      await api.unmatch(matchId);
      router.back();
    });

  const block = () =>
    run(async () => {
      if (match) await api.blockProfile(match.other.id);
      router.back();
    });

  const report = () => {
    setMenu('closed');
    if (match) {
      router.push({ pathname: '/report/[userId]', params: { userId: match.other.id, name: match.other.first_name, conversationId } });
    }
  };

  const left = match?.first_message_deadline ? timeLeft(match.first_message_deadline) : null;

  return (
    <SafeAreaView style={styles.safe} edges={['top', 'bottom']}>
      <View style={styles.header}>
        <Pressable accessibilityRole="button" onPress={() => router.back()} hitSlop={8}>
          <Text style={styles.headerLink}>{t('common.back')}</Text>
        </Pressable>
        <Pressable accessibilityRole="button" onPress={() => router.push({ pathname: '/match/[matchId]', params: { matchId } })}>
          <Text style={font.label}>{match?.other.first_name ?? ''}</Text>
        </Pressable>
        <Pressable accessibilityRole="button" onPress={() => setMenu(menu === 'closed' ? 'open' : 'closed')} hitSlop={8}>
          <Text style={styles.headerLink}>⋯</Text>
        </Pressable>
      </View>

      {menu === 'open' ? (
        <View style={styles.banner}>
          <Button label={t('chat.menuProfile')} variant="secondary" onPress={() => { setMenu('closed'); router.push({ pathname: '/match/[matchId]', params: { matchId } }); }} />
          <Button label={t('chat.menuReport')} variant="secondary" onPress={report} />
          <Button label={t('chat.menuBlock')} variant="secondary" onPress={() => setMenu('block')} />
          <Button label={t('chat.menuUnmatch')} variant="secondary" onPress={() => setMenu('unmatch')} />
          <Button label={t('chat.menuClose')} variant="ghost" onPress={() => setMenu('closed')} />
        </View>
      ) : null}

      {menu === 'unmatch' || menu === 'block' ? (
        <View style={styles.banner}>
          <Note>{t(menu === 'unmatch' ? 'chat.unmatchConfirm' : 'safety.blockConfirm')}</Note>
          <Button label={t(menu === 'unmatch' ? 'chat.unmatch' : 'safety.block')} variant="danger" onPress={menu === 'unmatch' ? unmatch : block} loading={busy} />
          <Button label={t('chat.cancel')} variant="ghost" onPress={() => setMenu('closed')} />
        </View>
      ) : null}

      {left && !left.expired ? (
        <View style={styles.banner}>
          <Text style={font.small}>{t('chat.firstMessageBanner', { hours: left.hours, minutes: left.minutes })}</Text>
          {match && match.extensions_left > 0 ? (
            <Button label={t('chat.extend')} variant="secondary" onPress={extend} loading={busy} />
          ) : null}
        </View>
      ) : null}

      {!closed && !left ? (
        <Pressable
          accessibilityRole="button"
          onPress={() => router.push({ pathname: '/outing/[matchId]', params: { matchId } })}
          style={styles.outing}
        >
          <Text style={styles.outingText}>
            {outing && outing.status === 'planned'
              ? t('outing.planned', { date: formatDateTime(outing.starts_at), place: outing.place })
              : t('outing.propose')}
          </Text>
        </Pressable>
      ) : null}

      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <FlatList
          inverted
          data={messages}
          keyExtractor={(m) => String(m.id)}
          contentContainerStyle={styles.list}
          ListEmptyComponent={<Text style={[font.small, styles.empty]}>{t('chat.empty')}</Text>}
          ListFooterComponent={<Text style={[font.small, styles.tip]}>{t('chat.scamTip')}</Text>}
          renderItem={({ item }) => {
            const mine = item.sender_id === profile?.id;
            return (
              <View style={[styles.bubble, mine ? styles.mine : styles.theirs]}>
                <Text style={[styles.body, mine && styles.bodyMine]}>{item.body}</Text>
              </View>
            );
          }}
        />
        <ErrorText message={error ? errorMessage(t, error) : null} />
        {closed ? (
          <Note>{t('chat.closed')}</Note>
        ) : (
          <View style={styles.composer}>
            <TextInput
              value={draft}
              onChangeText={setDraft}
              placeholder={t('chat.placeholder')}
              placeholderTextColor={colors.textMuted}
              multiline
              maxLength={2000}
              style={styles.input}
            />
            <Button label={t('chat.send')} onPress={send} loading={busy} disabled={!draft.trim()} />
          </View>
        )}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.cream },
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.lg, paddingVertical: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.border },
  headerLink: { color: colors.navy, fontWeight: '700', fontSize: 15 },
  banner: { margin: spacing.md, padding: spacing.md, borderRadius: radius.md, backgroundColor: colors.coralSoft, gap: spacing.sm },
  list: { padding: spacing.md, gap: spacing.sm },
  outing: { marginHorizontal: spacing.md, marginTop: spacing.sm, padding: spacing.sm, borderRadius: radius.md, backgroundColor: colors.navySoft },
  outingText: { color: colors.navy, fontWeight: '600', textAlign: 'center' },
  empty: { textAlign: 'center', marginTop: spacing.xl, transform: [{ scaleY: -1 }] },
  tip: { textAlign: 'center', marginBottom: spacing.md },
  bubble: { maxWidth: '80%', paddingHorizontal: spacing.md, paddingVertical: spacing.sm, borderRadius: radius.lg },
  mine: { alignSelf: 'flex-end', backgroundColor: colors.coral },
  theirs: { alignSelf: 'flex-start', backgroundColor: colors.white },
  body: { fontSize: 16, color: colors.text },
  bodyMine: { color: colors.white },
  composer: { flexDirection: 'row', alignItems: 'flex-end', gap: spacing.sm, padding: spacing.md, borderTopWidth: 1, borderTopColor: colors.border },
  input: { flex: 1, minHeight: 44, maxHeight: 120, borderRadius: radius.md, borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.white, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, fontSize: 16, color: colors.text },
});
