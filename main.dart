import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:translator/translator.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const MyApp());
}

Color lighten(Color c, [double amount = 0.12]) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

Color darken(Color c, [double amount = 0.18]) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

bool isVideoPath(String p) {
  final l = p.toLowerCase();
  return l.endsWith('.mp4') ||
      l.endsWith('.mov') ||
      l.endsWith('.mkv') ||
      l.endsWith('.webm') ||
      l.endsWith('.3gp') ||
      l.endsWith('.avi') ||
      l.endsWith('.m4v');
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'صنعة كليب',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: const Color(0xFF0E0E12),
      ),
      home: const VideoEditorHome(),
    );
  }
}

class Button3D extends StatefulWidget {
  final Color color;
  final Widget child;
  final VoidCallback onTap;

  const Button3D({
    Key? key,
    required this.color,
    required this.child,
    required this.onTap,
  }) : super(key: key);

  @override
  State<Button3D> createState() => _Button3DState();
}

class _Button3DState extends State<Button3D> {
  bool down = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return GestureDetector(
      onTapDown: (_) => setState(() => down = true),
      onTapUp: (_) {
        setState(() => down = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => down = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(0, down ? 4 : 0, 0),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [lighten(c, 0.15), c],
          ),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.35), width: 1.5),
          ),
          boxShadow: [
            BoxShadow(color: darken(c), offset: Offset(0, down ? 2 : 6)),
            BoxShadow(
              color: c.withOpacity(0.35),
              blurRadius: 16,
              offset: Offset(0, down ? 4 : 10),
            ),
          ],
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

// معاينة فيديو (اضغط للتشغيل)
class VideoTile extends StatefulWidget {
  final String path;
  const VideoTile({Key? key, required this.path}) : super(key: key);

  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  late VideoPlayerController c;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    c = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (mounted) setState(() => ready = true);
      });
    c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Center(child: CircularProgressIndicator(color: Colors.orange));
    }
    return GestureDetector(
      onTap: () => c.value.isPlaying ? c.pause() : c.play(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
          if (!c.value.isPlaying)
            const Center(
              child: Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
            ),
        ],
      ),
    );
  }
}

class Subtitle {
  final Duration start;
  final Duration end;
  final String text;
  Subtitle(this.start, this.end, this.text);
}

String srtTime(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)},$ms';
}

class VideoEditorHome extends StatefulWidget {
  const VideoEditorHome({Key? key}) : super(key: key);

  @override
  State<VideoEditorHome> createState() => _VideoEditorHomeState();
}

class _VideoEditorHomeState extends State<VideoEditorHome> {
  final ImagePicker _picker = ImagePicker();
  final List<XFile> media = [];

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  String? _localeId;
  bool isRecording = false;
  bool _restarting = false;
  final Stopwatch _watch = Stopwatch();
  Duration _lastEnd = Duration.zero;

  final GoogleTranslator _translator = GoogleTranslator();
  final List<Subtitle> subtitles = [];
  String transcribedText = "هنا ستبين الكتابة المترجمة سطر ورا سطر...";
  String selectedLanguage = "الفرنسية (Français)";
  final Map<String, String> languages = {
    "الفرنسية (Français)": "fr",
    "الإنجليزية (English)": "en",
    "الإسبانية (Español)": "es",
  };

  bool exporting = false;
  String exportStatus = '';
  String? lastExportPath;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    FFmpegKitConfig.setFontDirectoryList(["/system/fonts", "/System/Library/Fonts"]);
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------- صور + فيديوهات ----------
  Future<void> pickMedia() async {
    try {
      final files = await _picker.pickMultipleMedia();
      if (files.isEmpty) return;
      setState(() => media.addAll(files));
    } catch (e) {
      _msg('تعذر فتح المعرض: $e');
    }
  }

