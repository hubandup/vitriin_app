// Lecture et validation des secrets, une seule fois au démarrage du worker.
//
// On échoue au boot plutôt qu'au premier appel : un secret manquant ou mal
// renseigné doit se voir dans les logs de déploiement, pas dans une erreur 500
// au milieu d'un flux OAuth chez un commerçant.
//
// « Non vide » ne suffit pas. Un `META_APP_SECRET=COLLER_ICI` oublié passerait
// cette porte, les quatre fonctions démarreraient normalement, et l'échec
// n'apparaîtrait qu'au premier échange OAuth — sous la forme d'un
// « Invalid appsecret » renvoyé par Meta, qui ne désigne pas la cause. D'où la
// validation de FORME ci-dessous, secret par secret.

/**
 * Valeurs de remplissage qu'on retrouve dans un fichier d'exemple recopié trop
 * vite. Aucune n'est un secret légitime.
 */
const SENTINELS: RegExp[] = [
  /^coller/i,
  /^a[_-]?remplir/i,
  /^votre[_-]/i,
  /^your[_-]/i,
  /^change[_-]?me$/i,
  /^todo$/i,
  /^tbd$/i,
  /^x{3,}$/i,
  /^\.{3,}$/,
  /^<.*>$/,
  /^".*"$/,
];

type Validator = (value: string) => string | null;

function required(name: string, validate?: Validator): string {
  const value = Deno.env.get(name)?.trim();

  if (!value) {
    throw new Error(
      `Secret manquant : ${name}. ` +
        `Poser avec « supabase secrets set ${name}=... », ou depuis ` +
        `Dashboard → Project Settings → Edge Functions → Secrets.`,
    );
  }

  if (SENTINELS.some((pattern) => pattern.test(value))) {
    // Le message ne cite pas la valeur : même une sentinelle part dans les logs.
    throw new Error(
      `Secret ${name} laissé à sa valeur de remplissage. ` +
        `Renseigner la vraie valeur avant de déployer.`,
    );
  }

  const problem = validate?.(value);
  if (problem) {
    throw new Error(`Secret ${name} invalide : ${problem}`);
  }

  return value;
}

function optional(name: string): string | null {
  const value = Deno.env.get(name)?.trim();
  return value ? value : null;
}

// -----------------------------------------------------------------------------
// Validateurs
// -----------------------------------------------------------------------------

/** Identifiants Meta : des entiers longs, jamais autre chose. */
const numericId: Validator = (v) =>
  /^\d{8,25}$/.test(v) ? null : "attendu un identifiant numérique Meta.";

/** Un App Secret Meta est une chaîne de 32 caractères hexadécimaux. */
const appSecret: Validator = (v) =>
  /^[0-9a-f]{32}$/i.test(v)
    ? null
    : `attendu 32 caractères hexadécimaux, reçu ${v.length} caractère(s). ` +
      "Meta → Paramètres → De base → Clé secrète.";

const callbackUrl: Validator = (v) => {
  if (!v.startsWith("https://")) return "doit commencer par https://.";
  if (v.endsWith("/")) {
    return "ne doit pas finir par un slash — Meta compare l'URI caractère " +
      "pour caractère avec celle déclarée dans le tableau de bord.";
  }
  if (!v.endsWith("/meta-oauth-callback")) {
    return "doit pointer sur la fonction meta-oauth-callback.";
  }
  return null;
};

/** Clé HMAC du paramètre `state`. 32 octets en base64 → 44 caractères. */
const hmacKey: Validator = (v) =>
  v.length >= 32
    ? null
    : `trop courte (${v.length} caractères). Générer avec ` +
      "« openssl rand -base64 32 ».";

/**
 * Clé AES-256 : exactement 32 octets une fois le base64 décodé.
 *
 * `crypto.ts` refait ce contrôle, mais il n'y intervient qu'au premier
 * chiffrement — c'est-à-dire chez un commerçant, en plein flux OAuth. Le
 * remonter ici le transforme en échec de déploiement.
 */
const aes256Key: Validator = (v) => {
  let bytes: number;
  try {
    bytes = atob(v).length;
  } catch {
    return "n'est pas du base64 valide. Générer avec « openssl rand -base64 32 ».";
  }
  return bytes === 32
    ? null
    : `fait ${bytes} octets une fois décodée, il en faut 32 (AES-256). ` +
      "Générer avec « openssl rand -base64 32 ».";
};

const graphVersion: Validator = (v) =>
  /^v\d+\.\d+$/.test(v) ? null : "attendu la forme « v25.0 ».";

// -----------------------------------------------------------------------------

/**
 * Version de l'API Graph. Volontairement un secret et non une constante : Meta
 * déprécie les versions tous les ~2 ans, et on ne veut pas redéployer du code
 * pour ça. La valeur exacte est à relever dans le tableau de bord Meta.
 */
const GRAPH_VERSION = optional("META_GRAPH_VERSION") ?? "v25.0";

if (graphVersion(GRAPH_VERSION)) {
  throw new Error(
    `META_GRAPH_VERSION invalide : « ${GRAPH_VERSION} ». Attendu « v25.0 ».`,
  );
}

export const env = {
  metaAppId: required("META_APP_ID", numericId),
  metaAppSecret: required("META_APP_SECRET", appSecret),
  metaConfigId: required("META_CONFIG_ID", numericId),
  metaRedirectUri: required("META_REDIRECT_URI", callbackUrl),
  metaStateSecret: required("META_STATE_SECRET", hmacKey),
  tokenEncryptionKey: required("TOKEN_ENCRYPTION_KEY", aes256Key),

  graphVersion: GRAPH_VERSION,
  graphBase: `https://graph.facebook.com/${GRAPH_VERSION}`,
  dialogBase: `https://www.facebook.com/${GRAPH_VERSION}/dialog/oauth`,

  // Optionnel : si absent, meta-oauth-callback s'arrête sur sa page de
  // confirmation. C'est le mode de travail en développement — Expo Go sert
  // l'app sous un schéma exp:// qui change à chaque session, impossible à
  // figer dans un secret.
  appReturnUrl: optional("APP_RETURN_URL"),

  // Injectés par la plateforme. Le préfixe SUPABASE_ est réservé : on ne peut
  // pas les poser soi-même, et ils n'ont pas à l'être.
  supabaseUrl: required("SUPABASE_URL"),
  serviceRoleKey: required("SUPABASE_SERVICE_ROLE_KEY"),
  // Les projets récents exposent la clé publique sous SUPABASE_PUBLISHABLE_KEY.
  // SUPABASE_ANON_KEY reste injectée pour compatibilité — on accepte les deux
  // plutôt que d'échouer au boot selon l'âge du projet.
  anonKey: optional("SUPABASE_ANON_KEY") ??
    optional("SUPABASE_PUBLISHABLE_KEY") ??
    required("SUPABASE_ANON_KEY"),

  // Origines autorisées à appeler les fonctions depuis un navigateur.
  // `*` par défaut en local uniquement ; en production, poser la liste.
  allowedOrigins: (optional("ALLOWED_ORIGINS") ?? "*")
    .split(",")
    .map((o) => o.trim())
    .filter(Boolean),
};

/**
 * Toutes les valeurs qui ne doivent JAMAIS apparaître dans un log.
 * Consommé par redact() dans meta.ts.
 */
export const SECRET_VALUES: string[] = [
  env.metaAppSecret,
  env.metaStateSecret,
  env.tokenEncryptionKey,
  env.serviceRoleKey,
];
