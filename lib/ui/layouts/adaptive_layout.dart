import 'package:flutter/material.dart';

/// A simple adaptive layout that provides a different structure based on screen width.
/// For phones, it might use a bottom navigation bar.
/// For tablets, a navigation rail.
/// For desktops, a permanent drawer.
class AdaptiveLayout extends StatelessWidget {
  final Widget body;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const AdaptiveLayout({
    super.key,
    required this.body,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          // Mobile layout
          return Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard),
                  label: 'Dashboard',
                ),
                NavigationDestination(icon: Icon(Icons.people), label: 'Teams'),
                NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          );
        } else if (constraints.maxWidth < 1200) {
          // Tablet layout (Navigation Rail)
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard),
                      label: Text('Dashboard'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.people),
                      label: Text('Teams'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: body),
              ],
            ),
          );
        } else {
          // Desktop layout (Permanent Drawer)
          return Scaffold(
            body: Row(
              children: [
                Drawer(
                  elevation: 0,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  child: ListView(
                    children: [
                      const DrawerHeader(
                        child: Center(
                          child: Text(
                            'SyncBoard',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.dashboard),
                        title: const Text('Dashboard'),
                        selected: selectedIndex == 0,
                        onTap: () => onDestinationSelected(0),
                      ),
                      ListTile(
                        leading: const Icon(Icons.people),
                        title: const Text('Teams'),
                        selected: selectedIndex == 1,
                        onTap: () => onDestinationSelected(1),
                      ),
                      ListTile(
                        leading: const Icon(Icons.settings),
                        title: const Text('Settings'),
                        selected: selectedIndex == 2,
                        onTap: () => onDestinationSelected(2),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
      },
    );
  }
}
