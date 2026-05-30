import 'package:flutter/material.dart';
import 'package:turbo_bridge/turbo_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start the Turbo Bridge server
  await TurboBridge.start(
    config: const BridgeConfig(port: 8888),
    ensureInitialized: false,
  );

  runApp(const BenchmarkTargetApp());
}

class BenchmarkTargetApp extends StatelessWidget {
  const BenchmarkTargetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Benchmark Target',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

/// Home page with navigation to different test scenarios.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _counter = 0;
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark Target')),
      drawer: Drawer(
        key: const ValueKey('app_drawer'),
        child: ListView(
          children: [
            const DrawerHeader(
              child: Text('Navigation', style: TextStyle(fontSize: 24)),
            ),
            ListTile(
              key: const ValueKey('nav_home'),
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedIndex = 0);
              },
            ),
            ListTile(
              key: const ValueKey('nav_form'),
              leading: const Icon(Icons.edit),
              title: const Text('Form'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedIndex = 1);
              },
            ),
            ListTile(
              key: const ValueKey('nav_list'),
              leading: const Icon(Icons.list),
              title: const Text('Scrollable List'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedIndex = 2);
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildCounterPage(),
          const FormPage(),
          const ScrollableListPage(),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              key: const ValueKey('increment_button'),
              onPressed: () => setState(() => _counter++),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.edit), label: 'Form'),
          NavigationDestination(icon: Icon(Icons.list), label: 'List'),
        ],
      ),
    );
  }

  Widget _buildCounterPage() {
    return Center(
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

/// A page with text input fields for testing text entry.
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

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
            onPressed: () {
              setState(() {
                _status =
                    'Submitted: ${_nameController.text}, ${_emailController.text}';
              });
            },
            child: const Text('Submit'),
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
    );
  }
}

/// A page with a long scrollable list.
class ScrollableListPage extends StatelessWidget {
  const ScrollableListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Tapped item $index')),
            );
          },
        );
      },
    );
  }
}
