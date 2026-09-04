#!/usr/bin/env node
//
// Voegt in één keer alle routes uit een bestand toe aan een bedrijf.
//
//   node tool/import/importeer_routes.js --bedrijf=<bedrijfId> --bestand=routes.txt --depot="Depot Noord"
//   node tool/import/importeer_routes.js --bedrijf=<bedrijfId> --bestand=routes.txt --depot="Depot Noord" --schrijf
//
// Zonder --schrijf doet het script een DROOGLOOP: het leest alles in,
// controleert alles en laat zien wat het zou doen, maar schrijft niets weg.
// Zie importeer_chauffeurs.js voor waarom dat de standaard is.
//
// Bestandsformaat: één routenaam per regel, precies zoals hij in de app moet
// komen te staan. Het ritnummer typ je niet apart - dat staat immers al
// vooraan in de naam:
//
//   622 RSD Westrand
//   623 RSD Oost
//
// Staan de routes in verschillende depots, dan zet je het depot erachter in
// een tweede kolom (puntkomma, tab of komma):
//
//   622 RSD Westrand ; Depot Noord
//   711 RSD Centrum  ; Depot Zuid
//
// Het veld 'ritnummer' wordt afgeleid uit de cijfers vooraan de naam
// ("623 RSD Oost" -> "623"). De app gebruikt dat alleen voor het label
// "Rit 623" onder de routenaam; begint een naam niet met een cijfer, dan
// blijft het veld leeg en valt dat label gewoon weg.
//
// Het clusterId wordt NIET in het bestand gezet maar opgezocht bij het
// depot: een route in een ander cluster dan zijn depot is in de app
// onvindbaar (elk scherm filtert op bedrijfId én clusterId), en dat is een
// fout die je pas weken later ontdekt. Staat dezelfde depotnaam in meerdere
// clusters, dan stopt het script en moet je --cluster=<clusterId> meegeven.

const { Fout, leesArgumenten, maakDb, leesRegels, splitsVelden, controleerBedrijf, schrijfInBatches, draai } = require("./_gedeeld");

const GEBRUIK = `Gebruik:
  node tool/import/importeer_routes.js --bedrijf=<bedrijfId> --bestand=<pad> [--depot=<naam>] [--cluster=<clusterId>] [--schrijf] [--sleutel=<serviceaccount.json>]

  --bedrijf   Het bedrijfId waar de routes bij horen (verplicht).
  --bestand   Bestand met één routenaam per regel, bijv. '623 RSD Oost'
              (verplicht). Optioneel een tweede kolom met het depot.
  --depot     Depotnaam voor alle regels die zelf geen depot noemen.
  --cluster   Alleen nodig als dezelfde depotnaam in meerdere clusters voorkomt.
  --schrijf   Daadwerkelijk wegschrijven. Zonder deze vlag is het een droogloop.
  --sleutel   Servicesleutel (.json). Standaard: GOOGLE_APPLICATION_CREDENTIALS
              of application-default login (zie README.md in deze map).`;

/**
 * Haalt het ritnummer uit de routenaam: de cijfers waarmee de naam begint.
 * Levert een lege tekst op als de naam niet met een cijfer begint - dat is
 * geen fout, de app toont het label "Rit ..." dan gewoon niet.
 */
function afleidRitnummer(naam) {
  const gevonden = naam.match(/^\d+/);
  return gevonden ? gevonden[0] : "";
}

/** Leest het bestand uit tot een lijst {naam, depotNaam}. */
function leesRoutes(bestand, standaardDepot) {
  const routes = [];
  for (const regel of leesRegels(bestand)) {
    const velden = splitsVelden(regel.tekst).filter((veld) => veld !== "");
    // Een kopregel uit Excel stilletjes overslaan; die zou anders als route
    // met de naam 'naam' in de database belanden en daarna met de hand
    // verwijderd moeten worden.
    if (["naam", "route", "routenaam", "ritnummer"].includes(velden[0].toLowerCase())) continue;

    const [naam, depotUitBestand] = velden;
    const depotNaam = (depotUitBestand || standaardDepot || "").trim();

    if (velden.length > 2) {
      throw new Fout(`Regel ${regel.nummer}: ${velden.length} kolommen gevonden, verwacht 'naam' of 'naam ; depot'.\n  ${regel.tekst}`);
    }
    if (!depotNaam) {
      throw new Fout(`Regel ${regel.nummer}: geen depot. Zet het in een tweede kolom of geef --depot=<naam> mee.\n  ${regel.tekst}`);
    }
    routes.push({ nummer: regel.nummer, naam, depotNaam });
  }
  return routes;
}

/**
 * Zoekt per depotnaam het bijbehorende clusterId op. Alle depots van het
 * bedrijf worden in één keer opgehaald - dat scheelt niet alleen queries,
 * het maakt ook de foutmelding bruikbaar: bij een typefout in de depotnaam
 * kunnen we meteen laten zien welke depots er wél zijn.
 */
