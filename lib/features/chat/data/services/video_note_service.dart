import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class VideoNoteService {
  Future<File> makeRoundVideo(String inputPath) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('Видеокружки можно создавать на телефоне');
    }

    final temporaryDirectory = await getTemporaryDirectory();
    final outputFile = File(
      '${temporaryDirectory.path}/video_note_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    const filter =
        "[0:v]scale=480:480:force_original_aspect_ratio=increase,"
        "crop=480:480,format=rgba,"
        "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':"
        "a='if(lte(pow(X-W/2,2)+pow(Y-H/2,2),pow(min(W,H)/2,2)),255,0)'"
        "[circle];"
        "color=c=white:s=480x480:r=30:d=60[background];"
        "[background][circle]overlay=shortest=1:format=auto,setsar=1[video]";
    final videoEncoder = Platform.isAndroid
        ? 'h264_mediacodec'
        : 'h264_videotoolbox';

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      inputPath,
      '-filter_complex',
      filter,
      '-map',
      '[video]',
      '-map',
      '0:a?',
      '-c:v',
      videoEncoder,
      '-pix_fmt',
      'yuv420p',
      '-b:v',
      '900k',
      '-c:a',
      'aac',
      '-b:a',
      '96k',
      '-t',
      '60',
      '-shortest',
      '-movflags',
      '+faststart',
      outputFile.path,
    ]);

    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getLogsAsString();
      debugPrint('Ошибка FFmpeg при создании видеокружка: $logs');
      if (await outputFile.exists()) await outputFile.delete();
      throw StateError('Не удалось преобразовать видео в кружок');
    }

    if (!await outputFile.exists() || await outputFile.length() == 0) {
      throw StateError('Обработанное видео не было создано');
    }

    return outputFile;
  }
}
