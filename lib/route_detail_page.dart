import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'app_helpers.dart';

const List<String> _dagAfkortingen = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];

class RouteDetailPage extends StatefulWidget {
  final String routeNaam;
  final String depotNaam;
  // clusterId van de route/dagplanning waar dit scherm bij hoort. Wordt door
  // de aanroepende pagina meegegeven (die heeft dit al in de hand vanuit de
  // route- of dagplanning-data), zodat hier geen aparte Firestore-opvraging
  // nodig is om het cluster op te zoeken - zo'n opvraging (gefilterd op
  // depotnaam i.p.v. clusterId) zou door de security rules vooraf geweigerd
  // worden voor sub-accounts.
  final String? clusterId;
  final String bedrijfId;
  final DateTime? initieleDatum;
  const RouteDetailPage({
    super.key,
    required this.routeNaam,
    required this.depotNaam,
    required this.clusterId,
    required this.bedrijfId,
    this.initieleDatum,
  });
  @override
  State<RouteDetailPage> createState() => _RouteDetailPageState();
}

class _RouteDetailPageState extends State<RouteDetailPage> {
  DateTime _datum = DateTime.now();
  List<DateTime> _weekDagen = [];
  Map<String, Map<String, dynamic>> _weekData = {};

  String? _chauffeurDocId;
  String? _chauffeurNaam;
  TimeOfDay? _starttijd;
  TimeOfDay? _eindtijd;
  final TextEditingController _stopsGeladenController = TextEditingController();
  final TextEditingController _stopsGeleverdController = TextEditingController();
  bool _bezigMetOpslaan = false;
  bool _bezigMetLaden = true;
  String? _laadFout;
  String? _dagplanningDocId;

  @override
  void initState() {
    super.initState();
    _datum = alleenDatum(widget.initieleDatum ?? DateTime.now());
    _weekDagen = weekDagen(_datum);
    _laadWeekData();
  }

  @override
  void dispose() {
    _stopsGeladenController.dispose();
    _stopsGeleverdController.dispose();
    super.dispose();
  }

