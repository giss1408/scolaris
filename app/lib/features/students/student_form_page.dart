import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Enrol a student in 3 steps: identity, parent, class. Back keeps the data; each step validates only itself.
class StudentFormPage extends ConsumerStatefulWidget {
  const StudentFormPage({super.key});

  @override
  ConsumerState<StudentFormPage> createState() => _StudentFormPageState();
}

class _StudentFormPageState extends ConsumerState<StudentFormPage> {
  final _keys = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];
  final _last = TextEditingController();
  final _first = TextEditingController();
  final _place = TextEditingController();
  final _matricule = TextEditingController();
  final _parent = TextEditingController();
  final _phone = TextEditingController();
  int _step = 0;
  String _sex = 'F';
  DateTime? _birth;
  bool _assigned = false;
  String _relation = 'pere';
  bool _optin = false;
  Classroom? _room;
  final Set<String> _options = {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_last, _first, _place, _matricule, _parent, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _birth ?? DateTime(now.year - 10), firstDate: DateTime(now.year - 30), lastDate: now, locale: const Locale('fr'));
    if (d != null) setState(() => _birth = d);
  }

  void _next() {
    if (!(_keys[_step].currentState?.validate() ?? false)) return;
    if (_step == 2 && _room == null) {
      setState(() => _error = 'Choisissez une classe');
      return;
    }
    setState(() {
      _error = null;
      _step++;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await ref.read(repoProvider).createStudent(NewStudent(
            lastName: _last.text, firstNames: _first.text, sex: _sex, classroomId: _room!.id, birthDate: _birth, birthPlace: _place.text, matricule: _matricule.text,
            assigned: _assigned, options: _options.toList(), parentName: _parent.text, parentPhone: _phone.text, relation: _relation, optin: _optin,
          ));
      ref.invalidate(dashboardProvider);
      if (!mounted) return;
      showMessage(context, 'Élève inscrit');
      context.pop();
      context.push('/students/${s.id}?enrollment=${s.enrollmentId}&classroom=${Uri.encodeComponent(_room!.name)}');
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final last = _step == 3;
    final titles = [S.stepIdentity, S.stepParent, S.stepClass, S.summary];
    return Scaffold(
      appBar: AppBar(title: const Text(S.newStudent)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(borderRadius: BorderRadius.circular(Radii.pill), child: LinearProgressIndicator(value: (_step + 1) / 4, minHeight: 6, backgroundColor: Palette.line, color: Palette.accent)),
            const SizedBox(height: Space.sm),
            Text('${S.step(_step + 1, 4)} · ${titles[_step]}', style: t.labelMedium),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: switch (_step) { 0 => _identity(), 1 => _parentStep(), 2 => _classStep(), _ => _summary() },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
              Row(children: [
                if (_step > 0) Expanded(child: OutlinedButton(onPressed: _busy ? null : () => setState(() => _step--), child: const Text(S.back))),
                if (_step > 0) const SizedBox(width: Space.md),
                Expanded(flex: 2, child: BusyButton(label: last ? S.createStudent : S.next, onPressed: last ? _submit : _next, busy: _busy)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _identity() => Form(
        key: _keys[0],
        child: Column(children: [
          TextFormField(controller: _last, textCapitalization: TextCapitalization.characters, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: S.lastName), validator: (v) => (v ?? '').trim().isEmpty ? S.required : null),
          const SizedBox(height: Space.md),
          TextFormField(controller: _first, textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: S.firstNames), validator: (v) => (v ?? '').trim().isEmpty ? S.required : null),
          const SizedBox(height: Space.md),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'F', label: Text(S.female), icon: Icon(Icons.girl_outlined)), ButtonSegment(value: 'M', label: Text(S.male), icon: Icon(Icons.boy_outlined))],
            selected: {_sex},
            onSelectionChanged: (s) => setState(() => _sex = s.first),
          ),
          const SizedBox(height: Space.md),
          InkWell(
            onTap: _pickBirth,
            child: InputDecorator(decoration: const InputDecoration(labelText: S.birthDate, suffixIcon: Icon(Icons.calendar_today_outlined)), child: Text(_birth == null ? 'Choisir' : formatDate(_birth!))),
          ),
          const SizedBox(height: Space.md),
          TextFormField(controller: _place, textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: S.birthPlace)),
          const SizedBox(height: Space.md),
          TextFormField(controller: _matricule, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: S.matricule, helperText: S.matriculeHelp)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text(S.assignedByState), value: _assigned, onChanged: (v) => setState(() => _assigned = v)),
        ]),
      );

  Widget _parentStep() => Form(
        key: _keys[1],
        child: Column(children: [
          TextFormField(controller: _parent, textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: S.parentName), validator: (v) => (v ?? '').trim().length < 2 ? S.required : null),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
            decoration: const InputDecoration(labelText: S.phone, helperText: S.phoneHelp, prefixIcon: Icon(Icons.phone_outlined)),
            validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10 ? 'Entrez les 10 chiffres du numéro' : null,
          ),
          const SizedBox(height: Space.md),
          Align(alignment: Alignment.centerLeft, child: Wrap(spacing: Space.sm, children: [for (final r in const ['pere', 'mere', 'tuteur', 'autre']) ChoiceChip(label: Text(S.relationLabel(r)), selected: _relation == r, onSelected: (_) => setState(() => _relation = r))])),
          CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: const Text(S.optin), value: _optin, onChanged: (v) => setState(() => _optin = v ?? false)),
        ]),
      );

  Widget _classStep() {
    final rooms = ref.watch(classroomsProvider);
    return Form(
      key: _keys[2],
      child: rooms.when(
        loading: () => const SkeletonBox(height: 120, radius: Radii.md),
        error: (e, _) => SizedBox(height: 200, child: ErrorState(error: e, onRetry: () => ref.invalidate(classroomsProvider))),
        data: (list) => list.isEmpty
            ? const SizedBox(height: 200, child: EmptyState(icon: Icons.meeting_room_outlined, message: "Aucune classe n'est créée. Le directeur doit d'abord ajouter les classes (Profil > Classes)."))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(S.classroom, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: Space.sm),
                Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final r in list) ChoiceChip(label: Text(r.name), selected: _room?.id == r.id, onSelected: (_) => setState(() { _room = r; _options.clear(); }))]),
                if (_room != null) _Options(room: _room!, selected: _options, onToggle: (k) => setState(() => _options.contains(k) ? _options.remove(k) : _options.add(k))),
              ]),
      ),
    );
  }

  Widget _summary() {
    final t = Theme.of(context).textTheme;
    Widget row(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 120, child: Text(k, style: t.bodySmall)), Expanded(child: Text(v, style: t.bodyMedium))]));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(children: [
          row('Élève', '${_last.text.trim().toUpperCase()} ${_first.text.trim()}'),
          row(S.sex, _sex == 'F' ? S.female : S.male),
          if (_birth != null) row(S.birthDate, formatDate(_birth!)),
          row(S.assignedByState, _assigned ? 'Oui' : 'Non'),
          const Divider(),
          row('Parent', '${_parent.text.trim()} (${S.relationLabel(_relation)})'),
          row(S.phone, _phone.text.trim()),
          row('WhatsApp', _optin ? 'Accepté' : 'Non précisé'),
          const Divider(),
          row(S.classroom, _room?.name ?? ''),
          if (_options.isNotEmpty) row(S.options, _options.map(S.kindLabel).join(', ')),
        ]),
      ),
    );
  }
}

/// Optional services the class offers (cantine, transport...), read from the fee schedule of the class's level.
class _Options extends ConsumerWidget {
  const _Options({required this.room, required this.selected, required this.onToggle});
  final Classroom room;
  final Set<String> selected;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(meProvider).yearId ?? 0;
    return FutureBuilder<List<FeeLine>>(
      key: ValueKey(room.id),
      future: ref.read(repoProvider).fees(year, room.level),
      builder: (context, snap) {
        final opts = (snap.data ?? const <FeeLine>[]).where((f) => f.optional).toList();
        if (opts.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(S.options),
          for (final f in opts) CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: Text(S.kindLabel(f.kind)), subtitle: Text(formatFcfa(f.amount)), value: selected.contains(f.kind), onChanged: (_) => onToggle(f.kind)),
        ]);
      },
    );
  }
}