async function maakDepotIndex(db, bedrijfId, gekozenCluster) {
  const depots = await db.collection("depots").where("bedrijfId", "==", bedrijfId).get();
  const perNaam = new Map();
  for (const doc of depots.docs) {
    const naam = String(doc.get("naam") ?? "").trim();
    if (!naam) continue;
    const sleutel = naam.toLowerCase();
    if (!perNaam.has(sleutel)) perNaam.set(sleutel, { naam, clusters: [] });
    perNaam.get(sleutel).clusters.push(String(doc.get("clusterId") ?? ""));
  }

  return function zoekDepot(depotNaam, regelnummer) {
    const gevonden = perNaam.get(depotNaam.toLowerCase());
    if (!gevonden) {
      const beschikbaar = [...perNaam.values()].map((d) => `  ${d.naam}`).join("\n");
      throw new Fout(`Regel ${regelnummer}: depot '${depotNaam}' bestaat niet bij dit bedrijf.\n\nBestaande depots:\n${beschikbaar || "  (geen)"}`);
    }
    const clusters = [...new Set(gevonden.clusters)];
    if (gekozenCluster) {
      if (!clusters.includes(gekozenCluster)) {
        throw new Fout(`Regel ${regelnummer}: depot '${gevonden.naam}' zit niet in cluster '${gekozenCluster}' maar in: ${clusters.join(", ")}`);
      }
      return { depotNaam: gevonden.naam, clusterId: gekozenCluster };
    }
    if (clusters.length > 1) {
      throw new Fout(`Regel ${regelnummer}: depot '${gevonden.naam}' komt voor in meerdere clusters (${clusters.join(", ")}).\nGeef --cluster=<clusterId> mee om te kiezen.`);
    }
    // Let op: de depotnaam uit de DATABASE teruggeven, niet die uit het
    // bestand. Anders krijgt de route depotNaam 'depot noord' terwijl het
    // depot 'Depot Noord' heet, en dan vindt route_list_page.dart hem nooit -
    // die query vergelijkt hoofdlettergevoelig op depotNaam.
    return { depotNaam: gevonden.naam, clusterId: clusters[0] };
  };
}

async function hoofd() {
  const opties = leesArgumenten(process.argv);
  if (opties.help || opties.h) {
    console.log(GEBRUIK);
    return;
  }
  if (!opties.bedrijf || !opties.bestand) {
    throw new Fout(GEBRUIK);
  }

  const gelezen = leesRoutes(opties.bestand, typeof opties.depot === "string" ? opties.depot : null);
  if (gelezen.length === 0) {
    throw new Fout("Het bestand bevat geen routes.");
  }

  const db = maakDb(opties);
  const bedrijf = await controleerBedrijf(db, opties.bedrijf);
  const zoekDepot = await maakDepotIndex(db, opties.bedrijf, typeof opties.cluster === "string" ? opties.cluster : null);

  // Wat er al staat: één route per depot + naam. Dezelfde routenaam in een
  // ander depot mag dus wel, en dat komt in de praktijk ook voor.
  const bestaand = await db.collection("routes").where("bedrijfId", "==", opties.bedrijf).get();
  const bestaandeSleutels = new Set(
    bestaand.docs.map((doc) => sleutelVan(String(doc.get("depotNaam") ?? ""), String(doc.get("naam") ?? ""))),
  );
  // Ritnummers die al in gebruik zijn, per depot. Hier stopt het script niet
  // op - twee routes met hetzelfde nummer mag - maar het is wel bijna altijd
  // een half aangepaste naam ("623 RSD Oost" naast "623 RSD Oost nieuw"),
  // dus je krijgt er een waarschuwing over te zien.
  const bestaandeRitnummers = new Map();
  for (const doc of bestaand.docs) {
    const ritnummer = String(doc.get("ritnummer") ?? "").trim();
    if (!ritnummer) continue;
    bestaandeRitnummers.set(sleutelVan(String(doc.get("depotNaam") ?? ""), ritnummer), String(doc.get("naam") ?? ""));
  }

  const nieuw = [];
  const inBestand = new Map();
  const waarschuwingen = [];
  let overgeslagen = 0;
  for (const route of gelezen) {
    const { depotNaam, clusterId } = zoekDepot(route.depotNaam, route.nummer);
    const sleutel = sleutelVan(depotNaam, route.naam);

    if (inBestand.has(sleutel)) {
      console.log(`  Regel ${route.nummer}: '${route.naam}' bij '${depotNaam}' staat al op regel ${inBestand.get(sleutel)} - overgeslagen.`);
      continue;
    }
    inBestand.set(sleutel, route.nummer);

    if (bestaandeSleutels.has(sleutel)) {
      overgeslagen++;
      continue;
    }

    const ritnummer = afleidRitnummer(route.naam);
    const alGebruikt = ritnummer ? bestaandeRitnummers.get(sleutelVan(depotNaam, ritnummer)) : null;
    if (alGebruikt) {
      waarschuwingen.push(`  Regel ${route.nummer}: rit ${ritnummer} bestaat bij '${depotNaam}' al als '${alGebruikt}'.`);
    }

    nieuw.push({ ritnummer, naam: route.naam, depotNaam, clusterId, bedrijfId: opties.bedrijf });
  }

  console.log(`\nBedrijf:       ${opties.bedrijf} (${bedrijf.get("naam") ?? "zonder naam"})`);
  console.log(`In bestand:    ${gelezen.length}`);
  console.log(`Bestaat al:    ${overgeslagen}`);
  console.log(`Toe te voegen: ${nieuw.length}`);
  if (nieuw.length > 0) {
    console.log(`\n${nieuw.map((r) => `  + ${r.naam}   [${r.depotNaam} / ${r.clusterId}]${r.ritnummer ? "" : "   (geen ritnummer in de naam)"}`).join("\n")}`);
  }
  if (waarschuwingen.length > 0) {
    console.log(`\nLet op:\n${waarschuwingen.join("\n")}`);
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
  await schrijfInBatches(db, "routes", nieuw);
  console.log(`\nKlaar: ${nieuw.length} route(s) toegevoegd.\n`);
}

function sleutelVan(depotNaam, waarde) {
  // Spaties samentrekken: '623  RSD Oost' en '623 RSD Oost' zijn dezelfde
  // route, en zo'n dubbele spatie zie je in een lijst van honderd namen niet.
  return `${depotNaam.trim().toLowerCase()}|${waarde.trim().toLowerCase().replace(/\s+/g, " ")}`;
}

draai(hoofd);
