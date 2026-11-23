import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Search + list of the year's students, 50 at a time.
class StudentsPage extends ConsumerStatefulWidget {
  const StudentsPage({super.key});

  @override
  ConsumerState<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends ConsumerState<StudentsPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<StudentRow> _rows = [];
  Object? _error;
  bool _loading = true;
  bool _more = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final year = ref.read(meProvider).yearId;
    if (year == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _more = true;
      }
    });
    try {
      final page = await ref.read(repoProvider).students(year, query: _search.text, offset: reset ? 0 : _rows.length);
      if (!mounted) return;
      setState(() {
        _rows = reset ? page : [..._rows, ...page];
        _hasMore = page.length >= 50;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mapError(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final searching = _search.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text(S.tabStudents)),
      floatingActionButton: me.canEnrol
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/students/new');
                if (mounted) _load(reset: true);
              },
              icon: const Icon(Icons.person_add_alt_outlined),
              label: const Text(S.newStudent),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: S.searchStudent,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching ? IconButton(tooltip: 'Effacer', icon: const Icon(Icons.close), onPressed: () { _search.clear(); _load(reset: true); }) : null,
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const SkeletonList()
              : _error != null
                  ? ErrorState(error: _error!, onRetry: () => _load(reset: true))
                  : _rows.isEmpty
                      ? EmptyState(icon: Icons.groups_outlined, message: searching ? S.noResult : S.noStudents, actionLabel: !searching && me.canEnrol ? S.newStudent : null, onAction: !searching && me.canEnrol ? () => context.push('/students/new') : null)
                      : RefreshIndicator(
                          onRefresh: () => _load(reset: true),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, 96),
                            itemCount: _rows.length + (_hasMore ? 1 : 0),
                            separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
                            itemBuilder: (context, i) {
                              if (i == _rows.length) {
                                return Padding(padding: const EdgeInsets.all(Space.sm), child: OutlinedButton(onPressed: _more ? null : () => _load(reset: false), child: _more ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Charger plus')));
                              }
                              final s = _rows[i];
                              return RowCard(
                                leading: Avatar(s.name),
                                title: s.name,
                                subtitle: '${s.classroom} · ${s.matricule ?? s.internalNumber}',
                                trailing: s.assigned ? const StatusBadge(S.assigned, tone: Tone.info) : null,
                                onTap: () => context.push('/students/${s.id}?enrollment=${s.enrollmentId}&classroom=${Uri.encodeComponent(s.classroom)}'),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
