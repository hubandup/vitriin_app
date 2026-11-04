/**
 * La coquille : espace choisi, écrans web, barre d'onglets, liens, notifications.
 * Les écrans restent ceux de app.vitriin.co ; le contrat avec eux est dans
 * web/espace-magasin/public/shell.js et les règles dans ./rules.ts.
 */
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Linking from 'expo-linking';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import * as WebBrowser from 'expo-web-browser';
import { type ComponentType, type RefAttributes, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, BackHandler, KeyboardAvoidingView, Platform, Share, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { WebView, type WebViewMessageEvent, type WebViewNavigation } from 'react-native-webview';
import type { AndroidWebViewProps, IOSWebViewProps, ShouldStartLoadRequest, WebViewErrorEvent, WebViewHttpErrorEvent, WebViewOpenWindowEvent } from 'react-native-webview/lib/WebViewTypes';

import { colors } from '../theme';
import { Offline } from './Offline';
import { getPushToken, listenToNotificationTaps } from './push';
import { navigationFor, OAUTH_RETURN, parseBridge, parseLink, SPACE_PATH, WEB_ORIGIN, type BridgeMessage, type Link, type Space } from './rules';
import { TabBar } from './TabBar';
import { Welcome } from './Welcome';

// Le type publié croise les props iOS, Android et Windows et se réduit à `never` : on garde iOS et Android.
const Web = WebView as unknown as ComponentType<IOSWebViewProps & AndroidWebViewProps & RefAttributes<WebView>>;

const SPACE_KEY = 'vitriin-space';
const APP_VERSION = '1.0';

type WebState = { tabs: boolean; tab: string | null; badge: number; dark: boolean };
const NO_TABS: WebState = { tabs: false, tab: null, badge: 0, dark: false };

export function Shell() {
  const insets = useSafeAreaInsets();
  const web = useRef<WebView>(null);
  const canGoBack = useRef(false);

  const [booted, setBooted] = useState(false);
  const [space, setSpace] = useState<Space | null>(null);
  const [path, setPath] = useState('');
  const [mount, setMount] = useState(0); // change = rechargement complet
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const [state, setState] = useState<WebState>(NO_TABS);

  const show = useCallback((next: Space, nextPath = SPACE_PATH[next]) => {
    setSpace(next);
    setPath(nextPath);
    setState(NO_TABS);
    setFailed(false);
    setLoading(true);
    setMount((n) => n + 1);
    AsyncStorage.setItem(SPACE_KEY, next).catch(() => {});
  }, []);

  const follow = useCallback((link: Link | null) => {
    if (!link) return;
    show(link.kind === 'oauth' ? 'magasin' : link.space, link.path);
  }, [show]);

  // Démarrage : un lien entrant passe avant l'espace mémorisé.
  useEffect(() => {
    (async () => {
      const incoming = parseLink((await Linking.getInitialURL()) ?? '');
      if (incoming) follow(incoming);
      else {
        const saved = await AsyncStorage.getItem(SPACE_KEY).catch(() => null);
        if (saved === 'client' || saved === 'magasin') show(saved);
      }
      setBooted(true);
      SplashScreen.hideAsync().catch(() => {});
    })();
  }, [follow, show]);

  useEffect(() => {
    const sub = Linking.addEventListener('url', ({ url }) => follow(parseLink(url)));
    return () => sub.remove();
  }, [follow]);

  useEffect(() => listenToNotificationTaps((url) => follow(parseLink(url))), [follow]);

  const call = useCallback((js: string) => web.current?.injectJavaScript(`${js};true;`), []);

  // Android : le bouton retour ferme d'abord ce que la page a ouvert.
  useEffect(() => {
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      if (!space) return false;
      call('window.VitriinShell && VitriinShell.back()');
      return true;
    });
    return () => sub.remove();
  }, [space, call]);

  const openExternal = useCallback((url: string) => {
    Linking.openURL(url).catch(() => {});
  }, []);

  const authorize = useCallback(async (url: string) => {
    // Facebook refuse sa connexion dans un écran web intégré : on passe par le navigateur système.
    const start = `${WEB_ORIGIN}/retour-app/?to=${encodeURIComponent(url)}`;
    const result = await WebBrowser.openAuthSessionAsync(start, OAUTH_RETURN);
    if (result.type === 'success') follow(parseLink(result.url));
  }, [follow]);

  const onMessage = useCallback(async (event: WebViewMessageEvent) => {
    const msg: BridgeMessage | null = parseBridge(event.nativeEvent.data, event.nativeEvent.url);
    if (!msg) return;
    switch (msg.t) {
      case 'state':
        setState({ tabs: msg.tabs, tab: msg.tab, badge: msg.badge, dark: msg.dark });
        break;
      case 'auth':
        authorize(msg.url);
        break;
      case 'share':
        Share.share({ title: msg.title, message: [msg.text, msg.url].filter(Boolean).join(' ') }).catch(() => {});
        break;
      case 'space':
        show(msg.to);
        break;
      case 'push': {
        const token = await getPushToken().catch(() => null);
        if (token) call(`VitriinShell.pushToken(${JSON.stringify(token)})`);
        break;
      }
      case 'back-unhandled':
        if (canGoBack.current) web.current?.goBack();
        else BackHandler.exitApp();
        break;
    }
  }, [authorize, call, show]);

  const onShouldStart = useCallback((req: ShouldStartLoadRequest) => {
    const action = navigationFor(req.url, req.isTopFrame ?? true);
    if (action === 'external') openExternal(req.url);
    return action === 'load';
  }, [openExternal]);

  const beforeLoad = useMemo(
    () => `window.VitriinNative=Object.assign(window.VitriinNative||{},${JSON.stringify({ platform: Platform.OS, version: APP_VERSION, top: insets.top, bottom: insets.bottom })});true;`,
    [insets.top, insets.bottom],
  );

  if (!booted) return null;
  if (!space) {
    return (
      <>
        <StatusBar style="light" />
        <Welcome onChoose={(s) => show(s)} />
      </>
    );
  }

  return (
    <KeyboardAvoidingView style={styles.root} behavior={Platform.OS === 'android' ? 'height' : undefined}>
      <StatusBar style={state.dark ? 'light' : 'dark'} />
      <Web
        key={mount}
        ref={web}
        source={{ uri: WEB_ORIGIN + path }}
        style={styles.web}
        originWhitelist={['https://*', 'http://*', 'mailto:*', 'tel:*', 'about:*', 'blob:*']}
        injectedJavaScriptBeforeContentLoaded={beforeLoad}
        applicationNameForUserAgent={`VitriinApp/${APP_VERSION}`}
        onMessage={onMessage}
        onShouldStartLoadWithRequest={onShouldStart}
        onNavigationStateChange={(nav: WebViewNavigation) => { canGoBack.current = nav.canGoBack; }}
        onOpenWindow={(e: WebViewOpenWindowEvent) => openExternal(e.nativeEvent.targetUrl)}
        onLoadEnd={() => setLoading(false)}
        onError={(_e: WebViewErrorEvent) => setFailed(true)}
        onHttpError={(e: WebViewHttpErrorEvent) => {
          if (e.nativeEvent.statusCode >= 500 && e.nativeEvent.url.startsWith(WEB_ORIGIN + path)) setFailed(true);
        }}
        domStorageEnabled
        javaScriptEnabled
        sharedCookiesEnabled
        geolocationEnabled
        allowsInlineMediaPlayback
        mediaPlaybackRequiresUserAction={false}
        allowsBackForwardNavigationGestures={false}
        bounces={false}
        overScrollMode="never"
        textZoom={100}
        setSupportMultipleWindows
        contentInsetAdjustmentBehavior="never"
        automaticallyAdjustContentInsets={false}
        webviewDebuggingEnabled={__DEV__}
      />
      {state.tabs ? (
        <TabBar
          space={space}
          active={state.tab}
          badge={state.badge}
          bottomInset={insets.bottom}
          onPress={(tab) => call(`VitriinShell.tab(${JSON.stringify(tab)})`)}
        />
      ) : null}
      {loading && !failed ? (
        <View style={styles.loading}><ActivityIndicator size="large" color={colors.primary} /></View>
      ) : null}
      {failed ? (
        <Offline onRetry={() => { setFailed(false); setLoading(true); setMount((n) => n + 1); }} />
      ) : null}
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#fff' },
  web: { flex: 1, backgroundColor: '#fff' },
  loading: { ...StyleSheet.absoluteFill, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' },
});