  // ---------- الصوت ----------
  Future<void> _initSpeech() async {
    _speechReady = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && isRecording) {
          _restartListening();
        }
      },
      onError: (e) {
        if (isRecording) _restartListening();
      },
    );
    if (_speechReady) {
      final locales = await _speech.locales();
      final ids = locales.map((l) => l.localeId).toList();
      _localeId = ids.firstWhere(
        (id) => id.toLowerCase().replaceAll('-', '_') == 'ar_ma',
        orElse: () => ids.firstWhere(
          (id) => id.toLowerCase().startsWith('ar'),
          orElse: () => '',
        ),
      );
      if (_localeId!.isEmpty) _localeId = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _restartListening() async {
    if (_restarting || !isRecording) return;
    _restarting = true;
    await Future.delayed(const Duration(milliseconds: 300));
    _restarting = false;
    if (isRecording) await _listen();
  }

  Future<void> _listen() async {
    if (!_speechReady || _speech.isListening) return;
    await _speech.listen(
      localeId: _localeId,
      listenFor: const Duration(minutes: 1),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
      ),
      onResult: _onResult,
    );
  }

  void _onResult(SpeechRecognitionResult r) {
    if (r.finalResult) {
      _handleFinal(r.recognizedWords);
    } else {
      setState(() => transcribedText = r.recognizedWords);
    }
  }

  Future<void> _handleFinal(String text) async {
    text = text.trim();
    if (text.isEmpty) return;
    final start = _lastEnd;
    final end = _watch.elapsed;
    _lastEnd = end;

    String translated;
    try {
      final t = await _translator.translate(
        text,
        from: 'ar',
        to: languages[selectedLanguage]!,
      );
      translated = t.text;
    } catch (e) {
      translated = text;
      _msg('الترجمة تتطلب إنترنت');
    }
    if (!mounted) return;
    setState(() {
      subtitles.add(Subtitle(start, end, translated));
      transcribedText = translated;
    });
  }

  Future<void> toggleRecording() async {
    if (!_speechReady) {
      _msg('التعرف على الصوت غير متاح (تحقق من إذن الميكروفون)');
      return;
    }
    if (!isRecording) {
      setState(() {
        isRecording = true;
        transcribedText = "جاري الاستماع لصوتك (الدارجة/العربية)...";
      });
      _watch
        ..reset()
        ..start();
      _lastEnd = Duration.zero;
      subtitles.clear();
      await _listen();
    } else {
      setState(() => isRecording = false);
      await _speech.stop();
      _watch.stop();
      setState(() => transcribedText =
          "تم! ${subtitles.length} سطر مترجم إلى: $selectedLanguage");
    }
  }

  // ---------- التصدير 720x1280 (مقاس Reels) ----------
  Future<void> exportVideo({bool share = false}) async {
    if (media.isEmpty) {
      _msg('أضف صور أو فيديوهات أولا');
      return;
    }
    if (isRecording) await toggleRecording();
    setState(() {
      exporting = true;
      exportStatus = 'تحضير الملفات...';
    });

    try {
      final dir = await getTemporaryDirectory();
      final work = Directory('${dir.path}/work');
      if (await work.exists()) await work.delete(recursive: true);
      await work.create(recursive: true);

      // مدة الفيديوهات وهل فيها صوت
      final durations = <int, double>{};
      final hasAudio = <int, bool>{};
      double videoTotal = 0;
      int imgCount = 0;
      for (var i = 0; i < media.length; i++) {
        if (isVideoPath(media[i].path)) {
          final s = await FFprobeKit.getMediaInformation(media[i].path);
          final info = await s.getMediaInformation();
          final d = double.tryParse(info?.getDuration() ?? '') ?? 5.0;
          durations[i] = d;
          videoTotal += d;
          hasAudio[i] = (info?.getStreams() ?? [])
              .any((st) => st.getType() == 'audio');
        } else {
          imgCount++;
        }
      }

      final subSec = _lastEnd.inMilliseconds / 1000.0;
      double imgDur = 3.0;
      if (imgCount > 0 && subSec > videoTotal) {
        imgDur = ((subSec - videoTotal) / imgCount).clamp(2.0, 30.0).toDouble();
      }
      final imgDurStr = imgDur.toStringAsFixed(2);

      const vf =
          'scale=720:1280:force_original_aspect_ratio=decrease,pad=720:1280:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p';

      // 1) كل ملف يتحول لمقطع 720x1280
      final segs = <String>[];
      for (var i = 0; i < media.length; i++) {
        setState(() => exportStatus = 'معالجة ${i + 1} / ${media.length}');
        final out = '${work.path}/seg$i.mp4';
        final path = media[i].path;
        List<String> args;
        if (!isVideoPath(path)) {
          args = [
            '-y', '-loop', '1', '-t', imgDurStr, '-i', path,
            '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo',
            '-t', imgDurStr, '-vf', vf,
            '-c:v', 'libx264', '-c:a', 'aac', '-ar', '44100', '-ac', '2',
            '-shortest', out,
          ];
        } else if (hasAudio[i] == true) {
          args = [
            '-y', '-i', path, '-vf', vf,
            '-c:v', 'libx264', '-c:a', 'aac', '-ar', '44100', '-ac', '2',
            out,
          ];
        } else {
          args = [
            '-y', '-i', path,
            '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo',
            '-vf', vf, '-map', '0:v:0', '-map', '1:a:0',
            '-c:v', 'libx264', '-c:a', 'aac', '-ar', '44100', '-ac', '2',
            '-shortest', out,
          ];
        }
        final s = await FFmpegKit.executeWithArguments(args);
        if (!ReturnCode.isSuccess(await s.getReturnCode())) {
          throw 'فشلت معالجة الملف رقم ${i + 1}';
        }
        segs.add(out);
      }

      // 2) ربط المقاطع
      setState(() => exportStatus = 'ربط المقاطع...');
      final list = StringBuffer();
      for (final s in segs) {
        list.writeln("file '$s'");
      }
      final listFile = File('${work.path}/list.txt');
      await listFile.writeAsString(list.toString());
      final joined = '${work.path}/joined.mp4';
      final c1 = await FFmpegKit.executeWithArguments([
        '-y', '-f', 'concat', '-safe', '0', '-i', listFile.path,
        '-c', 'copy', joined,
      ]);
      if (!ReturnCode.isSuccess(await c1.getReturnCode())) {
        throw 'فشل ربط المقاطع';
      }

      // 3) الترجمة فوق الفيديو
      String finalPath = joined;
      if (subtitles.isNotEmpty) {
        setState(() => exportStatus = 'كتابة الترجمة...');
        final srt = StringBuffer();
        for (var i = 0; i < subtitles.length; i++) {
          final s = subtitles[i];
          srt.writeln('${i + 1}');
          srt.writeln('${srtTime(s.start)} --> ${srtTime(s.end)}');
          srt.writeln(s.text);
          srt.writeln();
        }
        final srtFile = File('${work.path}/subs.srt');
        await srtFile.writeAsString(srt.toString());
        finalPath =
            '${dir.path}/sanaa_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final c2 = await FFmpegKit.executeWithArguments([
          '-y', '-i', joined,
          '-vf',
          "subtitles=${srtFile.path}:force_style='FontSize=12,Outline=2,MarginV=30'",
          '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'copy',
          finalPath,
        ]);
        if (!ReturnCode.isSuccess(await c2.getReturnCode())) {
          throw 'فشلت كتابة الترجمة';
        }
      } else {
        final copy =
            '${dir.path}/sanaa_${DateTime.now().millisecondsSinceEpoch}.mp4';
        await File(joined).copy(copy);
        finalPath = copy;
      }

      lastExportPath = finalPath;
      await Gal.putVideo(finalPath);
      _msg('تم التصدير وتخزن الفيديو فالمعرض ✅');

      if (share) {
        await Share.shareXFiles(
          [XFile(finalPath)],
          text: 'صنعة كليب',
        );
      }
    } catch (e) {
      _msg('خطأ: $e');
    } finally {
      if (mounted) {
        setState(() {
          exporting = false;
          exportStatus = '';
        });
      }
    }
  }

  void clearAll() {
    setState(() {
      media.clear();
      subtitles.clear();
      transcribedText = "هنا ستبين الكتابة المترجمة سطر ورا سطر...";
    });
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  Widget _previewContent() {
    if (media.isEmpty) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_collection, size: 72, color: Colors.orangeAccent),
          SizedBox(height: 10),
          Text("أضف صور أو فيديوهات للبدء",
              style: TextStyle(color: Colors.white54)),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: PageView.builder(
        itemCount: media.length,
        itemBuilder: (_, i) {
          final p = media[i].path;
          if (isVideoPath(p)) {
            return VideoTile(key: ValueKey(p), path: p);
          }
          return Image.file(
            File(p),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎬 صنعة كليب'),
        backgroundColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.orange.withOpacity(0.4),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2E2E38), Color(0xFF1A1A20)],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white70),
            onPressed: clearAll,
          ),
          exporting
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.orange),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.save_alt, color: Colors.orange),
                  onPressed: () => exportVideo(),
                ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.2,
            colors: [Color(0xFF26263A), Color(0xFF0E0E12)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateX(-0.07),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF34344A), Color(0xFF16161F)],
                      ),
                      border: Border.all(
                          color: Colors.orange.withOpacity(0.5), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.25),
                          blurRadius: 30,
                          offset: const Offset(0, 16),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.7),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _previewContent(),
                        Positioned(
                          bottom: 20,
                          left: 12,
                          right: 12,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: Text(
                                transcribedText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        if (media.isNotEmpty)
                          Positioned(
                            top: 10,
                            right: 12,
                            child: Chip(
                              label: Text(
                                  '${media.length} 🖼  ${subtitles.length} 💬'),
                              backgroundColor: Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF30303C), Color(0xFF1E1E26)],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("لغة الترجمة:",
                        style: TextStyle(color: Colors.white70)),
                    DropdownButton<String>(
                      value: selectedLanguage,
                      dropdownColor: const Color(0xFF1E1E26),
                      style: const TextStyle(
                          color: Colors.orange, fontWeight: FontWeight.bold),
                      underline: Container(),
                      items: languages.keys.map((String lang) {
                        return DropdownMenuItem<String>(
                          value: lang,
                          child: Text(lang),
                        );
                      }).toList(),
                      onChanged: (String? v) {
                        if (v != null) setState(() => selectedLanguage = v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Button3D(
                      color: const Color(0xFF5B6CFF),
                      onTap: pickMedia,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_photo_alternate, color: Colors.white),
                          SizedBox(width: 8),
                          Text('صور / فيديو',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Button3D(
                      color: isRecording
                          ? const Color(0xFFE53935)
                          : const Color(0xFFFF8F00),
                      onTap: toggleRecording,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isRecording ? Icons.mic : Icons.mic_none,
                              color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            isRecording ? 'إيقاف' : 'تسجيل صوتي',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Button3D(
                color: const Color(0xFF1877F2),
                onTap: () {
                  if (!exporting) exportVideo(share: true);
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.share, color: Colors.white),
                    SizedBox(width: 8),
                    Text('نشر على فيسبوك (Reels)',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              SizedBox(
                height: 28,
                child: Center(
                  child: Text(exportStatus,
                      style: const TextStyle(color: Colors.orange)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
