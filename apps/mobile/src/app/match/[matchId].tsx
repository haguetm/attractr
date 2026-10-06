// A match's profile. Right after a mutual like (?new=1) it doubles as the
// "C'est un match !" screen.

import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { ActivityIndicator } from 'react-native';
import { ProfileCardView } from '../../components/ProfileCardView';
import { Button, ErrorText, Screen } from '../../components/ui';
import { useSession } from '../../features/session/SessionProvider';
import { api, type MatchSummary, type ProfileCard } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { colors } from '../../theme';

export default function MatchScreen() {
  const { t } = useTranslation();
  const { matchId, new: isNew } = useLocalSearchParams<{ matchId: string; new?: string }>();
  const { profile } = useSession();
  const [card, setCard] = useState<ProfileCard | null>(null);
  const [summary, setSummary] = useState<MatchSummary | null>(null);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    Promise.all([api.getMatchProfile(matchId), api.getMyMatches()])
      .then(([c, matches]) => {
        setCard(c);
        setSummary(matches.find((m) => m.match_id === matchId) ?? null);
      })
      .catch(setError);
  }, [matchId]);

  const openChat = () => summary && router.replace({ pathname: '/chat/[conversationId]', params: { conversationId: summary.conversation_id, matchId } });

  return (
    <Screen
      title={isNew ? t('match.title') : (card?.first_name ?? '')}
      subtitle={isNew ? t('match.subtitle') : undefined}
      footer={
        <>
          <Button label={t('match.write')} onPress={openChat} disabled={!summary} />
          <Button label={isNew ? t('match.later') : t('common.back')} variant="ghost" onPress={() => router.back()} />
        </>
      }
    >
      {card ? <ProfileCardView card={card} alcoholFree={profile?.alcohol_free_icons ?? false} /> : null}
      {!card && !error ? <ActivityIndicator color={colors.coral} /> : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