  /// Zelfde nette, afgeronde veldstijl als bij Overzicht (Depot/Route) -
  /// witte achtergrond met dun grijs randje, navy als je erin tikt.
  InputDecoration _nettDecoration(String label, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBlauwBoven, width: 1.5),
      ),
    );
  }

  /// Tijden worden als 'HH:mm' in Firestore opgeslagen. Bewust niet via
  /// TimeOfDay.format(context): dat volgt de landinstelling van het toestel en
  /// kan er dan '9:30 AM' van maken, wat [_parseTijd] hieronder niet meer
  /// terug kan lezen. Opgeslagen data moet niet van de telefoon-instellingen
  /// van degene die het invulde afhangen.
  static String _tijdNaarTekst(TimeOfDay tijd) =>
      '${tijd.hour.toString().padLeft(2, '0')}:${tijd.minute.toString().padLeft(2, '0')}';

  TimeOfDay? _parseTijd(String? tijdString) {
    if (tijdString == null) return null;
    final delen = tijdString.split(':');
    if (delen.length != 2) return null;
    final uur = int.tryParse(delen[0].trim());
    final minuut = int.tryParse(delen[1].trim());
    if (uur == null || minuut == null) return null;
    if (uur < 0 || uur > 23 || minuut < 0 || minuut > 59) return null;
    return TimeOfDay(hour: uur, minute: minuut);
  }

  Future<void> _laadWeekData() async {
    setState(() {
      _bezigMetLaden = true;
      _laadFout = null;
    });
    final dagKeys = _weekDagen.map(dateKey).toList();

    // Belangrijk: ook hier op clusterId filteren, naast routeNaam/depotNaam/
    // datum - de query moet filteren op precies het veld dat de security
    // rule checkt, anders weigert Firestore de hele lijst-opvraging vooraf
    // (ook al zou de data zelf kloppen voor dit sub-account).
    final clusterId = widget.clusterId;

    var query = FirebaseFirestore.instance
        .collection('dagplanning')
        .where('bedrijfId', isEqualTo: widget.bedrijfId)
        .where('routeNaam', isEqualTo: widget.routeNaam)
        .where('depotNaam', isEqualTo: widget.depotNaam)
        .where('datum', whereIn: dagKeys);
    if (clusterId != null) {
      query = query.where('clusterId', isEqualTo: clusterId);
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await query.get();
    } catch (fout) {
      // Zonder deze afhandeling bleef _bezigMetLaden voor altijd op true
      // staan en zag de gebruiker een laad-animatie die nooit ophield.
      if (!mounted) return;
      setState(() {
        _bezigMetLaden = false;
        _laadFout = '$fout';
      });
      return;
    }

    if (!mounted) return;

    final nieuweWeekData = <String, Map<String, dynamic>>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      // Een document zonder (of met een raar) datum-veld sloeg de hele
      // opvraging stuk op een mislukte cast; nu wordt het simpelweg
      // overgeslagen.
      final datum = data['datum'];
      if (datum is! String) continue;
      nieuweWeekData[datum] = {...data, 'docId': doc.id};
    }

    setState(() {
      _weekData = nieuweWeekData;
      _bezigMetLaden = false;
    });
    _vulVeldenVoorGeselecteerdeDag();
  }

  void _vulVeldenVoorGeselecteerdeDag() {
    final data = _weekData[dateKey(_datum)];
    if (data != null) {
      setState(() {
        _dagplanningDocId = data['docId'] as String?;
        _chauffeurDocId = data['chauffeurDocId'] as String?;
        _chauffeurNaam = data['chauffeurNaam'] as String?;
        _starttijd = _parseTijd(data['starttijd'] as String?);
        _eindtijd = _parseTijd(data['eindtijd'] as String?);
      });
      _stopsGeladenController.text = (data['stopsGeladen'] as int?)?.toString() ?? '';
      _stopsGeleverdController.text = (data['stopsGeleverd'] as int?)?.toString() ?? '';
    } else {
      setState(() {
        _dagplanningDocId = null;
        _chauffeurDocId = null;
        _chauffeurNaam = null;
        _starttijd = null;
        _eindtijd = null;
      });
      _stopsGeladenController.clear();
      _stopsGeleverdController.clear();
    }
  }

  /// Slaat de huidige dag automatisch op (zonder snackbar) als er minimaal
  /// een chauffeur + starttijd is ingevuld. Wordt aangeroepen vlak voordat we
  /// van dag/week wisselen of het scherm verlaten, zodat niets verloren gaat
  /// zonder dat er expliciet op "Opslaan" geklikt hoeft te worden.
  Future<bool> _autoOpslaanIndienMogelijk() async {
    if (_chauffeurDocId != null && _starttijd != null && !_bezigMetOpslaan) {
      return _opslaan(toonSnackbar: false);
    }
    return true;
  }

  Future<void> _kiesWeekDag(DateTime dag) async {
    await _autoOpslaanIndienMogelijk();
    if (!mounted) return;
    setState(() => _datum = dag);
    _vulVeldenVoorGeselecteerdeDag();
  }

  Future<void> _vorigeWeek() async {
    await _autoOpslaanIndienMogelijk();
    if (!mounted) return;
    setState(() {
      _datum = plusDagen(_datum, -7);
      _weekDagen = weekDagen(_datum);
    });
    _laadWeekData();
  }

  Future<void> _volgendeWeek() async {
    await _autoOpslaanIndienMogelijk();
    if (!mounted) return;
    setState(() {
      _datum = plusDagen(_datum, 7);
      _weekDagen = weekDagen(_datum);
    });
    _laadWeekData();
  }

  Future<void> _kiesAndereDatum() async {
    final gekozen = await showDatePicker(
      context: context,
      initialDate: _datum,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (gekozen != null) {
      await _autoOpslaanIndienMogelijk();
      if (!mounted) return;
      setState(() {
        _datum = alleenDatum(gekozen);
        _weekDagen = weekDagen(gekozen);
      });
      _laadWeekData();
    }
  }

  int? get _duurInMinuten {
    if (_starttijd == null || _eindtijd == null) return null;
    final start = _starttijd!.hour * 60 + _starttijd!.minute;
    final eind = _eindtijd!.hour * 60 + _eindtijd!.minute;
    final duur = eind - start;
    return duur > 0 ? duur : null;
  }

  String? get _duurTekst {
    if (_starttijd == null || _eindtijd == null) return null;
    final duur = _duurInMinuten;
    if (duur == null) return 'Eindtijd moet na de starttijd liggen';
    return '${duur ~/ 60} uur ${duur % 60} min';
  }

  Future<void> _kiesStarttijd() async {
    final gekozen = await showTimePicker(
      context: context,
      initialTime: _starttijd ?? TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (gekozen != null) setState(() => _starttijd = gekozen);
  }

  Future<void> _kiesEindtijd() async {
    final gekozen = await showTimePicker(
      context: context,
      initialTime: _eindtijd ?? TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (gekozen != null) setState(() => _eindtijd = gekozen);
  }

  void _maakChauffeurLeeg() {
    setState(() {
      _chauffeurDocId = null;
      _chauffeurNaam = null;
    });
  }

  void _maakStarttijdLeeg() {
    setState(() => _starttijd = null);
  }

  void _maakEindtijdLeeg() {
    setState(() => _eindtijd = null);
  }

  /// Slaat de ingevulde dag op. Geeft terug of dat gelukt is, zodat de
  /// aanroeper (bijv. het weggaan van dit scherm) weet of er data verloren
  /// dreigt te gaan.
  Future<bool> _opslaan({bool toonSnackbar = true}) async {
    if (_chauffeurDocId == null || _starttijd == null) return false;
    setState(() => _bezigMetOpslaan = true);

    final datumKey = dateKey(_datum);
    final stopsGeladen = int.tryParse(_stopsGeladenController.text.trim());
    final stopsGeleverd = int.tryParse(_stopsGeleverdController.text.trim());
    final clusterId = widget.clusterId;

    final data = {
      'datum': datumKey,
      'routeNaam': widget.routeNaam,
      'depotNaam': widget.depotNaam,
      'clusterId': clusterId,
      'bedrijfId': widget.bedrijfId,
      'chauffeurNaam': _chauffeurNaam,
      'chauffeurDocId': _chauffeurDocId,
      'starttijd': _tijdNaarTekst(_starttijd!),
      'eindtijd': _eindtijd == null ? null : _tijdNaarTekst(_eindtijd!),
      'duurMinuten': _duurInMinuten,
      'stopsGeladen': stopsGeladen,
      'stopsGeleverd': stopsGeleverd,
      'ingevoerdDoor': FirebaseAuth.instance.currentUser?.email,
    };

    // Zonder deze try/catch bleef _bezigMetOpslaan bij een mislukte
    // schrijfactie op true staan: de Opslaan-knop werd dan permanent grijs en
    // je kon je invoer helemaal niet meer bewaren tot je het scherm sloot -
    // waarbij je invoer dus alsnog weg was.
    final String docId;
    try {
      if (_dagplanningDocId == null) {
        final nieuwDoc = await FirebaseFirestore.instance.collection('dagplanning').add(data);
        docId = nieuwDoc.id;
      } else {
        docId = _dagplanningDocId!;
        await FirebaseFirestore.instance.collection('dagplanning').doc(docId).update(data);
      }
    } catch (fout) {
      if (!mounted) return false;
      setState(() => _bezigMetOpslaan = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opslaan mislukt: $fout'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
        ),
      );
      return false;
    }

    if (!mounted) return true;
    setState(() {
      _dagplanningDocId = docId;
      _weekData[datumKey] = {...data, 'docId': docId};
      _bezigMetOpslaan = false;
    });
    if (toonSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opgeslagen!')));
    }
    return true;
  }

  Future<void> _leegmaken() async {
    if (_dagplanningDocId == null) return;

    final bevestigd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Route leegmaken?'),
        content: const Text(
          'Weet je zeker dat je de chauffeur en tijden voor deze dag wilt verwijderen? Er wordt dan geen chauffeur meer gekoppeld en er zijn geen uren geregistreerd.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuleren')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leegmaken'),
          ),
        ],
      ),
    );
    if (bevestigd != true || !mounted) return;

    final datumKey = dateKey(_datum);
    try {
      await FirebaseFirestore.instance.collection('dagplanning').doc(_dagplanningDocId).delete();
    } catch (fout) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Leegmaken mislukt: $fout'), backgroundColor: Colors.red.shade700));
      return;
    }

    if (!mounted) return;
    setState(() {
      _weekData.remove(datumKey);
      _dagplanningDocId = null;
      _chauffeurDocId = null;
      _chauffeurNaam = null;
      _starttijd = null;
      _eindtijd = null;
    });
    _stopsGeladenController.clear();
    _stopsGeleverdController.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route leeggemaakt voor deze dag.')));
  }

  Widget _weekDagKnop(DateTime dag) {
    final key = dateKey(dag);
    final isGeselecteerd = dateKey(_datum) == key;
    final dagData = _weekData[key];
    final isCompleet = dagData != null && dagData['eindtijd'] != null;
    final isDeelsIngevuld = dagData != null && dagData['eindtijd'] == null;

    final achtergrond = isGeselecteerd ? Theme.of(context).colorScheme.primary : Colors.transparent;
    final voorgrond = isGeselecteerd
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    final randkleur = isGeselecteerd ? Theme.of(context).colorScheme.primary : Colors.grey.shade300;

    return Expanded(
      child: GestureDetector(
        onTap: () => _kiesWeekDag(dag),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: achtergrond,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: randkleur, width: 1.4),
          ),
          child: Column(
            children: [
              Text(
                _dagAfkortingen[dag.weekday - 1],
                style: TextStyle(fontSize: 12, color: voorgrond, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${dag.day}',
                style: TextStyle(fontSize: 15, color: voorgrond, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleet ? Colors.green : (isDeelsIngevuld ? Colors.orange : Colors.transparent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendeItem(Color kleur, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: kleur),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompleetVoorGeselecteerdeDag = _dagplanningDocId != null && _eindtijd != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final opgeslagen = await _autoOpslaanIndienMogelijk();
        if (!context.mounted) return;
        // Ging het automatisch opslaan mis, dan sloot dit scherm vroeger
        // gewoon en was de invoer weg zonder dat iemand dat merkte. Nu eerst
        // vragen of er echt weggegaan moet worden.
        if (!opgeslagen) {
          final tochWeg = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Niet opgeslagen'),
              content: const Text('Deze dag kon niet worden opgeslagen. Als je nu teruggaat, ben je je invoer kwijt.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Blijven')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Toch teruggaan'),
                ),
              ],
            ),
          );
          if (tochWeg != true || !context.mounted) return;
        }
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: GradientAppBar(title: Text(widget.routeNaam)),
        body: _bezigMetLaden
            ? const Center(child: AppLoader())
            : _laadFout != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Kan deze week niet laden:\n$_laadFout', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      OutlinedButton(onPressed: _laadWeekData, child: const Text('Opnieuw proberen')),
                    ],
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: ListView(
                  children: [
                    Row(
                      children: [
                        IconButton(icon: const Icon(Icons.chevron_left), onPressed: _vorigeWeek),
                        Expanded(
                          child: Center(
                            child: Text(
                              'Week van ${DateFormat('dd-MM').format(_weekDagen.first)} t/m ${DateFormat('dd-MM').format(_weekDagen.last)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.chevron_right), onPressed: _volgendeWeek),
                        IconButton(icon: const Icon(Icons.calendar_month), onPressed: _kiesAndereDatum),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(children: _weekDagen.map(_weekDagKnop).toList()),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        _legendeItem(Colors.green, 'Compleet'),
                        _legendeItem(Colors.orange, 'Nog geen eindtijd'),
                        _legendeItem(Colors.grey.shade300, 'Niets ingevuld'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('chauffeurs')
                          .where('bedrijfId', isEqualTo: widget.bedrijfId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text(
                            'Kan chauffeurs niet laden: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red),
                          );
                        }
                        if (!snapshot.hasData) return const Center(child: AppLoader());
                        final chauffeurs = snapshot.data!.docs;
                        final huidigeIds = chauffeurs.map((c) => c.id).toSet();
                        final geldigeWaarde = (_chauffeurDocId != null && huidigeIds.contains(_chauffeurDocId))
                            ? _chauffeurDocId
                            : null;
                        return DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: _nettDecoration(
                            'Chauffeur',
                            suffixIcon: geldigeWaarde != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    tooltip: 'Chauffeur leegmaken',
                                    onPressed: _maakChauffeurLeeg,
                                  )
                                : null,
                          ),
                          initialValue: geldigeWaarde,
                          items: chauffeurs.map((c) {
                            final data = c.data() as Map<String, dynamic>;
                            return DropdownMenuItem(value: c.id, child: Text(data['naam'] ?? 'Onbekend'));
                          }).toList(),
                          onChanged: (waarde) {
                            // firstWhere zonder orElse gooide een StateError
                            // zodra de gekozen chauffeur net was verwijderd
                            // door iemand anders (de lijst is een live stream).
                            final gekozenDoc = chauffeurs.where((c) => c.id == waarde).firstOrNull;
                            if (gekozenDoc == null) return;
                            final data = gekozenDoc.data() as Map<String, dynamic>;
                            setState(() {
                              _chauffeurDocId = waarde;
                              _chauffeurNaam = data['naam']?.toString();
                            });
                          },
                        );
                      },
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Starttijd'),
                      subtitle: Text(_starttijd?.format(context) ?? 'Nog niet ingevuld'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_starttijd != null)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Starttijd leegmaken',
                              onPressed: _maakStarttijdLeeg,
                            ),
                          const Icon(Icons.access_time),
                        ],
                      ),
                      onTap: _kiesStarttijd,
                    ),
                    ListTile(
                      title: const Text('Eindtijd'),
                      subtitle: Text(_eindtijd?.format(context) ?? 'Nog niet ingevuld'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_eindtijd != null)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Eindtijd leegmaken',
                              onPressed: _maakEindtijdLeeg,
                            ),
                          const Icon(Icons.access_time),
                        ],
                      ),
                      onTap: _kiesEindtijd,
                    ),
                    if (_duurTekst != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Duur: $_duurTekst', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _stopsGeladenController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: _nettDecoration('Aantal stops geladen'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _stopsGeleverdController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: _nettDecoration('Aantal stops geleverd'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    GradientButton(
                      onPressed: (_chauffeurDocId != null && _starttijd != null && !_bezigMetOpslaan) ? _opslaan : null,
                      child: _bezigMetOpslaan
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Opslaan'),
                    ),
                    if (_dagplanningDocId != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _leegmaken,
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text('Route leegmaken voor deze dag', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                      ),
                    ],
                    if (_dagplanningDocId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Card(
                          elevation: 0,
                          color: isCompleetVoorGeselecteerdeDag
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Colors.orange.shade50,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isCompleetVoorGeselecteerdeDag
                                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                                  : Colors.orange.shade200,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: isCompleetVoorGeselecteerdeDag
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.orange,
                                  child: Icon(
                                    isCompleetVoorGeselecteerdeDag ? Icons.check : Icons.hourglass_bottom,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isCompleetVoorGeselecteerdeDag
                                            ? 'Deze chauffeur is opgeslagen voor deze dag.'
                                            : 'Chauffeur en starttijd opgeslagen — eindtijd ontbreekt nog.',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$_chauffeurNaam · start ${_starttijd?.format(context) ?? '-'}'
                                        '${_eindtijd != null ? ' · eind ${_eindtijd!.format(context)}' : ''}'
                                        ' · ${DateFormat('dd-MM-yyyy').format(_datum)}',
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                      ),
                                      if (_stopsGeladenController.text.isNotEmpty ||
                                          _stopsGeleverdController.text.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            '${_stopsGeladenController.text.isNotEmpty ? '${_stopsGeladenController.text} geladen' : ''}'
                                            '${_stopsGeladenController.text.isNotEmpty && _stopsGeleverdController.text.isNotEmpty ? ' · ' : ''}'
                                            '${_stopsGeleverdController.text.isNotEmpty ? '${_stopsGeleverdController.text} geleverd' : ''}',
                                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
