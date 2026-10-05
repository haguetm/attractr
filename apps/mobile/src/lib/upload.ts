import { AppError, errorCode } from './errors';
import { supabase } from './supabase';

const randomName = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

/** Uploads a local image under `<userId>/` in a private bucket and returns its path. */
export async function uploadImage(bucket: 'photos' | 'selfies', userId: string, uri: string, mimeType?: string | null) {
  const contentType = mimeType ?? 'image/jpeg';
  const extension = contentType.split('/')[1] ?? 'jpg';
  const path = `${userId}/${randomName()}.${extension}`;
  const body = await (await fetch(uri)).arrayBuffer();
  const { error } = await supabase.storage.from(bucket).upload(path, body, { contentType, upsert: false });
  if (error) throw new AppError(errorCode(error) === 'generic' ? 'storage_object_not_found' : errorCode(error));
  return path;
}

/** Short-lived URL to display one of the user's own photos. */
export async function signedPhotoUrl(path: string): Promise<string | null> {
  const { data } = await supabase.storage.from('photos').createSignedUrl(path, 3600);
  return data?.signedUrl ?? null;
}
