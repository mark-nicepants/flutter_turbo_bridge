import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Direct connection to the Dart VM Service for evaluation and inspection.
class VmServiceConnection {
  final String vmServiceUri;
  VmService? _vmService;
  String? _mainIsolateId;

  VmServiceConnection({required this.vmServiceUri});

  /// Whether we have an active connection.
  bool get isConnected => _vmService != null;

  /// The main isolate ID (cached after first resolution).
  String? get mainIsolateId => _mainIsolateId;

  /// Connect to the VM Service.
  Future<void> connect() async {
    _vmService = await vmServiceConnectUri(vmServiceUri);
    await _resolveMainIsolate();
  }

  /// Get the underlying VM Service instance.
  VmService get vmService {
    if (_vmService == null) {
      throw StateError('Not connected. Call connect() first.');
    }
    return _vmService!;
  }

  /// Evaluate a Dart expression in the main isolate.
  Future<Response> evaluate(String expression, {String? isolateId}) async {
    final id = isolateId ?? _mainIsolateId;
    if (id == null) throw StateError('No isolate available');

    final isolate = await vmService.getIsolate(id);
    final rootLibId = isolate.rootLib?.id;
    if (rootLibId == null) throw StateError('No root library found');

    return vmService.evaluate(id, rootLibId, expression);
  }

  /// Get information about the VM.
  Future<VM> getVM() => vmService.getVM();

  /// Get information about the main isolate.
  Future<Isolate> getIsolate() async {
    final id = _mainIsolateId;
    if (id == null) throw StateError('No isolate available');
    return vmService.getIsolate(id);
  }

  /// Call a Flutter service extension.
  Future<Response> callServiceExtension(
    String method, {
    Map<String, String>? args,
  }) async {
    final id = _mainIsolateId;
    if (id == null) throw StateError('No isolate available');

    return vmService.callServiceExtension(
      method,
      isolateId: id,
      args: args,
    );
  }

  Future<void> _resolveMainIsolate() async {
    final vm = await vmService.getVM();
    for (final isolateRef in vm.isolates ?? <IsolateRef>[]) {
      if (isolateRef.isSystemIsolate != true) {
        _mainIsolateId = isolateRef.id;
        return;
      }
    }
  }

  /// Disconnect and clean up.
  Future<void> dispose() async {
    await _vmService?.dispose();
    _vmService = null;
    _mainIsolateId = null;
  }
}
