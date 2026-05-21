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
      home: const CounterPage(),
    );
  }
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark Target')),
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
            // Add some widget tree depth for realistic benchmarks
            _buildNestedWidgets(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('increment_button'),
        onPressed: () => setState(() => _counter++),
        child: const Icon(Icons.add),
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
