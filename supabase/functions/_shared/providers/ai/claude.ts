// Real provider: Claude through the Anthropic Messages API, with a JSON-schema output.
// The model id comes from app_config `ai.model`, so it can be changed without a
// redeploy. Anthropic does not train on API inputs by default; photos are sent inline
// (base64) and never uploaded to the Files API, so nothing stays on their side to delete.

import Anthropic from 'npm:@anthropic-ai/sdk@0.131.0';
import { encodeBase64 } from 'jsr:@std/encoding@1/base64';
import { OUTPUT_SCHEMA, SYSTEM_PROMPT, userPrompt } from './prompt.ts';
import type { ProfileAnalysisInput, ProfileAnalysisProvider } from './types.ts';

export type Effort = 'low' | 'medium' | 'high';

// Server-side refusal fallback is only accepted by these model families.
const FALLBACK_MODELS = /^claude-(opus-5|fable-5|sonnet-5-5)/;

export class ClaudeAiProvider implements ProfileAnalysisProvider {
  private readonly client: Anthropic;

  constructor(readonly model: string, private readonly effort: Effort, apiKey: string) {
    this.client = new Anthropic({ apiKey, timeout: 90_000, maxRetries: 1 });
  }

  async analyze(input: ProfileAnalysisInput): Promise<unknown> {
    const fallback = FALLBACK_MODELS.test(this.model);
    const response = await this.client.beta.messages.create({
      model: this.model,
      max_tokens: 16000,
      system: SYSTEM_PROMPT,
      output_config: { effort: this.effort, format: { type: 'json_schema', schema: OUTPUT_SCHEMA } },
      ...(fallback ? { betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default' as const } : {}),
      messages: [
        {
          role: 'user',
          content: [
            ...input.photos.map((p) => ({
              type: 'image' as const,
              source: { type: 'base64' as const, media_type: p.contentType, data: encodeBase64(p.image) },
            })),
            { type: 'text' as const, text: userPrompt(input) },
          ],
        },
      ],
    });

    if (response.stop_reason === 'refusal') throw new Error('ai refusal');
    if (response.stop_reason === 'max_tokens') throw new Error('ai answer truncated');
    const text = response.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    return JSON.parse(text);
  }
}
