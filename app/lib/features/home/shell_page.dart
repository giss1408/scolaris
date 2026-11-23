import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../money/arrears_page.dart';
import '../students/students_page.dart';
import 'dashboard_page.dart';
import 'profile_page.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.builder);
  final String label;
  final IconData icon, selectedIcon;
  final Widget Function(void Function(int) goTo) builder;
}

/// Bottom navigation (rail on wide screens). The tabs depend on the role: what a role can never do is not shown.
class ShellPage extends ConsumerStatefulWidget {
  const ShellPage({super.key});

  @override
  ConsumerState<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends ConsumerState<ShellPage> {
  int _index = 0;

  List<_Tab> _tabs(bool money) => [
        if (money) _Tab(S.tabHome, Icons.dashboard_outlined, Icons.dashboard, (go) => DashboardPage(goTo: go)),
        _Tab(S.tabStudents, Icons.groups_outlined, Icons.groups, (_) => const StudentsPage()),
        if (money) _Tab(S.tabArrears, Icons.warning_amber_outlined, Icons.warning_amber, (_) => const ArrearsPage()),
        _Tab(S.tabProfile, Icons.person_outline, Icons.person, (_) => const ProfilePage()),
      ];

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final tabs = _tabs(me.canCollect);
    final index = _index.clamp(0, tabs.length - 1);
    void goTo(int i) => setState(() => _index = i);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = IndexedStack(index: index, children: [for (final t in tabs) t.builder(goTo)]);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: goTo,
            labelType: NavigationRailLabelType.all,
            destinations: [for (final t in tabs) NavigationRailDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: Text(t.label))],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1200), child: body))),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: goTo,
        destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label)],
      ),
    );
  }
}

/// Index of a tab by its label (used by the dashboard shortcuts).
int tabIndexOf(bool money, String label) {
  final labels = [if (money) S.tabHome, S.tabStudents, if (money) S.tabArrears, S.tabProfile];
  return labels.indexOf(label);
}
