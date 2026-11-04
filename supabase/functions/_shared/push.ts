// Notifications de l'app mobile, envoyées par le service Expo (aucune clé côté client).
// Un jeton refusé par Expo (app désinstallée) est retiré de device_tokens.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export type PushMessage = { to: string; title: string; body: string; data?: Record<string, string> };

const EXPO_PUSH = "https://exp.host/--/api/v2/push/send";

export async function sendPush(admin: SupabaseClient, messages: PushMessage[]) {
  for (let i = 0; i < messages.length; i += 100) {
    const batch = messages.slice(i, i + 100);
    const res = await fetch(EXPO_PUSH, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(batch),
    });
    if (!res.ok) throw new Error(`Expo push ${res.status}`);
    const { data } = await res.json() as { data?: { status: string; details?: { error?: string } }[] };
    const gone = batch
      .filter((_, k) => data?.[k]?.details?.error === "DeviceNotRegistered")
      .map((m) => m.to);
    if (gone.length) await admin.from("device_tokens").delete().in("token", gone);
  }
}
