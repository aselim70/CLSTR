#!/usr/bin/env node
//
// Voegt in één keer alle chauffeurs uit een tekstbestand toe aan een bedrijf.
//
//   node tool/import/importeer_chauffeurs.js --bedrijf=<bedrijfId> --bestand=chauffeurs.txt
//   node tool/import/importeer_chauffeurs.js --bedrijf=<bedrijfId> --bestand=chauffeurs.txt --schrijf
//
// Zonder --schrijf doet het script een DROOGLOOP: het leest alles in,
// controleert alles en laat zien wat het zou doen, maar schrijft niets weg.
// Dat is expres de standaard - dit script praat rechtstreeks met de
// productie-database van alle bedrijven, en een typefout in --bedrijf zet
// anders zonder waarschuwing honderd chauffeurs bij de verkeerde klant.
//
// Bestandsformaat: één naam per regel. Lege regels en regels die met #
// beginnen worden overgeslagen.
//
//   # Chauffeurs cluster Noord
//   Jan Jansen
//   Piet de Vries
//
// Chauffeurs die al bestaan bij dit bedrijf (zelfde naam, hoofdletters
// maken niet uit) worden overgeslagen in plaats van dubbel aangemaakt, zodat
// je het script gerust nog een keer kunt draaien met een aangevulde lijst.

const { Fout, leesArgumenten, maakDb, leesRegels, splitsVelden, controleerBedrijf, schrijfInBatches, draai } = require("./_gedeeld");

const GEBRUIK = `Gebruik:
  node tool/import/importeer_chauffeurs.js --bedrijf=<bedrijfId> --bestand=<pad> [--schrijf] [--sleutel=<serviceaccount.json>]

  --bedrijf   Het bedrijfId waar de chauffeurs bij horen (verplicht).
  --bestand   Tekstbestand met één chauffeursnaam per regel (verplicht).
  --schrijf   Daadwerkelijk wegschrijven. Zonder deze vlag is het een droogloop.
  --sleutel   Servicesleutel (.json). Standaard: GOOGLE_APPLICATION_CREDENTIALS
              of application-default login (zie README.md in deze map).`;

async function hoofd() {
  const opties = leesArgumenten(process.argv);
  if (opties.help || opties.h) {
    console.log(GEBRUIK);
    return;
  }
  if (!opties.bedrijf || !opties.bestand) {
    throw new Fout(GEBRUIK);
  }

  // Namen uit het bestand halen en meteen ontdubbelen binnen het bestand
  // zelf: twee keer dezelfde naam in de lijst is bijna altijd een fout in
  // het knip- en plakwerk, niet twee chauffeurs die toevallig zo heten.
  const gezien = new Map();
  const namen = [];
  for (const regel of leesRegels(opties.bestand)) {
    const velden = splitsVelden(regel.tekst).filter((veld) => veld !== "");
    if (velden.length > 1) {
      throw new Fout(`Regel ${regel.nummer}: verwacht alleen een naam, maar er staan ${velden.length} kolommen:\n  ${regel.tekst}`);
    }
    const naam = velden[0];
    const sleutel = naam.toLowerCase();
    if (gezien.has(sleutel)) {
      console.log(`  Regel ${regel.nummer}: '${naam}' staat al op regel ${gezien.get(sleutel)} - overgeslagen.`);
      continue;
    }
    gezien.set(sleutel, regel.nummer);
    namen.push(naam);
  }
  if (namen.length === 0) {
    throw new Fout("Het bestand bevat geen namen.");
  }

  const db = maakDb(opties);
  const bedrijf = await controleerBedrijf(db, opties.bedrijf);

  const bestaand = await db.collection("chauffeurs").where("bedrijfId", "==", opties.bedrijf).get();
  const bestaandeNamen = new Set(bestaand.docs.map((doc) => String(doc.get("naam") ?? "").trim().toLowerCase()));

  const nieuw = namen.filter((naam) => !bestaandeNamen.has(naam.toLowerCase()));
  const overgeslagen = namen.length - nieuw.length;

  console.log(`\nBedrijf:       ${opties.bedrijf} (${bedrijf.get("naam") ?? "zonder naam"})`);
  console.log(`In bestand:    ${namen.length}`);
  console.log(`Bestaat al:    ${overgeslagen}`);
  console.log(`Toe te voegen: ${nieuw.length}`);
  if (nieuw.length > 0) {
    console.log(`\n${nieuw.map((naam) => `  + ${naam}`).join("\n")}`);
  }

  if (nieuw.length === 0) {
    console.log("\nNiets te doen.\n");
    return;
  }
  if (!opties.schrijf) {
    console.log("\nDROOGLOOP - er is niets weggeschreven. Draai opnieuw met --schrijf om het echt te doen.\n");
    return;
  }

  console.log("\nWegschrijven...");
  await schrijfInBatches(db, "chauffeurs", nieuw.map((naam) => ({ naam, bedrijfId: opties.bedrijf })));
  console.log(`\nKlaar: ${nieuw.length} chauffeur(s) toegevoegd.\n`);
}

draai(hoofd);
