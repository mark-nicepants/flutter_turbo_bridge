import 'package:flutter/material.dart';
import 'package:turbo_bridge/turbo_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start the Turbo Bridge server with DevTools data + SSE enabled. The
  // DevTools web UI runs on the host (e.g. `dart run turbo_bridge_mcp:devtools`
  // or the MCP server) and connects to these endpoints over the bridge port.
  // Never enable in a production build.
  await TurboBridge.start(
    config: const BridgeConfig(
      port: 8888,
      enableDevTools: true,
    ),
    ensureInitialized: false,
  );

  TurboBridge.instance.logs.info('App started', category: 'lifecycle');

  runApp(const BenchmarkTargetApp());
}

class BenchmarkTargetApp extends StatelessWidget {
  const BenchmarkTargetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Benchmark Target',
      // TurboNavigationObserver pushes every push/pop/replace into the
      // DevTools timeline. Add it to your app's MaterialApp / Router to
      // get free navigation traces.
      navigatorObservers: [TurboNavigationObserver()],
      initialRoute: '/home',
      routes: {
        '/home': (_) => const HomePage(),
        '/form': (_) => const FormPage(),
        '/list': (_) => const ScrollableListPage(),
        '/detail': (_) => const DetailPage(),
      },
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
    );
  }
}

