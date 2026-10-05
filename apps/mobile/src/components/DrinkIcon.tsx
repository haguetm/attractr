import type { Drink } from '@attractr/shared';
import { Text } from 'react-native';

// Placeholder glyphs until the illustrated icon set exists. The alcohol-free
// variant is the user's choice (spec §1).
const ICONS: Record<Drink, string> = { wine: '🍷', coffee: '☕', cocktail: '🍸', beer: '🍺' };
const ALCOHOL_FREE_ICONS: Record<Drink, string> = { wine: '🍇', coffee: '☕', cocktail: '🧃', beer: '🥤' };

export function DrinkIcon({ drink, alcoholFree = false, size = 28 }: { drink: Drink; alcoholFree?: boolean; size?: number }) {
  return (
    <Text style={{ fontSize: size }} accessible={false}>
      {(alcoholFree ? ALCOHOL_FREE_ICONS : ICONS)[drink]}
    </Text>
  );
}
