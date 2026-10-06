import { type ConfigReader, providerMode } from '../config.ts';
import { ClaudeAiProvider, type Effort } from './claude.ts';
import { type MockAiOutcome, MockAiProvider } from './mock.ts';
import type { ProfileAnalysisProvider } from './types.ts';

export { guardAnalysis } from './guard.ts';
export type { AnalysisPhoto, ProfileAnalysis, ProfileAnalysisInput, ProfileAnalysisProvider } from './types.ts';

export async function aiProvider(config: ConfigReader): Promise<ProfileAnalysisProvider> {
  const mode = await providerMode(config, 'ai');
  if (mode === 'mock') {
    return new MockAiProvider(((await config.get('providers.mock_ai_outcome')) ?? 'ok') as MockAiOutcome);
  }
  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY missing');
  const model = ((await config.get('ai.model')) ?? 'claude-opus-5-5') as string;
  const effort = ((await config.get('ai.effort')) ?? 'medium') as Effort;
  return new ClaudeAiProvider(model, effort, apiKey);
}
