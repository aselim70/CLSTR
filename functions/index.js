const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

initializeApp();
const db = getFirestore();
const auth = getAuth();

/**
 * Controleert dat de aanroeper ingelogd én hoofdaccount is (admin óf
 * superadmin), en geeft naast het e-mailadres ook de rol en het bedrijfId
 * van de aanroeper terug. Zelfde rol als vroeger controleerIsAdmin() had -
 * hier uitgebreid met bedrijfId, nu er meerdere bedrijven zijn. Dit wordt
 * herhaald in elke functie hieronder omdat Cloud Functions met de Admin SDK
 * draait en dus NIET langs de Firestore Security Rules gaat.
 */
async function controleerAanroeper(request) {
  if (!request.auth || !request.auth.token || !request.auth.token.email) {
    throw new HttpsError("unauthenticated", "Je moet ingelogd zijn.");
  }
  const aanroeperEmail = request.auth.token.email.toLowerCase();
  const aanroeperDoc = await db.collection("gebruikers").doc(aanroeperEmail).get();
  const data = aanroeperDoc.exists ? aanroeperDoc.data() : {};
  if (data.rol !== "admin" && data.rol !== "superadmin") {
    throw new HttpsError("permission-denied", "Alleen hoofdaccounts mogen accounts beheren.");
  }
  return { email: aanroeperEmail, rol: data.rol, bedrijfId: data.bedrijfId ?? null };
}

/**
 * Maakt een nieuw account volledig aan: de inlog (Firebase Authentication)
 * én het gebruikers-document in Firestore (rol + bedrijfId + clusters), in
 * één keer.
 *
 * Dit moet via een Cloud Function met de Admin SDK, en kan niet rechtstreeks
 * vanuit de app met de gewone Firebase Auth-aanroep: als je vanuit de app
 * zelf een nieuw account aanmaakt, logt je eigen toestel automatisch in als
 * dát nieuwe account in plaats van als de beheerder - hier gebeurt het op de
 * server, dus de sessie van de beheerder blijft gewoon actief.
 *
 * Belangrijk (bedrijf-scheiding): een gewone admin kan hier NOOIT een ander
 * bedrijfId of een 'admin'/'superadmin'-rol doorgeven - dat zou een gat zijn
 * waarmee een admin van Bedrijf A zichzelf toegang tot Bedrijf B zou kunnen
 * geven. Het bedrijfId van het nieuwe account wordt voor een gewone admin
 * altijd geforceerd naar het EIGEN bedrijfId van de aanroeper, en de rol
 * altijd naar 'subaccount'. Alleen een superadmin mag een 'admin'-account
 * aanmaken, en moet dan zelf aangeven bij welk bedrijf dat hoort.
 *
 * Verwacht in request.data: { email, wachtwoord, rol, clusters, bedrijfId }
 * (bedrijfId is alleen verplicht/relevant als de aanroeper superadmin is)
 */
exports.maakAccountAan = onCall(async (request) => {
  const aanroeper = await controleerAanroeper(request);

  const { email, wachtwoord, rol, clusters, bedrijfId: gevraagdBedrijfId } = request.data || {};

  if (!email || typeof email !== "string" || !email.trim()) {
    throw new HttpsError("invalid-argument", "Vul een e-mailadres in.");
  }
  if (!wachtwoord || typeof wachtwoord !== "string" || wachtwoord.length < 6) {
    throw new HttpsError("invalid-argument", "Het wachtwoord moet minstens 6 tekens lang zijn.");
  }

  let doelBedrijfId;
  let nieuweRol;
  if (aanroeper.rol === "superadmin") {
    if (!gevraagdBedrijfId || typeof gevraagdBedrijfId !== "string") {
      throw new HttpsError("invalid-argument", "bedrijfId is verplicht.");
    }
    doelBedrijfId = gevraagdBedrijfId;
    nieuweRol = rol === "admin" ? "admin" : "subaccount";
  } else {
    // Gewone admin: bedrijfId en rol volledig negeren wat de client meestuurt.
    doelBedrijfId = aanroeper.bedrijfId;
    nieuweRol = "subaccount";
    // Een admin zonder eigen bedrijfId (niet-gemigreerd account) zou hier een
    // gebruiker met bedrijfId null aanmaken. Zo'n account kan daarna nergens
    // meer bij en is alleen nog via de Firebase Console te repareren.
    if (!doelBedrijfId) {
      throw new HttpsError(
        "failed-precondition",
        "Je eigen account is nog niet aan een bedrijf gekoppeld; neem contact op met de superadmin.",
      );
    }
  }

  const nieuweEmail = email.trim().toLowerCase();
  const nieuweClusters = nieuweRol === "admin"
    ? []
    : (Array.isArray(clusters) ? clusters.map((c) => String(c)) : []);

  // Bestaat er al een gebruikers-document, dan zou de .set() hieronder de
  // bestaande rol/clusters overschrijven zonder waarschuwing.
  const bestaandDoc = await db.collection("gebruikers").doc(nieuweEmail).get();
  if (bestaandDoc.exists) {
    throw new HttpsError("already-exists", "Er bestaat al een account met dit e-mailadres.");
  }

  let nieuweGebruiker;
  try {
    nieuweGebruiker = await auth.createUser({
      email: nieuweEmail,
      password: wachtwoord,
    });
  } catch (fout) {
    if (fout.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "Er bestaat al een account met dit e-mailadres.");
    }
    if (fout.code === "auth/invalid-email") {
      throw new HttpsError("invalid-argument", "Dit is geen geldig e-mailadres.");
    }
    throw new HttpsError("internal", "Aanmaken van het account is mislukt: " + fout.message);
  }

  // Mislukt het schrijven van het gebruikers-document, dan blijft er anders
  // een inlog achter zonder rol: die persoon kan wél inloggen maar nergens
  // bij, en opnieuw aanmaken lukt niet meer ("e-mailadres bestaat al"). Daarom
  // de zojuist gemaakte inlog weer opruimen.
  try {
    await db.collection("gebruikers").doc(nieuweEmail).set({
      email: nieuweEmail,
      rol: nieuweRol,
      bedrijfId: doelBedrijfId,
      clusters: nieuweClusters,
    });
  } catch (fout) {
    await auth.deleteUser(nieuweGebruiker.uid).catch(() => {});
    throw new HttpsError("internal", "Opslaan van de accountgegevens is mislukt: " + fout.message);
  }

  return { succes: true, uid: nieuweGebruiker.uid };
});

