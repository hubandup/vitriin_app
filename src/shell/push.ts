/** Notifications : autorisation, jeton Expo et ouverture au toucher. Aucune clé ici, l'envoi se fait côté serveur. */
import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: false,
    shouldSetBadge: false,
  }),
});

/** Null tant que le projet EAS n'existe pas, sur simulateur, ou si l'utilisateur refuse. */
export async function getPushToken(): Promise<string | null> {
  const projectId = Constants.expoConfig?.extra?.eas?.projectId as string | undefined;
  if (!projectId || !Device.isDevice) return null;
  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', {
      name: 'Promos et campagnes',
      importance: Notifications.AndroidImportance.DEFAULT,
    });
  }
  const current = await Notifications.getPermissionsAsync();
  const granted = current.granted || (await Notifications.requestPermissionsAsync()).granted;
  if (!granted) return null;
  return (await Notifications.getExpoPushTokenAsync({ projectId })).data;
}

/** Appelle `onOpen` avec l'adresse portée par la notification touchée, y compris au démarrage de l'app. */
export function listenToNotificationTaps(onOpen: (url: string) => void) {
  const read = (r: Notifications.NotificationResponse | null) => {
    const url = r?.notification.request.content.data?.url;
    if (typeof url === 'string') onOpen(url);
  };
  read(Notifications.getLastNotificationResponse());
  const sub = Notifications.addNotificationResponseReceivedListener(read);
  return () => sub.remove();
}
