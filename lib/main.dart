import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void main() {
  runApp(const MainApp());
}

// =============================================================================
// Router Configuration
// =============================================================================

final _router = GoRouter(
  initialLocation: '/entities',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return AppShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/entities',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: EntitiesListScreen()),
          routes: [
            GoRoute(
              path: ':entityId',
              pageBuilder: (context, state) => NoTransitionPage(
                child: EntityDetailScreen(
                  entityId: state.pathParameters['entityId']!,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SelectionArea Bug - go_router',
      theme: ThemeData(useMaterial3: true),
      routerConfig: _router,
    );
  }
}

// =============================================================================
// AppShell - ShellRoute builder
// =============================================================================

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 200,
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Demo App',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.people, size: 20),
                  title: const Text('Entities', style: TextStyle(fontSize: 14)),
                  selected: true,
                  dense: true,
                  onTap: () => context.go('/entities'),
                ),
              ],
            ),
          ),
          Container(width: 1, color: Colors.grey[300]),

          // Main content
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 48,
                  color: Colors.white,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(location, style: const TextStyle(fontSize: 14)),
                ),
                Container(height: 1, color: Colors.grey[300]),

                // SelectionArea wraps the shell child (Navigator)
                Expanded(child: SelectionArea(child: child)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Entities List Screen
// =============================================================================

class EntitiesListScreen extends StatelessWidget {
  const EntitiesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      header: const Text(
        'Entities',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Table(
            border: TableBorder.all(color: Colors.grey[300]!),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(3),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey[100]),
                children: const [
                  _Cell(text: 'Name', bold: true),
                  _Cell(text: 'Email', bold: true),
                  _Cell(text: 'Phone', bold: true),
                  _Cell(text: 'Action', bold: true),
                ],
              ),
              for (final e in _entities)
                TableRow(
                  children: [
                    _Cell(text: e.name),
                    _Cell(text: e.email),
                    _Cell(text: e.phone),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextButton(
                        onPressed: () => context.go('/entities/${e.id}'),
                        child: const Text('View'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.text, this.bold = false});

  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
    );
  }
}

// =============================================================================
// Entity Detail Screen
// =============================================================================

class EntityDetailScreen extends StatelessWidget {
  const EntityDetailScreen({super.key, required this.entityId});

  final String entityId;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      header: _EntityHeader(entityId: entityId),
      body: _ContentBody(entityId: entityId),
    );
  }
}

class _EntityHeader extends StatelessWidget {
  const _EntityHeader({required this.entityId});

  final String entityId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'John Doe',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Text(
                'Individual · Active · $entityId',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => context.go('/entities'),
          child: const Text('Back to list'),
        ),
      ],
    );
  }
}

class _ContentBody extends StatelessWidget {
  const _ContentBody({required this.entityId});

  final String entityId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DefaultTabController(
          length: 3,
          child: TabBar(
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Portfolio'),
              Tab(text: 'Documents'),
            ],
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey[500],
            indicatorColor: Colors.blue,
            isScrollable: true,
          ),
        ),
        const SizedBox(height: 16),
        _surface('Personal Details', const [
          InfoRow(label: 'First Name', value: 'John'),
          InfoRow(label: 'Last Name', value: 'Doe'),
          InfoRow(label: 'Date of Birth', value: 'Jan 15, 1990'),
          InfoRow(label: 'Nationality', value: 'Netherlands'),
        ]),
        const SizedBox(height: 16),
        _surface('Contact Information', const [
          InfoRow(label: 'Email', value: 'john.doe@example.com'),
          InfoRow(label: 'Phone', value: '+31 6 1234 5678'),
          InfoRow(label: 'Address', value: 'Keizersgracht 123'),
          InfoRow(label: '', value: '1015 CJ Amsterdam, Netherlands'),
        ]),
        const SizedBox(height: 16),
        _surface('Financial Details', const [
          InfoRow(label: 'IBAN', value: 'NL91 ABNA 0417 1643 00'),
          InfoRow(label: 'Tax Number', value: '123456789B01'),
        ]),
        const SizedBox(height: 16),
        _surface('Investment Permissions', [
          _tagRow('Notes Investments', true),
          _tagRow('Private Investments', true),
          _tagRow('Card Payments', false),
          _tagRow('Large Investments', false),
        ]),
        const SizedBox(height: 16),
        _surface('Account Status', const [
          InfoRow(label: 'Created', value: 'Mar 15, 2024'),
          InfoRow(label: 'Activated', value: 'Mar 20, 2024'),
          InfoRow(label: 'Last Updated', value: 'Feb 18, 2026'),
        ]),
        const SizedBox(height: 16),
        for (int i = 0; i < 3; i++) ...[
          _surface('Additional Section ${i + 1}', [
            InfoRow(label: 'Reference', value: 'REF-${1000 + i}-ABCD-EFGH'),
            const InfoRow(label: 'Status', value: 'Completed'),
            const InfoRow(label: 'Notes', value: 'Lorem ipsum dolor sit amet'),
          ]),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

// =============================================================================
// PageScaffold (mirrors BrxsPageScaffold with LayoutBuilder)
// =============================================================================

class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.header, required this.body});

  final Widget header;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isBounded = constraints.hasBoundedHeight;

        return Column(
          mainAxisSize: isBounded ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: header,
            ),
            const SizedBox(height: 16),
            if (isBounded)
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: body,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: body,
              ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// Common Widgets
// =============================================================================

Widget _surface(String title, List<Widget> rows) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Padding(
      padding: const EdgeInsets.all(1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...rows,
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _tagRow(String label, bool allowed) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: TextStyle(color: Colors.grey[600])),
        ),
        Expanded(
          flex: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message: allowed ? 'Allowed' : 'Not allowed',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: allowed ? Colors.green[50] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  allowed ? 'Allowed' : 'Not allowed',
                  style: TextStyle(
                    color: allowed ? Colors.green[700] : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(flex: 3, child: Text(value)),
        ],
      ),
    );
  }
}

// =============================================================================
// Sample Data
// =============================================================================

class _EntityData {
  const _EntityData({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
}

const _entities = [
  _EntityData(
    id: 'entity-1',
    name: 'John Doe',
    email: 'john.doe@example.com',
    phone: '+31 6 1234 5678',
  ),
  _EntityData(
    id: 'entity-2',
    name: 'Jane Smith',
    email: 'jane.smith@example.com',
    phone: '+31 6 8765 4321',
  ),
  _EntityData(
    id: 'entity-3',
    name: 'Bob Johnson',
    email: 'bob.johnson@example.com',
    phone: '+31 6 1111 2222',
  ),
  _EntityData(
    id: 'entity-4',
    name: 'Alice Williams',
    email: 'alice.williams@example.com',
    phone: '+31 6 3333 4444',
  ),
];