/**
 * Werkt een bestaand account bij (rol + clusters). Vervangt de vroegere
 * rechtstreekse client-`.set()` in gebruikers_beheer_page.dart - die kon per
 * ongeluk het bedrijfId wegschrijven (geen merge:true) en had geen enkele
 * server-side controle, waardoor een admin in theorie zijn eigen rol/
 * bedrijfId had kunnen aanpassen. E-mailadres en bedrijfId liggen hier vast
 * en zijn NIET aan te passen via deze functie.
 *
 * Verwacht in request.data: { email, rol, clusters }
 */
exports.bijwerkenAccount = onCall(async (request) => {
  const aanroeper = await controleerAanroeper(request);

  const { email, rol, clusters } = request.data || {};
  if (!email || typeof email !== "string" || !email.trim()) {
    throw new HttpsError("invalid-argument", "E-mailadres ontbreekt.");
  }
  const doelEmail = email.trim().toLowerCase();

  const doelDoc = await db.collection("gebruikers").doc(doelEmail).get();
  if (!doelDoc.exists) {
    throw new HttpsError("not-found", "Dit account bestaat niet (meer).");
  }
  const doelData = doelDoc.data();

  if (aanroeper.rol !== "superadmin" && doelData.bedrijfId !== aanroeper.bedrijfId) {
    throw new HttpsError("permission-denied", "Je mag alleen accounts van je eigen bedrijf bewerken.");
  }

  // Een gewone admin kan hieronder alléén 'subaccount' als uitkomst krijgen -
  // ook als het doelaccount nu admin is. Een admin die het bewerk-scherm van
  // een hoofdaccount opende en op Opslaan drukte, degradeerde dat account dus
  // ongemerkt; deed hij dat bij zichzelf, dan sloot hij zichzelf buiten het
  // accountbeheer en kon hij dat niet meer terugdraaien (promoveren tot admin
  // mag alleen de superadmin). Vandaar deze twee controles.
  if (aanroeper.rol !== "superadmin") {
    if (doelEmail === aanroeper.email) {
      throw new HttpsError("failed-precondition", "Je kunt je eigen rol niet wijzigen.");
    }
    if (doelData.rol === "admin" || doelData.rol === "superadmin") {
      throw new HttpsError("permission-denied", "Alleen de superadmin kan een hoofdaccount wijzigen.");
    }
  }

  // Een gewone admin mag geen admin/superadmin van maken - alleen subaccount.
  const nieuweRol = aanroeper.rol === "superadmin"
    ? (rol === "admin" ? "admin" : "subaccount")
    : "subaccount";
  const nieuweClusters = nieuweRol === "admin"
    ? []
    : (Array.isArray(clusters) ? clusters.map((c) => String(c)) : []);

  await db.collection("gebruikers").doc(doelEmail).update({
    rol: nieuweRol,
    clusters: nieuweClusters,
  });

  return { succes: true };
});

/**
 * Verwijdert een account volledig: zowel de inlog (Firebase Authentication)
 * als het gebruikers-document in Firestore. Bewust gekoppeld aan
 * maakAccountAan - zou je alleen het Firestore-document verwijderen, dan
 * blijft de inlog zelf bestaan en kan hetzelfde e-mailadres nooit meer
 * opnieuw aangemaakt worden via maakAccountAan.
 *
 * Verwacht in request.data: { email }
 */
