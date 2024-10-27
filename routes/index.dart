import 'dart:io';
import 'dart:isolate';
import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final body = await context.request.body();
  final code = body;

  final result = await _runCodeInIsolate(code);

  return Response.json(body: {'result': result});
}

Future<Map<String, dynamic>> _runCodeInIsolate(String code) async {
  final receivePort = ReceivePort();

  await Isolate.spawn(_isolateRunner, [receivePort.sendPort, code]);

  final result = await receivePort.first as Map<String, dynamic>;

  return result;
}

Future<void> _isolateRunner(List<dynamic> args) async {
  final sendPort = args[0] as SendPort;
  final code = args[1] as String;

  try {
    final tempFile = await _createTempDartFile(code);
    final result = await _runDartCode(tempFile);
    await tempFile.delete();

    sendPort.send(result);
  } catch (e) {
    sendPort.send({
      'output': 'Error: $e',
      'executionTime': null,
      'memoryUsed': null,
    });
  }
}

Future<File> _createTempDartFile(String code) async {
  final tempDir = Directory.systemTemp;
  final tempFile = File('${tempDir.path}/temp_dart_code.dart');
  await tempFile.writeAsString(code);

  return tempFile;
}

Future<Map<String, dynamic>> _runDartCode(File dartFile) async {
  final stopwatch = Stopwatch()..start();
  final initialMemory = ProcessInfo.currentRss;

  final result = await Process.run('dart', [dartFile.path]);

  final executionTime = stopwatch.elapsedMilliseconds;
  final finalMemory = ProcessInfo.currentRss;
  final memoryUsed = finalMemory - initialMemory;

  print("Process result: ${result.stdout}");
  print("Process error: ${result.stderr}");
  print("Process exit code: ${result.exitCode}");

  if (result.exitCode != 0) {
    return {
      'output': result.stderr.toString(),
      'executionTime': executionTime.toString(),
      'memoryUsed': null,
    };
  } else {
    return {
      'output': result.stdout.toString(),
      'executionTime': '${executionTime}ms',
      'memoryUsed': '${(memoryUsed / 1024).toStringAsFixed(2)}KB',
    };
  }
}
