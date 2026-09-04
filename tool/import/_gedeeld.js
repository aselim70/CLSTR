// Gedeelde hulpjes voor de importscripts in deze map.
//
// Deze scripts praten met de Admin SDK en gaan dus NIET langs
// firestore.rules. Alles wat de rules normaal tegenhouden (verkeerd
// bedrijfId, een cluster dat niet bestaat) moet hier dus met de hand
// gecontroleerd worden - vandaar dat controleerBedrijf() en de
// depot-opzoeking in importeer_routes.js zo streng zijn.

const fs = require("fs");
const path = require("path");
const { initializeApp, cert, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const PROJECT_ID = "clstr-794ed";

/** Leest `--sleutel=waarde` en losse `--vlag` uit de opdrachtregel. */
function leesArgumenten(argv) {
  const opties = {};
  for (const arg of argv.slice(2)) {
    if (!arg.startsWith("--")) {
      throw new Fout(`Onbekend argument: ${arg}`);
    }
    const gelijk = arg.indexOf("=");
    if (gelijk === -1) {
      opties[arg.slice(2)] = true;
    } else {
      opties[arg.slice(2, gelijk)] = arg.slice(gelijk + 1);
    }
  }
  return opties;
}

/**
 * Eigen fouttype voor "de gebruiker heeft iets fout ingevuld". Die tonen we
 * als één nette regel; alle andere fouten laten we mét stacktrace zien,
 * want dat is dan een bug in het script zelf.
 */
class Fout extends Error {}

/**
 * Verbinding met Firestore. Volgorde van inloggen:
 *   1. --sleutel=pad/naar/serviceaccount.json
 *   2. de omgevingsvariabele GOOGLE_APPLICATION_CREDENTIALS
 *   3. `gcloud auth application-default login`
 */
function maakDb(opties) {
  const sleutelPad = opties.sleutel || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const projectId = opties.project || PROJECT_ID;

  if (sleutelPad) {
    const volledig = path.resolve(sleutelPad);
    if (!fs.existsSync(volledig)) {
      throw new Fout(`Servicesleutel niet gevonden: ${volledig}`);
    }
    initializeApp({ credential: cert(require(volledig)), projectId });
  } else {
    try {
      initializeApp({ credential: applicationDefault(), projectId });
    } catch {
      throw new Fout(
        "Geen inloggegevens gevonden. Geef --sleutel=serviceaccount.json mee, of draai eerst:\n" +
        "  gcloud auth application-default login",
      );
    }
  }
  return getFirestore();
}

/**
 * Leest een tekstbestand als lijst regels. Lege regels en regels die met #
 * beginnen vallen weg, zodat je opmerkingen in je invoerbestand kunt zetten.
 * De BOM die Excel en Kladblok vooraan een UTF-8-bestand plakken wordt
 * weggehaald - anders zou de eerste naam onzichtbaar beginnen met "﻿"
 * en dus nooit matchen met wat al in Firestore staat.
 */
function leesRegels(bestand) {
  const volledig = path.resolve(bestand);
  if (!fs.existsSync(volledig)) {
    throw new Fout(`Bestand niet gevonden: ${volledig}`);
  }
  return fs
    .readFileSync(volledig, "utf8")
    .replace(/^﻿/, "")
    .split(/\r?\n/)
    .map((regel, index) => ({ nummer: index + 1, tekst: regel.trim() }))
    .filter((regel) => regel.tekst !== "" && !regel.tekst.startsWith("#"));
}

/**
 * Splitst een regel in velden. Het scheidingsteken wordt per regel bepaald:
 * puntkomma, tab of komma - in die volgorde, want een routenaam als
 * "622 RSD Westrand, Noord" bevat vaker een komma dan een puntkomma.
 */
function splitsVelden(tekst) {
  const scheiding = tekst.includes(";") ? ";" : tekst.includes("\t") ? "\t" : ",";
  return tekst.split(scheiding).map((veld) => veld.trim());
}

/** Bestaat dit bedrijf? Zo niet: toon welke er wél zijn. */
async function controleerBedrijf(db, bedrijfId) {
  if (!bedrijfId || typeof bedrijfId !== "string") {
    throw new Fout("--bedrijf=<bedrijfId> is verplicht.");
  }
  const doc = await db.collection("bedrijven").doc(bedrijfId).get();
  if (doc.exists) return doc;

  const alle = await db.collection("bedrijven").limit(25).get();
  const namen = alle.docs.map((d) => `  ${d.id}  (${d.get("naam") ?? "zonder naam"})`).join("\n");
  throw new Fout(`Bedrijf '${bedrijfId}' bestaat niet.\n\nBestaande bedrijven:\n${namen || "  (geen)"}`);
}

/**
 * Schrijft de documenten weg in batches. Firestore staat maximaal 500
 * bewerkingen per batch toe; 400 houdt marge over voor de zekerheid.
 */
async function schrijfInBatches(db, collectie, documenten) {
  const perBatch = 400;
  for (let i = 0; i < documenten.length; i += perBatch) {
    const batch = db.batch();
    for (const document of documenten.slice(i, i + perBatch)) {
      batch.set(db.collection(collectie).doc(), document);
    }
    await batch.commit();
    process.stdout.write(`  ${Math.min(i + perBatch, documenten.length)}/${documenten.length} weggeschreven\n`);
  }
}

/** Draait het script en zet een Fout om in één nette regel op stderr. */
async function draai(hoofd) {
  try {
    await hoofd();
  } catch (fout) {
    if (fout instanceof Fout) {
      console.error(`\n${fout.message}\n`);
      process.exitCode = 1;
    } else {
      throw fout;
    }
  }
}

module.exports = { Fout, leesArgumenten, maakDb, leesRegels, splitsVelden, controleerBedrijf, schrijfInBatches, draai };
