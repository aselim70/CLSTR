import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';

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
  final DateTime? initieleDatum;
  const RouteDetailPage({
    super.key,
    required this.routeNaam,
    required this.depotNaam,
    required this.clusterId,
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
  String? _dagplanningDocId;

  @override
  void initState() {
    super.initState();
    _datum = widget.initieleDatum ?? DateTime.now();
    _weekDagen = _berekenWeekDagen(_datum);
    _laadWeekData();
  }

  @override
  void dispose() {
    _stopsGeladenController.dispose();
    _stopsGeleverdController.dispose();
    super.dispose();
  }

  String _dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  List<DateTime> _berekenWeekDagen(DateTime datum) {
    final maandag = datum.subtract(Duration(days: datum.weekday - 1));
    return List.generate(7, (i) => DateTime(maandag.year, maandag.month, maandag.day + i));
  }

  TimeOfDay? _parseTijd(String? tijdString) {
    if (tijdString == null) return null;
    final delen = tijdString.split(':');
    if (delen.length != 2) return null;
    final uur = int.tryParse(delen[0].trim());
    final minuut = int.tryParse(delen[1].trim());
    if (uur == null || minuut == null) return null;
    return TimeOfDay(hour: uur, minute: minuut);
  }

  Future<void> _laadWeekData() async {
    setState(() => _bezigMetLaden = true);
    final dagKeys = _weekDagen.map(_dateKey).toList();

    // Belangrijk: ook hier op clusterId filteren, naast routeNaam/depotNaam/
    // datum - de query moet filteren op precies het veld dat de security
    // rule checkt, anders weigert Firestore de hele lijst-opvraging vooraf
    // (ook al zou de data zelf kloppen voor dit sub-account).
    final clusterId = widget.clusterId;

    var query = FirebaseFirestore.instance
        .collection('dagplanning')
        .where('routeNaam', isEqualTo: widget.routeNaam)
        .where('depotNaam', isEqualTo: widget.depotNaam)
        .where('datum', whereIn: dagKeys);
    if (clusterId != null) {
      query = query.where('clusterId', isEqualTo: clusterId);
    }
    final snapshot = await query.get();

    if (!mounted) return;

    final nieuweWeekData = <String, Map<String, dynamic>>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      nieuweWeekData[data['datum'] as String] = {...data, 'docId': doc.id};
    }

    setState(() {
      _weekData = nieuweWeekData;
      _bezigMetLaden = false;
    });
    _vulVeldenVoorGeselecteerdeDag();
  }

  void _vulVeldenVoorGeselecteerdeDag() {
    final data = _weekData[_dateKey(_datum)];
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
  Future<void> _autoOpslaanIndienMogelijk() async {
    if (_chauffeurDocId != null && _starttijd != null && !_bezigMetOpslaan) {
      await _opslaan(toonSnackbar: false);
    }
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
      _datum = _datum.subtract(const Duration(days: 7));
      _weekDagen = _berekenWeekDagen(_datum);
    });
    _laadWeekData();
  }

  Future<void> _volgendeWeek() async {
    await _autoOpslaanIndienMogelijk();
    if (!mounted) return;
    setState(() {
      _datum = _datum.add(const Duration(days: 7));
      _weekDagen = _berekenWeekDagen(_datum);
    });
    _laadWeekData();
  }

  Future<void> _kiesAndereDatum() async {
    final gekozen = await showDatePicker(context: context, initialDate: _datum, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (gekozen != null) {
      await _autoOpslaanIndienMogelijk();
      if (!mounted) return;
      setState(() {
        _datum = gekozen;
        _weekDagen = _berekenWeekDagen(gekozen);
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

  Future<void> _opslaan({bool toonSnackbar = true}) async {
    if (_chauffeurDocId == null || _starttijd == null) return;
    setState(() => _bezigMetOpslaan = true);

    final datumKey = _dateKey(_datum);
    final stopsGeladen = int.tryParse(_stopsGeladenController.text.trim());
    final stopsGeleverd = int.tryParse(_stopsGeleverdController.text.trim());
    final clusterId = widget.clusterId;

    final data = {
      'datum': datumKey,
      'routeNaam': widget.routeNaam,
      'depotNaam': widget.depotNaam,
      'clusterId': clusterId,
      'chauffeurNaam': _chauffeurNaam,
      'chauffeurDocId': _chauffeurDocId,
      'starttijd': _starttijd!.format(context),
      'eindtijd': _eindtijd?.format(context),
      'duurMinuten': _duurInMinuten,
      'stopsGeladen': stopsGeladen,
      'stopsGeleverd': stopsGeleverd,
      'ingevoerdDoor': FirebaseAuth.instance.currentUser?.email,
    };

    String docId;
    if (_dagplanningDocId == null) {
      final nieuwDoc = await FirebaseFirestore.instance.collection('dagplanning').add(data);
      docId = nieuwDoc.id;
    } else {
      docId = _dagplanningDocId!;
      await FirebaseFirestore.instance.collection('dagplanning').doc(docId).update(data);
    }

    if (!mounted) return;
    setState(() {
      _dagplanningDocId = docId;
      _weekData[datumKey] = {...data, 'docId': docId};
      _bezigMetOpslaan = false;
    });
    if (toonSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opgeslagen!')));
    }
  }

  Future<void> _leegmaken() async {
    if (_dagplanningDocId == null) return;

    final bevestigd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Route leegmaken?'),
        content: const Text('Weet je zeker dat je de chauffeur en tijden voor deze dag wilt verwijderen? Er wordt dan geen chauffeur meer gekoppeld en er zijn geen uren geregistreerd.'),
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
    if (bevestigd != true) return;

    final datumKey = _dateKey(_datum);
    await FirebaseFirestore.instance.collection('dagplanning').doc(_dagplanningDocId).delete();

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
    final key = _dateKey(dag);
    final isGeselecteerd = _dateKey(_datum) == key;
    final dagData = _weekData[key];
    final isCompleet = dagData != null && dagData['eindtijd'] != null;
    final isDeelsIngevuld = dagData != null && dagData['eindtijd'] == null;

    final achtergrond = isGeselecteerd ? Theme.of(context).colorScheme.primary : Colors.transparent;
    final voorgrond = isGeselecteerd ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface;
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
              Text(_dagAfkortingen[dag.weekday - 1], style: TextStyle(fontSize: 12, color: voorgrond, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('${dag.day}', style: TextStyle(fontSize: 15, color: voorgrond, fontWeight: FontWeight.bold)),
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
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: kleur)),
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
        await _autoOpslaanIndienMogelijk();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: GradientAppBar(title: Text(widget.routeNaam)),
        body: _bezigMetLaden
            ? const Center(child: AppLoader())
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
                      stream: FirebaseFirestore.instance.collection('chauffeurs').snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Center(child: AppLoader());
                        final chauffeurs = snapshot.data!.docs;
                        final huidigeIds = chauffeurs.map((c) => c.id).toSet();
                        final geldigeWaarde = (_chauffeurDocId != null && huidigeIds.contains(_chauffeurDocId)) ? _chauffeurDocId : null;
                        return DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Chauffeur',
                            suffixIcon: geldigeWaarde != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    tooltip: 'Chauffeur leegmaken',
                                    onPressed: _maakChauffeurLeeg,
                                  )
                                : null,
                          ),
                          value: geldigeWaarde,
                          items: chauffeurs.map((c) {
                            final data = c.data() as Map<String, dynamic>;
                            return DropdownMenuItem(value: c.id, child: Text(data['naam'] ?? 'Onbekend'));
                          }).toList(),
                          onChanged: (waarde) {
                            final gekozenDoc = chauffeurs.firstWhere((c) => c.id == waarde);
                            final data = gekozenDoc.data() as Map<String, dynamic>;
                            setState(() {
                              _chauffeurDocId = waarde;
                              _chauffeurNaam = data['naam'];
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
                      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Duur: $_duurTekst', style: const TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _stopsGeladenController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Aantal stops geladen',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _stopsGeleverdController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Aantal stops geleverd',
                              border: OutlineInputBorder(),
                            ),
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
                          color: isCompleetVoorGeselecteerdeDag ? Theme.of(context).colorScheme.primaryContainer : Colors.orange.shade50,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isCompleetVoorGeselecteerdeDag ? Theme.of(context).colorScheme.primary.withOpacity(0.3) : Colors.orange.shade200,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: isCompleetVoorGeselecteerdeDag ? Theme.of(context).colorScheme.primary : Colors.orange,
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
                                      if (_stopsGeladenController.text.isNotEmpty || _stopsGeleverdController.text.isNotEmpty)
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