/// Home page with a counter + a Card of static items.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _counter = 0;

  @override
  void initState() {
    super.initState();
    TurboBridge.instance.logs.debug(
      'HomePage initState',
      category: 'lifecycle',
    );
  }

  void _increment() {
    setState(() => _counter++);
    TurboBridge.instance.logs.info(
      'Counter incremented to $_counter',
      category: 'interaction',
      data: {'counter': _counter},
    );
    if (_counter % 5 == 0) {
      TurboBridge.instance.logs.warn(
        'Counter hit a multiple of 5',
        category: 'milestone',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark Target · Home')),
      drawer: const _AppDrawer(currentRoute: '/home'),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Counter value:'),
            Text(
              '$_counter',
              key: const ValueKey('counter_text'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            _buildNestedWidgets(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('increment_button'),
        onPressed: _increment,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: _AppBottomNav(currentRoute: '/home'),
    );
  }

  Widget _buildNestedWidgets() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(
            5,
            (i) => ListTile(
              leading: Icon(Icons.star, color: Colors.amber[100 * (i + 1)]),
              title: Text('Item $i'),
              subtitle: Text('Subtitle for item $i'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Text-entry page demonstrating logs on submit + a fake network call.
class FormPage extends StatefulWidget {
  const FormPage({super.key});

  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  String _status = '';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    TurboBridge.instance.logs.debug(
      'FormPage initState',
      category: 'lifecycle',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text;
    final email = _emailController.text;
    final message = _messageController.text;
    TurboBridge.instance.logs.info(
      'Form submit attempted',
      category: 'form',
      data: {'name': name, 'email': email, 'messageLen': message.length},
    );
    if (name.isEmpty || email.isEmpty) {
      TurboBridge.instance.logs.warn(
        'Form validation failed',
        category: 'form',
        data: {'reason': 'name or email empty'},
      );
      setState(() => _status = 'Name and email are required.');
      return;
    }
    setState(() {
      _submitting = true;
      _status = 'Submitting…';
    });

    // Fake an HTTP POST so the Network row gets a real-looking entry.
    final sw = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 320));
    sw.stop();
    final ok = !email.contains('@invalid');
    TurboBridge.instance.network.record(
      method: 'POST',
      url: 'https://api.example.com/submissions',
      status: ok ? 201 : 422,
      durationMs: sw.elapsedMilliseconds,
      requestHeaders: {
        'authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.demo',
        'content-type': 'application/json',
      },
      requestBody: '{"name":"$name","email":"$email","message":"$message"}',
      responseHeaders: {'content-type': 'application/json'},
      responseBody: ok
          ? '{"id":${DateTime.now().millisecondsSinceEpoch},"status":"queued"}'
          : '{"error":"invalid_email"}',
    );
    if (!ok) {
      TurboBridge.instance.logs.error(
        'Submission rejected by server',
        category: 'form',
        data: {'email': email, 'status': 422},
      );
      setState(() {
        _submitting = false;
        _status = 'Server rejected the submission.';
      });
      return;
    }
    TurboBridge.instance.logs.info(
      'Submission accepted',
      category: 'form',
      data: {'durationMs': sw.elapsedMilliseconds},
    );
    setState(() {
      _submitting = false;
      _status = 'Submitted: $name, $email';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark Target · Form')),
      drawer: const _AppDrawer(currentRoute: '/form'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('name_field'),
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('email_field'),
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('message_field'),
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const ValueKey('submit_button'),
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting…' : 'Submit'),
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _status,
                key: const ValueKey('form_status'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _AppBottomNav(currentRoute: '/form'),
    );
  }
}

/// Long scrollable list. Tapping an item pushes /detail.
class ScrollableListPage extends StatelessWidget {
  const ScrollableListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark Target · List')),
      drawer: const _AppDrawer(currentRoute: '/list'),
      body: ListView.builder(
        key: const ValueKey('scrollable_list'),
        itemCount: 100,
        itemBuilder: (context, index) {
          return ListTile(
            key: ValueKey('list_item_$index'),
            leading: CircleAvatar(child: Text('$index')),
            title: Text('List item $index'),
            subtitle: Text('Description for item $index'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              TurboBridge.instance.logs.info(
                'List item tapped',
                category: 'interaction',
                data: {'index': index},
              );
              Navigator.pushNamed(
                context,
                '/detail',
                arguments: {'index': index},
              );
            },
          );
        },
      ),
      bottomNavigationBar: _AppBottomNav(currentRoute: '/list'),
    );
  }
}

/// Detail page reached by tapping a list item. Demonstrates a push +
/// fake "fetch detail" network call on entry.
class DetailPage extends StatefulWidget {
  const DetailPage({super.key});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Map<String, dynamic>? _payload;
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final index = args?['index'] as int? ?? 0;
    _fetch(index);
  }

  Future<void> _fetch(int index) async {
    final sw = Stopwatch()..start();
    TurboBridge.instance.logs.debug(
      'Fetching item detail',
      category: 'detail',
      data: {'index': index},
    );
    await Future<void>.delayed(Duration(milliseconds: 120 + (index % 7) * 30));
    sw.stop();
    final ok = index % 17 != 0; // an occasional simulated failure
    TurboBridge.instance.network.record(
      method: 'GET',
      url: 'https://api.example.com/items/$index',
      status: ok ? 200 : 503,
      durationMs: sw.elapsedMilliseconds,
      requestHeaders: const {
        'authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.demo',
        'accept': 'application/json',
      },
      responseHeaders: const {'content-type': 'application/json'},
      responseBody: ok
          ? '{"id":$index,"title":"Item $index","price":${(index + 1) * 99}}'
          : '{"error":"upstream_unavailable"}',
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _payload = {
          'id': index,
          'title': 'Item $index',
          'price': (index + 1) * 99,
        };
        _loading = false;
      });
    } else {
      TurboBridge.instance.logs.error(
        'Item detail fetch failed',
        category: 'detail',
        data: {'index': index, 'status': 503},
      );
      setState(() {
        _error = 'Could not load item $index (503).';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final index = args?['index'] as int? ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text('Detail · item $index')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(_error!),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _payload!['title'] as String,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text('Price: \$${_payload!['price']}'),
                    ],
                  ),
      ),
    );
  }
}

/// Drawer shared across all top-level pages.
class _AppDrawer extends StatelessWidget {
  final String currentRoute;
  const _AppDrawer({required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      key: const ValueKey('app_drawer'),
      child: ListView(
        children: [
          const DrawerHeader(
            child: Text('Navigation', style: TextStyle(fontSize: 24)),
          ),
          _navTile(context, '/home', Icons.home, 'Home', 'nav_home'),
          _navTile(context, '/form', Icons.edit, 'Form', 'nav_form'),
          _navTile(context, '/list', Icons.list, 'Scrollable list', 'nav_list'),
        ],
      ),
    );
  }

  ListTile _navTile(
    BuildContext context,
    String route,
    IconData icon,
    String label,
    String keyName,
  ) {
    final selected = route == currentRoute;
    return ListTile(
      key: ValueKey(keyName),
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: () {
        Navigator.pop(context);
        if (selected) return;
        TurboBridge.instance.logs.debug(
          'Drawer tap',
          category: 'navigation',
          data: {'to': route, 'from': currentRoute},
        );
        Navigator.pushReplacementNamed(context, route);
      },
    );
  }
}

class _AppBottomNav extends StatelessWidget {
  final String currentRoute;
  const _AppBottomNav({required this.currentRoute});

  static const _routes = ['/home', '/form', '/list'];

  @override
  Widget build(BuildContext context) {
    final idx = _routes.indexOf(currentRoute);
    return NavigationBar(
      selectedIndex: idx < 0 ? 0 : idx,
      onDestinationSelected: (i) {
        final to = _routes[i];
        if (to == currentRoute) return;
        TurboBridge.instance.logs.debug(
          'BottomNav tap',
          category: 'navigation',
          data: {'to': to, 'from': currentRoute},
        );
        Navigator.pushReplacementNamed(context, to);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.edit), label: 'Form'),
        NavigationDestination(icon: Icon(Icons.list), label: 'List'),
      ],
    );
  }
}
