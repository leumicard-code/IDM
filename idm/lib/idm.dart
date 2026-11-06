import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

const reset = '\x1B[0m';
const green = '\x1B[32m';
const cyan = '\x1B[36m';
const yellow = '\x1B[33m';
const blue = '\x1B[34m';
const bold = '\x1B[1m';
const maxRetries = 10;
const retryBaseDelay = Duration(seconds: 1);

void main(List<String> args) async {
  if (args.isEmpty) {
    print('${yellow}שימוש:${reset} dart download.dart <URL> [שם_קובץ]');
    exit(1);
  }

  final url = args[0];
  final fileName = args.length > 1 ? args[1] : p.basename(Uri.parse(url).path);
  final savePath = (fileName.isEmpty || fileName == '/') ? 'downloaded_file' : fileName;
  const connections = 8;

  print('\n${bold}$cyan🚀  Dart Download Manager (with Resume)${reset}');
  print('${blue}URL:${reset}        $url');
  print('${blue}קובץ:${reset}       $savePath');
  print('${blue}חיבורים:${reset}    $connections\n');

  try {
    await multiDownload(url, savePath, connections);
    print('\n${green}✓ ההורדה הסתיימה בהצלחה${reset}\n');
  } catch (e) {
    print('\n${yellow}✗ שגיאה: $e${reset}');
    exit(1);
  }
}

Future<void> multiDownload(String url, String savePath, int connections) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 30),
    headers: {'User-Agent': 'DartDownloadManager/1.1'},
  ));

  final head = await dio.head(url);
  final contentLength = int.tryParse(head.headers.value('content-length') ?? '0') ?? 0;
  final acceptRanges = head.headers.value('accept-ranges')?.toLowerCase() == 'bytes';

  if (contentLength == 0) throw Exception('לא ניתן לקבוע את גודל הקובץ');

  if (!acceptRanges) {
    print('${yellow}השרת לא תומך ב-Range. עובר להורדה רגילה.${reset}');
    await singleDownload(dio, url, savePath, contentLength);
    return;
  }

  print('${cyan}גודל קובץ:${reset} ${(contentLength / 1024 / 1024).toStringAsFixed(2)} MB');
  print('${cyan}Resume:${reset}      פעיל\n');

  final partSize = (contentLength / connections).ceil();
  final received = List<int>.filled(connections, 0);
  final tempFiles = <String>[];

  // בודקים מה כבר קיים (Resume)
  for (var i = 0; i < connections; i++) {
    final tempPath = '$savePath.part$i';
    tempFiles.add(tempPath);
    final file = File(tempPath);
    if (await file.exists()) {
      received[i] = await file.length();
    }
  }

  final alreadyDownloaded = received.reduce((a, b) => a + b);
  if (alreadyDownloaded > 0) {
    print('${green}ממשיך הורדה קודמת...${reset} (${(alreadyDownloaded / 1024 / 1024).toStringAsFixed(1)} MB כבר ירדו)\n');
  }

  final stopwatch = Stopwatch()..start();
  int lastTotal = alreadyDownloaded;

  void updateProgress() {
    final totalReceived = received.reduce((a, b) => a + b);
    final percent = (totalReceived / contentLength * 100).clamp(0, 100);
    final downloadedMB = totalReceived / 1024 / 1024;
    final totalMB = contentLength / 1024 / 1024;

    final elapsed = max(stopwatch.elapsedMilliseconds / 1000, 0.1);
    final speed = (totalReceived - lastTotal) / 1024 / elapsed;
    lastTotal = totalReceived;

    final speedText = speed > 1024
    ? '${(speed / 1024).toStringAsFixed(1)} MB/s'
    : '${speed.toStringAsFixed(0)} KB/s';

    const barWidth = 28;
    final filled = (percent / 100 * barWidth).round();
    final bar = '${green}${'█' * filled}${reset}${'─' * (barWidth - filled)}';

    stdout.write('\r$bar ${percent.toStringAsFixed(1)}%  '
    '${downloadedMB.toStringAsFixed(1)}/${totalMB.toStringAsFixed(1)} MB  '
    '$cyan$speedText$reset   ');
  }

  final futures = <Future>[];

  for (var i = 0; i < connections; i++) {
    final start = i * partSize;
    final end = min((i + 1) * partSize - 1, contentLength - 1);
    final currentLength = received[i];

    // אם החלק כבר הושלם – מדלגים
    if (start + currentLength > end) {
      received[i] = end - start + 1;
      continue;
    }

    final resumeFrom = start + currentLength;

    futures.add(
      downloadSegment(
        dio: dio,
        url: url,
        savePath: tempFiles[i],
        start: resumeFrom,
        end: end,
        append: currentLength > 0,
        onProgress: (count) {
          received[i] = currentLength + count;
          updateProgress();
        },
      ),
    );
  }

  if (futures.isNotEmpty) {
    await Future.wait(futures);
  }

  stopwatch.stop();

  // חיבור החלקים
  stdout.write('\n\n${yellow}מחבר חלקים...${reset}');
  final output = File(savePath).openWrite();
  for (final temp in tempFiles) {
    final f = File(temp);
    if (await f.exists()) {
      await output.addStream(f.openRead());
      await f.delete();
    }
  }
  await output.close();

  final seconds = max(stopwatch.elapsed.inSeconds, 1);
  final avg = (contentLength / 1024 / 1024) / seconds;
  print('\n${green}סיום!${reset} זמן: ${seconds}s | ממוצע: ${avg.toStringAsFixed(1)} MB/s');
}

Future<void> downloadSegment({
  required Dio dio,
  required String url,
  required String savePath,
  required int start,
  required int end,
  required bool append,
  required Function(int) onProgress,
}) async {
  var attempt = 0;
  var downloaded = 0;

  while (true) {
    try {
      final file = File(savePath);

      // כמה bytes כבר נמצאים בחלק הזה
      final existingBytes = await file.exists() ? await file.length() : 0;

      final currentStart = start + existingBytes;

      // החלק כבר הושלם
      if (currentStart > end) {
        return;
      }

      downloaded = existingBytes;

      print(
        '\n${cyan}Range: $currentStart-$end '
      '(attempt ${attempt + 1}/$maxRetries)${reset}',
      );

      await dio.download(
        url,
        savePath,
        options: Options(
          headers: {
            'Range': 'bytes=$currentStart-$end',
          },
        ),
        fileAccessMode: existingBytes > 0
        ? FileAccessMode.append
        : FileAccessMode.write,
        onReceiveProgress: (received, _) {
          onProgress(downloaded + received);
        },
      );

      return;
    } catch (e) {
      attempt++;

      if (attempt >= maxRetries) {
        print(
          '\n${yellow}✗ Range $start-$end נכשל '
        'אחרי $maxRetries ניסיונות${reset}',
        );

        rethrow;
      }

      final delaySeconds = 1 << (attempt - 1);

      print(
        '\n${yellow}⚠ החיבור נכשל.${reset} '
      'Retry בעוד ${delaySeconds}s...',
      );

      await Future.delayed(
        Duration(seconds: delaySeconds),
      );
    }
  }
}

Future<void> singleDownload(Dio dio, String url, String savePath, int total) async {
  await dio.download(
    url,
    savePath,
    onReceiveProgress: (count, _) {
      final percent = (count / total * 100).toStringAsFixed(1);
      stdout.write('\rהורדה רגילה: $percent%');
    },
  );
}
//EXIT

