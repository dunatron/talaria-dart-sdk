import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria_serverpod/src/shutdown_flush.dart';
import 'package:talaria_serverpod/talaria_serverpod.dart';
import 'package:test/test.dart';

/// Spans wait for their batch (talaria 0.3.9), so a server that stops
/// between batches must flush on shutdown or lose them. `attach` and
/// `registerShutdownFlush` add a `talaria.flush` Serverpod shutdown task.
void main() {
  late FakeTransport transport;
  late TalariaClient client;
  late _ShutdownTasks tasks;

  setUp(() {
    transport = FakeTransport();
    client = TalariaClient(
      TalariaOptions(
        url: 'https://api.example.com',
        apiKey: 'tal_prod_test_key_for_unit_tests',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      )..applySdkDocument({
        'schemaVersion': 1,
        'active': true,
        'tracing': {'enabled': true, 'tracesSampleRate': 1.0},
      }),
      transport: transport,
    );
    tasks = _ShutdownTasks();
  });

  tearDown(() async {
    if (!client.isClosed) await client.close();
  });

  Future<void> shutdown() => tasks.runAll();

  test('uses the documented task id', () {
    expect(TalariaServerpod.shutdownTaskId, 'talaria.flush');
    addShutdownFlushTask(tasks.addTask, client);
    expect(tasks.removeTask('talaria.flush'), isTrue);
  });

  test('the shutdown task sends spans still waiting for their batch', () async {
    addShutdownFlushTask(tasks.addTask, client);
    for (var i = 0; i < 3; i++) {
      client.startTransaction('GET /pending/$i').finish();
    }
    client.captureMessage('pending event');
    await Future<void>.delayed(Duration.zero);
    expect(transport.spanBatches, isEmpty, reason: 'batch not full yet');
    expect(client.spanQueueSize(), 3);

    await shutdown();

    expect(transport.spanBatches, hasLength(1));
    expect(transport.spanBatches.single.map((s) => s.name).toList(), [
      'GET /pending/0',
      'GET /pending/1',
      'GET /pending/2',
    ]);
    expect(client.spanQueueSize(), 0);
    expect(
      transport.batches.expand((b) => b).map((e) => e.message),
      contains('pending event'),
    );
  });

  test('registering twice keeps one task and does not throw', () async {
    addShutdownFlushTask(tasks.addTask, client);
    addShutdownFlushTask(tasks.addTask, client);
    client.startTransaction('GET /once').finish();
    await shutdown();
    expect(transport.spanBatches, hasLength(1));
  });

  test('a client closed before shutdown is left alone', () async {
    addShutdownFlushTask(tasks.addTask, client);
    client.startTransaction('GET /closed').finish();
    await client.close();
    final sent = transport.spanBatches.length;
    await shutdown();
    expect(transport.spanBatches, hasLength(sent));
  });
}

/// Same contract as Serverpod's shutdown `TaskManager` (whose
/// implementation is internal): a duplicate id throws [StateError], and
/// shutdown runs every task.
class _ShutdownTasks {
  final _tasks = <Object, Future<void> Function()>{};

  void addTask(Object id, Future<void> Function() task) {
    if (_tasks.containsKey(id)) {
      throw StateError('Task with id $id already exists.');
    }
    _tasks[id] = task;
  }

  bool removeTask(Object id) => _tasks.remove(id) != null;

  Future<void> runAll() async {
    await [for (final task in _tasks.values) task()].wait;
  }
}
