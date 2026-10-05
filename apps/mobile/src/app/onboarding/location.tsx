// Position or home city. Asked early because the country decides which sensitive
// questions exist (Q21). The exact position goes to the Edge Function only and is
// snapped to ~1 km before storage.

import * as Location from 'expo-location';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Text } from 'react-native';
import { Button, ErrorText, Field, Note, Screen, Section } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { useSession } from '../../features/session/SessionProvider';
import { api } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { useSubmit } from '../../lib/useSubmit';
import { font } from '../../theme';

export default function LocationScreen() {
  const { t } = useTranslation();
  const { refreshProfile } = useSession();
  const { goNext, progress, refreshSwitches } = useOnboarding();
  const [city, setCity] = useState('');
  const [denied, setDenied] = useState(false);
  const { busy, error, run } = useSubmit();

  const finish = async (result: { countryCode: string | null }) => {
    await refreshSwitches(result.countryCode);
    await refreshProfile();
    await goNext('location');
  };

  const useDevice = () =>
    run(async () => {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') {
        setDenied(true);
        return;
      }
      const position = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
      await finish(await api.updateLocation({ mode: 'device', lat: position.coords.latitude, lon: position.coords.longitude }));
    });

  const useCity = () => run(async () => finish(await api.updateLocation({ mode: 'home', query: city })));

  return (
    <Screen progress={progress('location')} title={t('location.title')} subtitle={t('location.subtitle')}>
      <Button label={t('location.useDevice')} onPress={useDevice} loading={busy} />
      {denied ? <Note>{t('location.permissionDenied')}</Note> : null}
      <Text style={[font.small, { textAlign: 'center' }]}>{t('location.or')}</Text>
      <Section title={t('location.homeLabel')}>
        <Field value={city} onChangeText={setCity} placeholder={t('location.homePlaceholder')} autoComplete="postal-address-locality" onSubmitEditing={useCity} />
        <Button label={t('location.search')} variant="secondary" onPress={useCity} disabled={city.trim().length < 2 || busy} />
      </Section>
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
