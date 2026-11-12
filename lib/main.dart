import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:translator/translator.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

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

  @override
  void initState() {
    super.initState();
    _initSpeech();
    FFmpegKitConfig.setFontDirectoryList(["/system/fonts", "/System/Library/Fonts"]);
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> pickImages() async {
    try {
      final files = await _picker.pickMultiImage();
      if (files.isEmpty) return;
      setState(() => media.addAll(files));
    } catch (e) {
      _msg('تعذر فتح المعرض: $e');
    }
  }

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
          "تم! ${subtitles.length} سطر مترجم إلى: $selectedLanguage 🚀");
    }
  }

  Future<void> exportVideo() async {
    if (media.isEmpty) {
      _msg('أضف صور أولا');
      return;
    }
    if (isRecording) await toggleRecording();
    setState(() => exporting = true);

    try {
      final dir = await getTemporaryDirectory();
      final out = '${dir.path}/montage_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final totalSec = subtitles.isEmpty
          ? media.length * 3.0
          : (_lastEnd.inMilliseconds / 1000.0)
              .clamp(media.length * 2.0, 600.0)
              .toDouble();
      final per = (totalSec / media.length).toStringAsFixed(2);

      final list = StringBuffer();
      for (final m in media) {
        list.writeln("file '${m.path.replaceAll("'", r"'\''")}'");
        list.writeln('duration $per');
      }
      list.writeln("file '${media.last.path.replaceAll("'", r"'\''")}'");
      final listFile = File('${dir.path}/list.txt');
      await listFile.writeAsString(list.toString());

      String vf =
          'scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p';
      if (subtitles.isNotEmpty) {
        final srt = StringBuffer();
        for (var i = 0; i < subtitles.length; i++) {
          final s = subtitles[i];
          srt.writeln('${i + 1}');
          srt.writeln('${srtTime(s.start)} --> ${srtTime(s.end)}');
          srt.writeln(s.text);
          srt.writeln();
        }
        final srtFile = File('${dir.path}/subs.srt');
        await srtFile.writeAsString(srt.toString());
        vf += ",subtitles=${srtFile.path}:force_style='FontSize=20,Outline=2,MarginV=60'";
      }

      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-f', 'concat',
        '-safe', '0',
        '-i', listFile.path,
        '-vf', vf,
        '-r', '30',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        out,
      ]);
      final code = await session.getReturnCode();

      if (ReturnCode.isSuccess(code)) {
        await Gal.putVideo(out);
        _msg('تم التصدير وتخزن الفيديو فالمعرض ✅');
      } else {
        _msg('فشل التصدير، جرب مرة أخرى');
      }
    } catch (e) {
      _msg('خطأ: $e');
    } finally {
      if (mounted) setState(() => exporting = false);
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
        itemBuilder: (_, i) => Image.file(
          File(media[i].path),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
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
                  onPressed: exportVideo,
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
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orange.withOpacity(0.4),
                                    blurRadius: 12,
                                  ),
                                ],
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
                              label: Text('${media.length} 🖼  ${subtitles.length} 💬'),
                              backgroundColor: Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF30303C), Color(0xFF1E1E26)],
                  ),
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
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
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Button3D(
                      color: const Color(0xFF5B6CFF),
                      onTap: pickImages,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_photo_alternate, color: Colors.white),
                          SizedBox(width: 8),
                          Text('إضافة صور',
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
                            isRecording ? 'إيقاف التسجيل' : 'تسجيل صوتي',
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
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