exports.verwijderAccount = onCall(async (request) => {
  const aanroeper = await controleerAanroeper(request);

  const { email } = request.data || {};
  if (!email || typeof email !== "string" || !email.trim()) {
    throw new HttpsError("invalid-argument", "E-mailadres ontbreekt.");
  }
  const teVerwijderenEmail = email.trim().toLowerCase();

  if (teVerwijderenEmail === aanroeper.email) {
    throw new HttpsError("failed-precondition", "Je kunt je eigen account niet verwijderen.");
  }

  // Let op: een superadmin heeft bedrijfId null, dus die valt hier vanzelf
  // buiten het bereik van een gewone admin.
  if (aanroeper.rol !== "superadmin") {
    const doelDoc = await db.collection("gebruikers").doc(teVerwijderenEmail).get();
    if (doelDoc.exists && doelDoc.data().bedrijfId !== aanroeper.bedrijfId) {
      throw new HttpsError("permission-denied", "Je mag alleen accounts van je eigen bedrijf verwijderen.");
    }
  }

  try {
    const gebruiker = await auth.getUserByEmail(teVerwijderenEmail);
    await auth.deleteUser(gebruiker.uid);
  } catch (fout) {
    if (fout.code !== "auth/user-not-found") {
      throw new HttpsError("internal", "Verwijderen van de inlog is mislukt: " + fout.message);
    }
    // Inlog bestond al niet meer (bijv. eerder al handmatig verwijderd) -
    // gewoon doorgaan met het opruimen van het Firestore-document.
  }

  await db.collection("gebruikers").doc(teVerwijderenEmail).delete();

  return { succes: true };
});

/**
 * Alleen voor superadmin: maakt in één keer een nieuw bedrijf aan, plus het
 * eerste admin-account van dat bedrijf (inlog + gebruikers-document). Dit is
 * de enige manier waarop een nieuw bedrijf ontstaat.
 *
 * Verwacht in request.data: { bedrijfsnaam, adminEmail, adminWachtwoord }
 */
exports.maakBedrijfMetAdminAan = onCall(async (request) => {
  const aanroeper = await controleerAanroeper(request);
  if (aanroeper.rol !== "superadmin") {
    throw new HttpsError("permission-denied", "Alleen de superadmin mag nieuwe bedrijven aanmaken.");
  }

  const { bedrijfsnaam, adminEmail, adminWachtwoord } = request.data || {};
  if (!bedrijfsnaam || typeof bedrijfsnaam !== "string" || !bedrijfsnaam.trim()) {
    throw new HttpsError("invalid-argument", "Vul een bedrijfsnaam in.");
  }
  if (!adminEmail || typeof adminEmail !== "string" || !adminEmail.trim()) {
    throw new HttpsError("invalid-argument", "Vul een e-mailadres in voor de eerste admin.");
  }
  if (!adminWachtwoord || typeof adminWachtwoord !== "string" || adminWachtwoord.length < 6) {
    throw new HttpsError("invalid-argument", "Het wachtwoord moet minstens 6 tekens lang zijn.");
  }

  const nieuweAdminEmail = adminEmail.trim().toLowerCase();

  const bestaandDoc = await db.collection("gebruikers").doc(nieuweAdminEmail).get();
  if (bestaandDoc.exists) {
    throw new HttpsError("already-exists", "Er bestaat al een account met dit e-mailadres.");
  }

  // Volgorde is hier bewust: eerst de inlog aanmaken, pas daarna het bedrijf.
  // Andersom (zoals eerder) bleef er bij een mislukte createUser een leeg
  // bedrijf zonder admin in de lijst achter, dat alleen via de Firebase
  // Console weg te krijgen was.
  let nieuweGebruiker;
  try {
    nieuweGebruiker = await auth.createUser({
      email: nieuweAdminEmail,
      password: adminWachtwoord,
    });
  } catch (fout) {
    if (fout.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "Er bestaat al een account met dit e-mailadres.");
    }
    if (fout.code === "auth/invalid-email") {
      throw new HttpsError("invalid-argument", "Dit is geen geldig e-mailadres.");
    }
    throw new HttpsError("internal", "Aanmaken van het admin-account is mislukt: " + fout.message);
  }

  const bedrijfRef = db.collection("bedrijven").doc();
  try {
    // Bedrijf en gebruikersdocument in één batch: zo bestaat er nooit een
    // bedrijf zonder admin of een admin zonder bedrijf.
    const batch = db.batch();
    batch.set(bedrijfRef, {
      naam: bedrijfsnaam.trim(),
      aangemaaktOp: FieldValue.serverTimestamp(),
    });
    batch.set(db.collection("gebruikers").doc(nieuweAdminEmail), {
      email: nieuweAdminEmail,
      rol: "admin",
      bedrijfId: bedrijfRef.id,
      clusters: [],
    });
    await batch.commit();
  } catch (fout) {
    await auth.deleteUser(nieuweGebruiker.uid).catch(() => {});
    throw new HttpsError("internal", "Aanmaken van het bedrijf is mislukt: " + fout.message);
  }

  return { succes: true, bedrijfId: bedrijfRef.id };
});