import 'package:talaria/talaria.dart';

/// Serverpod shutdown task id for the Talaria flush.
const talariaShutdownTaskId = 'talaria.flush';

/// Registers the flush with [addTask] (Serverpod's
/// `pod.experimental.shutdownTasks.addTask`). The task flushes [client]
/// unless it is already closed, so spans still waiting for their batch are
/// sent before the process exits. A second registration is ignored.
void addShutdownFlushTask(
  void Function(Object id, Future<void> Function() task) addTask,
  TalariaClient client,
) {
  try {
    addTask(talariaShutdownTaskId, () async {
      if (!client.isClosed) {
        await client.flush();
      }
    });
  } on StateError {
    // Already registered.
  }
}
