import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/device_load.dart';
import '../../app/preferences.dart';
import '../../domain/plan.dart';
import '../../app/providers.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/app_settings.dart';
import '../../domain/models.dart';
import '../../domain/ocr.dart';
import '../../domain/qr_reader.dart';
import '../../domain/scanner_service.dart';
import '../batch_edit/batch_completion.dart';
import '../batch_edit/batch_review_screen.dart';
import '../capture/photo_import_screen.dart';
import '../export/export_sheet.dart';
import '../pages/scan_controller.dart';
import '../../imaging/book_split.dart';
import 'auto_capture.dart';
import 'batch_camera.dart';
import 'camera_frame.dart';
import 'camera_mode.dart';
import 'capture_settings_screen.dart';
import 'page_identity.dart';

/// Opens the camera. Pages join the current draft as they are taken. When
/// the camera closes with pages taken, the draft opens; [openDraftAfter] is
/// false when the caller is already inside the draft. When camera access is
/// blocked and photo import is picked instead, that runs here.
Future<void> openBatchCapture(BuildContext context, WidgetRef ref, {bool openDraftAfter = true}) async {
  final before = ref.read(scanControllerProvider).pages;
  final exit = await Navigator.of(context).push<Object>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => BatchCaptureScreen(returnToReview: !openDraftAfter)),
  );
  if (!context.mounted) return;
  if (exit == _importPhotosInstead) {
    final added = await importPhotosFlow(context, ref);
    if (added && openDraftAfter && context.mounted) openDraft(context);
    return;
  }
  final taken = !identical(ref.read(scanControllerProvider).pages, before);
  if (openDraftAfter && (taken || exit != null)) openDraft(context);
  if (exit == BatchOutcome.export && context.mounted) await showExportSheet(context);
}

/// What the camera closes with when photo import is picked instead.
const _importPhotosInstead = #importPhotos;

/// The camera (iOS flow prototype, screen 02 "Camera preview"; BE-01;
/// docs/capture-modes-algorithms.md). It stays open between shots: each
/// press of the shutter saves a page to the draft and the camera is ready
/// for the next one straight away, with no preview or "Add page" step in
/// between.
///
/// Over the preview: the guidance chip, camera settings (•••) and the Batch,
/// Flash and Auto capture quick controls, plus the page outline and the
/// guides of the current mode. Below it: the page count, the capture modes
/// (Docs, Book, Text, OCR Doc, QR, Photo), and the thumbnail (opens Captured
/// photos, where a page can be retaken and the batch reviewed), the shutter,
/// and the cross that discards the photos taken in this visit.
class BatchCaptureScreen extends ConsumerStatefulWidget {
  const BatchCaptureScreen({super.key, this.returnToReview = false});

  /// Opened from Batch Review: Review goes back to it instead of opening
  /// another one.
  final bool returnToReview;

  @override
  ConsumerState<BatchCaptureScreen> createState() => _BatchCaptureScreenState();
}

enum _CameraStatus { opening, ready, blocked, failed }

class _BatchCaptureScreenState extends ConsumerState<BatchCaptureScreen> with WidgetsBindingObserver {
  /// Shutter presses made while a photo is being taken run right after it,
  /// up to this many, so quick taps are never lost.
  static const _maxQueuedShots = 2;

  /// One analysed frame at a time, at most this often: about 6 a second
  /// for the page outline, fewer for QR codes.
  static const _pageFrameGap = Duration(milliseconds: 150);
  static const _qrFrameGap = Duration(milliseconds: 250);

  /// The same QR code read twice within this time is accepted
  /// (identicalPayloadCount ≥ 2 within 500 ms).
  static const _qrAgreement = Duration(milliseconds: 500);

  late final BatchCamera _camera = ref.read(batchCameraProvider)();
  late final ScanController _controller = ref.read(scanControllerProvider.notifier);

  /// Whether the draft had no pages when the camera opened. Discarding then
  /// deletes the photo files too; otherwise only this visit's pages leave.
  bool _startedEmpty = true;

  _CameraStatus _status = _CameraStatus.opening;
  bool _blockedPermanently = false;
  String? _failure;

  /// Pages taken in this visit, in order. Retakes keep their place.
  final List<ScanPage> _taken = [];

  /// Photos taken but not yet in the draft.
  int _saving = 0;
  Future<void> _saves = Future.value();
  bool _shooting = false;
  int _queuedShots = 0;

  /// What the text on the last page photo read as, and its pages, so an
  /// automatic photo of the same page again is not kept (US-03.11).
  ({PageIdentity identity, List<String> pageIds})? _lastRead;

  /// Repeat checks queued behind the camera and not yet run.
  int _pendingChecks = 0;

  /// Reading text or a QR code from a photo just taken.
  bool _reading = false;

  /// The page the next shot replaces, while a retake is on.
  String? _retakeId;

  CameraMode _mode = CameraMode.docs;

  /// Batch mode: keep capturing without review. Off, Batch Review opens
  /// after every photo.
  bool _batch = true;
  bool _torch = false;
  bool _autoCapture = true;
  bool _autoCrop = true;
  bool _grid = false;

  /// Coverage of the camera by another screen or a sheet over it, or the
  /// app going to the background.
  bool _covered = false;
  bool _sheetOpen = false;

  /// Bumped on every shot to replay the white capture flash.
  int _flashSerial = 0;

  /// Short confirmation after each shot, such as "Page 4 captured".
  String? _toast;
  int _toastSerial = 0;
  Timer? _toastTimer;

  /// Finds the page in each new photo, one photo at a time, in the background.
  Future<void> _cropIo = Future.value();

  // Live preview analysis.
  final _tracker = AutoCaptureTracker();

  /// The last page outline seen, and when: drawn on for a moment after the
  /// detector loses the page for a frame or two, so the outline does not
  /// flicker, and used to crop a photo the detector finds no page in.
  CropQuad? _seenQuad;
  DateTime _seenAt = DateTime(0);

  /// How long an outline stays drawn after the page was last found.
  static const _outlineHold = Duration(milliseconds: 700);

  /// The page outline to draw: the one in the last frame, or one seen a
  /// moment ago.
  CropQuad? get _outline =>
      _tracker.quad ?? (_smart && DateTime.now().difference(_seenAt) <= _outlineHold ? _seenQuad : null);

  /// Smart scanning (drift following, quick next page, repeat check, outline
  /// hold, fallback crop) is a Pro feature.
  bool get _smart => ref.read(planIncludesProvider(PlanFeature.smartScan));
  bool _analysing = false;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  FrameAnalysis _frame = const FrameAnalysis();
  QrResult? _qrSeen;
  DateTime _qrSeenAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Last QR code shown, so the same code is not offered again and again
  /// while it stays in view.
  String? _qrShown;

  AppSettings get _settings => ref.read(appSettingsProvider);

  /// Kept for background work on pages that finishes after the camera
  /// closes.
  late final ProviderContainer _container = ProviderScope.containerOf(context, listen: false);

  @override
  void initState() {
    super.initState();
    _startedEmpty = ref.read(scanControllerProvider).pages.isEmpty;
    _container;
    _tracker.stableFrames = _settings.autoCaptureSteadiness.frames;
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _toastTimer?.cancel();
    unawaited(_camera.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_status != _CameraStatus.ready) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      unawaited(_camera.pause());
    } else if (state == AppLifecycleState.resumed && !_covered) {
      _resume();
    }
  }

  Future<void> _open() async {
    setState(() {
      _status = _CameraStatus.opening;
      _failure = null;
    });
    try {
      await _camera.open(resolution: _settings.captureResolution);
      if (_torch) await _camera.setTorch(true);
      await _camera.startFrames(_onFrame);
      if (mounted) setState(() => _status = _CameraStatus.ready);
    } on ScannerPermissionDenied catch (e) {
      if (mounted) {
        setState(() {
          _status = _CameraStatus.blocked;
          _blockedPermanently = e.permanently;
        });
      }
    } on ScannerFailure catch (e) {
      if (mounted) {
        setState(() {
          _status = _CameraStatus.failed;
          _failure = e.message;
        });
      }
    }
  }

  Future<void> _resume() async {
    try {
      await _camera.resume();
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _status = _CameraStatus.failed;
          _failure = e is ScannerFailure ? e.message : '$e';
        });
      }
      return;
    }
    if (mounted) setState(() {});
  }

  // ---- Live preview analysis -------------------------------------------

  bool get _watchesPages => _mode.findsPage;

  /// Called for every preview frame. Drops the frame unless nothing else is
  /// being analysed and enough time has passed, so analysis never falls
  /// behind the preview (one frame in flight).
  void _onFrame(CameraFrame frame) {
    if (!mounted || _analysing || _covered || _sheetOpen || _reading) return;
    if (!_watchesPages && _mode != CameraMode.qr) return;
    final now = DateTime.now();
    if (now.difference(_lastAnalysis) < (_mode == CameraMode.qr ? _qrFrameGap : _pageFrameGap)) return;
    _lastAnalysis = now;
    _analysing = true;
    unawaited(_analyse(frame).whenComplete(() => _analysing = false));
  }

  Future<void> _analyse(CameraFrame frame) async {
    final mode = _mode;
    try {
      if (mode == CameraMode.qr) {
        final code = await ref.read(qrReaderProvider).readFrame(frame);
        if (mounted && _mode == mode) _seeQr(code);
        return;
      }
      final analysis = await ref.read(frameAnalyzerProvider)(frame);
      if (!mounted || _mode != mode) return;
      final dark = analysis.tooDark;
      _tracker.smart = _smart;
      final shoot = _tracker.add(dark ? null : analysis.quad, dark ? null : analysis.signature, analysis.scene);
      if (!dark && analysis.quad != null) {
        _seenQuad = analysis.quad;
        _seenAt = DateTime.now();
      }
      setState(() => _frame = analysis);
      if (shoot && _autoCapture && mode.canAutoCapture && !_shooting && _retakeId == null) {
        unawaited(_shoot(auto: true));
      }
    } catch (e) {
      debugPrint('Preview analysis failed: $e');
    }
  }

  /// Accepts a QR code once it has been read twice within [_qrAgreement].
  void _seeQr(QrResult? code) {
    final now = DateTime.now();
    if (code == null) {
      if (now.difference(_qrSeenAt) > const Duration(seconds: 2)) _qrShown = null;
      return;
    }
    final agreed = _qrSeen?.raw == code.raw && now.difference(_qrSeenAt) <= _qrAgreement;
    _qrSeen = code;
    _qrSeenAt = now;
    setState(() {});
    if (agreed && code.raw != _qrShown) {
      _qrShown = code.raw;
      unawaited(_showQr(code));
    }
  }

  // ---- Taking photos ---------------------------------------------------

  void _feedback() {
    if (_settings.captureHaptics) unawaited(HapticFeedback.lightImpact());
    if (_settings.shutterSound) unawaited(SystemSound.play(SystemSoundType.click));
  }

  /// Takes a photo. [auto] when auto capture took it, not the shutter: then
  /// a photo of the page taken just before is dropped once its text is read.
  Future<void> _shoot({bool auto = false}) async {
    if (_status != _CameraStatus.ready || _covered || _reading || !_camera.isReady) return;
    if (_shooting) {
      if (_batch && _mode.addsPages && _queuedShots < _maxQueuedShots) _queuedShots++;
      return;
    }
    final replacing = _retakeId;
    final mode = _mode;
    final seen = mode.findsPage && _smart ? _outline : null;
    // Whether tapped or automatic, this page is taken: auto capture now
    // waits for a different page instead of taking the same one again.
    if (mode.findsPage) _tracker.captured();
    setState(() {
      _shooting = true;
      _flashSerial++;
    });
    try {
      final path = await _camera.takePicture();
      _feedback();
      if (!mounted) return;
      if (!mode.addsPages) {
        unawaited(mode == CameraMode.text ? _readText(path) : _readQrPhoto(path));
        return;
      }
      setState(() {
        _saving++;
        if (replacing != null) _retakeId = null;
      });
      final saved = _save(path, replacing, mode, auto: auto, seen: seen);
      _saves = _saves.then((_) => saved);
      if (!_batch) unawaited(saved.then((page) => page != null && mounted ? _review() : null));
    } on ScannerFailure catch (e) {
      _queuedShots = 0;
      if (mounted) _showToast('Photo not taken: ${e.message}');
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
    if (_queuedShots > 0 && mounted) {
      _queuedShots--;
      unawaited(_shoot());
    }
  }

  /// [seen] is the page outline on the preview when the photo was taken.
  Future<ScanPage?> _save(String path, String? replacing, CameraMode mode, {bool auto = false, CropQuad? seen}) async {
    final List<ScanPage>? pages;
    // Book mode makes two pages only when both are in view; held over one
    // page, with the other cut off, it makes just that page.
    if (mode == CameraMode.book && showsSpread(_frame.quad)) {
      pages = await _controller.addCaptureSplit(path, const [leftHalf, rightHalf], replacing: replacing);
    } else {
      final page = await _controller.addCapture(path, replacing: replacing, plain: mode == CameraMode.photo);
      pages = page == null ? null : [page];
    }
    if (!mounted) {
      if (pages != null) _afterCapture(pages, mode, auto: auto, retake: replacing != null, seen: seen);
      return pages?.first;
    }
    setState(() {
      _saving--;
      if (pages == null) return;
      final at = replacing == null ? -1 : _taken.indexWhere((p) => p.id == replacing);
      if (at >= 0) {
        _taken.replaceRange(at, at + 1, pages);
      } else if (replacing == null) {
        _taken.addAll(pages);
      }
    });
    if (pages == null) {
      _showToast('That photo could not be saved. Take it again.');
      return null;
    }
    final all = ref.read(scanControllerProvider).pages;
    final first = all.indexWhere((p) => p.id == pages!.first.id) + 1;
    _showToast(switch (mode) {
      _ when pages.length == 2 => 'Pages $first and ${first + 1} captured',
      _ when replacing != null => 'Page $first replaced',
      _ => 'Page $first captured',
    });
    _afterCapture(pages, mode, auto: auto, retake: replacing != null, seen: seen);
    return pages.first;
  }

  /// Background work on new pages, one photo at a time: the page outline
  /// (Docs, OCR Doc), the spine (Book), the text (OCR Doc), then, with auto
  /// capture on, whether the photo shows the same page as the one before.
  ///
  /// With auto crop on, every page photo is cropped: to the page found in
  /// the photo, or when none is found there, to the outline [seen] on the
  /// preview as it was taken. The crop can still be adjusted afterwards.
  void _afterCapture(List<ScanPage> pages, CameraMode mode, {bool auto = false, bool retake = false, CropQuad? seen}) {
    final container = _container;
    final analyzer = container.read(photoAnalyzerProvider);
    final splitter = container.read(spreadSplitterProvider);
    final ocr = container.read(ocrEngineProvider);
    final controller = _controller;
    final autoCrop = _autoCrop;
    final checkRepeat = _smart && _autoCapture && mode.canAutoCapture && !retake;
    if (checkRepeat) _pendingChecks++;
    _cropIo = _cropIo.then((_) async {
      try {
        if (mode == CameraMode.book && autoCrop && pages.length == 2) {
          final (left, right) = await splitter(pages.first.originalPath);
          controller.applyDetectedCrop(pages[0].id, left, expected: leftHalf);
          controller.applyDetectedCrop(pages[1].id, right, expected: rightHalf);
        } else if (mode.findsPage && autoCrop) {
          CropQuad? found;
          try {
            found = await analyzer.analyze(pages.first.originalPath);
          } catch (e) {
            debugPrint('Page detection failed: $e');
          }
          final quad = found ?? seen;
          if (quad != null) controller.applyDetectedCrop(pages.first.id, quad);
        }
      } catch (e) {
        debugPrint('Page detection failed: $e');
      }
      if (checkRepeat) {
        try {
          await _checkRepeat(pages, ocr, controller, container, auto: auto);
        } finally {
          _pendingChecks--;
        }
      }
      if (mode != CameraMode.ocrDoc) return;
      for (final page in pages) {
        if (container.read(scanControllerProvider).pageById(page.id) == null) continue;
        try {
          final current = container.read(scanControllerProvider).pageById(page.id);
          if (current == null) continue;
          final text = await ocr.recognize(current, languageCode: 'en');
          controller.setPageText(page.id, text);
          if (mounted && text.trim().isNotEmpty) {
            final n = container.read(scanControllerProvider).pages.indexWhere((p) => p.id == page.id) + 1;
            _showToast('Text read on page $n');
          }
        } catch (e) {
          debugPrint('Text recognition failed: $e');
        }
      }
    });
  }

  /// Reads the text on a new photo and compares it with the photo before:
  /// the page number, then the first and last lines and the words. A photo
  /// auto capture took of that same page again, because it was held in
  /// view too long, is removed. Shutter photos are always kept.
  Future<void> _checkRepeat(
    List<ScanPage> pages,
    OcrEngine ocr,
    ScanController controller,
    ProviderContainer container, {
    required bool auto,
  }) async {
    // Reading text is heavy. When the phone is short of memory or CPU, or
    // reads are piling up behind a fast batch, the check is skipped so the
    // camera stays quick; the page is kept.
    final load = await container.read(deviceLoadProbeProvider).sample();
    if (!affordsTextCheck(load, pending: _pendingChecks - 1)) {
      debugPrint('Repeat check skipped: $load, ${_pendingChecks - 1} waiting');
      _lastRead = null;
      return;
    }
    PageIdentity? identity;
    try {
      identity = PageIdentity.fromText(await ocr.recognizeFile(pages.first.originalPath));
    } catch (e) {
      debugPrint('Repeat check could not read the page: $e');
    }
    final before = _lastRead;
    if (identity == null) {
      // Nothing to compare with: neither this photo nor the one before can
      // be told apart from the next.
      _lastRead = null;
      return;
    }
    final draft = container.read(scanControllerProvider);
    final kept = before != null && before.pageIds.any((id) => draft.pageById(id) != null);
    if (auto && kept && identity.samePageAs(before.identity)) {
      final ids = {for (final p in pages) p.id};
      controller.removePages(ids);
      final n = draft.pages.indexWhere((p) => p.id == before.pageIds.first) + 1;
      if (!mounted) return;
      setState(() => _taken.removeWhere((p) => ids.contains(p.id)));
      _showToast(n > 0 ? 'Same page as page $n, not kept' : 'Same page again, not kept');
      return;
    }
    _lastRead = (identity: identity, pageIds: [for (final p in pages) p.id]);
  }

  /// Text mode: reads the photo and offers the text. The photo is kept only
  /// when it is added as a page.
  Future<void> _readText(String path) async {
    setState(() => _reading = true);
    String? text;
    String? problem;
    try {
      text = await ref.read(ocrEngineProvider).recognizeFile(path);
    } catch (e) {
      problem = 'Text could not be read on this device.';
      debugPrint('Text recognition failed: $e');
    }
    if (!mounted) return;
    setState(() => _reading = false);
    if (text == null || text.trim().isEmpty) {
      _deleteQuietly(path);
      _showToast(problem ?? 'No text found. Move closer or add light.');
      return;
    }
    final addPage = await _withSheet(
      () => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _TextResultSheet(text: text!),
      ),
    );
    if (!mounted) return;
    if (addPage == true) {
      setState(() => _saving++);
      final saved = _save(path, null, CameraMode.docs);
      _saves = _saves.then((_) => saved);
    } else {
      _deleteQuietly(path);
    }
  }

  /// QR mode, shutter: reads a QR code from the photo, which is not kept.
  Future<void> _readQrPhoto(String path) async {
    setState(() => _reading = true);
    QrResult? code;
    try {
      code = await ref.read(qrReaderProvider).readFile(path);
    } catch (e) {
      debugPrint('QR reading failed: $e');
    }
    _deleteQuietly(path);
    if (!mounted) return;
    setState(() => _reading = false);
    if (code == null) {
      _showToast('No QR code found. Move closer, hold steady or add light.');
      return;
    }
    _qrShown = code.raw;
    await _showQr(code);
  }

  Future<void> _showQr(QrResult code) async {
    if (_sheetOpen) return;
    unawaited(HapticFeedback.selectionClick());
    await _withSheet(
      () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _QrResultSheet(code: code),
      ),
    );
  }

  /// Runs a sheet over the camera, with preview analysis paused meanwhile.
  Future<T?> _withSheet<T>(Future<T?> Function() show) async {
    setState(() => _sheetOpen = true);
    try {
      return await show();
    } finally {
      if (mounted) setState(() => _sheetOpen = false);
    }
  }

  static void _deleteQuietly(String path) {
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // The camera's own cache folder is cleared by the OS.
    }
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() {
      _toast = message;
      _toastSerial++;
    });
    _toastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // ---- Controls --------------------------------------------------------

  void _retake(String pageId) => setState(() => _retakeId = pageId);

  void _cancelRetake() => setState(() => _retakeId = null);

  void _setMode(CameraMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _frame = const FrameAnalysis();
      _qrSeen = null;
      _qrShown = null;
      if (!mode.addsPages) _retakeId = null;
    });
    _tracker.reset();
    _seenQuad = null;
    if (mode == CameraMode.text || mode == CameraMode.ocrDoc) unawaited(_checkOcr());
  }

  /// Says once, on picking a text mode, when text cannot be read here.
  Future<void> _checkOcr() async {
    final capability = await ref.read(ocrEngineProvider).capability('en');
    if (!mounted || capability.readiness == OcrReadiness.ready) return;
    _showToast(
      _mode == CameraMode.ocrDoc
          ? 'Pages are kept; text will not be read: ${capability.reason ?? 'text recognition is unavailable'}'
          : capability.reason ?? 'Text recognition is not available.',
    );
  }

  Future<void> _setTorch(bool on) async {
    if (!_camera.hasTorch || _status != _CameraStatus.ready) return;
    setState(() => _torch = on);
    await _camera.setTorch(on);
  }

  void _setOption(_Option option, bool on) {
    switch (option) {
      case _Option.batch:
        setState(() => _batch = on);
      case _Option.flash:
        unawaited(_setTorch(on));
      case _Option.auto:
        setState(() => _autoCapture = on);
        _tracker.reset();
        _seenQuad = null;
      case _Option.crop:
        setState(() => _autoCrop = on);
      case _Option.grid:
        setState(() => _grid = on);
    }
  }

  bool _option(_Option option) => switch (option) {
    _Option.batch => _batch,
    _Option.flash => _torch,
    _Option.auto => _autoCapture,
    _Option.crop => _autoCrop,
    _Option.grid => _grid,
  };

  Future<void> _openSettings() async {
    final more = await _withSheet(
      () => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => StatefulBuilder(
          builder: (sheetContext, setSheet) => _SettingsSheet(
            value: _option,
            flashAvailable: _status == _CameraStatus.ready && _camera.hasTorch,
            onChanged: (option, on) {
              _setOption(option, on);
              setSheet(() {});
            },
          ),
        ),
      ),
    );
    if (more == true && mounted) await _openMoreSettings();
  }

  /// More capture settings, over the camera. A new photo size restarts the
  /// camera on return.
  Future<void> _openMoreSettings() async {
    setState(() => _covered = true);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CaptureSettingsScreen()));
    if (!mounted) return;
    _tracker.stableFrames = _settings.autoCaptureSteadiness.frames;
    try {
      await _camera.setResolution(_settings.captureResolution);
    } on ScannerFailure catch (e) {
      if (mounted) _showToast('Photo size not changed: ${e.message}');
    }
    if (mounted) setState(() => _covered = false);
  }

  /// Captured photos: every page so far, numbered. Tapping one retakes it.
  Future<void> _openPhotos() async {
    final choice = await _withSheet(
      () => showModalBottomSheet<_PhotosChoice>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const _CapturedPhotosSheet(),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.review) {
      await _review();
    } else if (choice.retakeId != null) {
      if (!_mode.addsPages) _setMode(CameraMode.docs);
      _retake(choice.retakeId!);
    }
  }

  /// Batch Review over the camera. The camera is released while it is open
  /// and taken back on return, unless the user finished there.
  Future<void> _review() async {
    if (_covered) return;
    if (widget.returnToReview) return _finish();
    if (ref.read(scanControllerProvider).pages.isEmpty) return;
    setState(() {
      _covered = true;
      _retakeId = null;
    });
    await _camera.pause();
    if (!mounted) return;
    final outcome = await Navigator.of(context)
        .push<BatchOutcome>(MaterialPageRoute(builder: (_) => const BatchReviewScreen(fromCamera: true)));
    if (!mounted) return;
    if (outcome == BatchOutcome.review || outcome == BatchOutcome.export) {
      Navigator.of(context).pop(outcome);
      return;
    }
    _covered = false;
    _tracker.reset();
    _seenQuad = null;
    // Pages deleted in Batch Review leave this visit's list too.
    final ids = {for (final p in ref.read(scanControllerProvider).pages) p.id};
    _taken.removeWhere((p) => !ids.contains(p.id));
    await _resume();
  }

  /// Leaves keeping every photo.
  void _finish() => Navigator.of(context).pop(_taken.isEmpty ? null : BatchOutcome.review);

  /// The cross: leaves, and when photos were taken in this visit, asks
  /// first and then removes them.
  Future<void> _discard() async {
    if (_taken.isEmpty && _saving == 0) {
      Navigator.of(context).pop();
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => _DiscardDialog(count: _taken.length),
    );
    if (sure != true || !mounted) return;
    setState(() => _covered = true);
    await _saves;
    if (_startedEmpty) {
      await _controller.clear();
    } else {
      _controller.removePages({for (final p in _taken) p.id});
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _permissionHelp() async {
    if (_blockedPermanently) {
      await openAppSettings();
      return;
    }
    await _open();
  }

  String get _guidance {
    if (_status != _CameraStatus.ready) return 'Starting camera';
    if (_reading) return _mode == CameraMode.qr ? 'Reading the QR code' : 'Reading the text';
    if (_mode == CameraMode.qr) return _qrSeen != null ? 'QR code found' : _mode.guidance;
    if (_watchesPages && _frame.tooDark) return 'More light needed';
    if (_autoCapture && _mode.canAutoCapture) return _tracker.state.label;
    return _mode.guidance;
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(scanControllerProvider.select((s) => s.pages));
    final last = _taken.isEmpty ? (pages.isEmpty ? null : pages.last) : _taken.last;
    final retakeNumber = _retakeId == null ? 0 : pages.indexWhere((p) => p.id == _retakeId) + 1;
    final ready = _status == _CameraStatus.ready;
    final autoRunning = ready && _autoCapture && _mode.canAutoCapture;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_discard());
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _preview(),
                    if (ready) IgnorePointer(child: _CaptureFlash(serial: _flashSerial)),
                    if (_reading) const Center(child: CircularProgressIndicator(color: Colors.white)),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const SizedBox(width: 48),
                                Expanded(
                                  child: Center(
                                    child: _retakeId != null ? const SizedBox.shrink() : _Chip(text: _guidance),
                                  ),
                                ),
                                _RoundButton(
                                  tooltip: 'Camera settings',
                                  icon: Icons.more_horiz,
                                  onPressed: _openSettings,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _QuickToggle(
                                    icon: Icons.burst_mode_outlined,
                                    title: 'Batch',
                                    on: _batch,
                                    onChanged: (on) => _setOption(_Option.batch, on),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _QuickToggle(
                                    icon: _torch ? Icons.flash_on : Icons.flash_off,
                                    title: 'Flash',
                                    on: _torch,
                                    onChanged: ready && _camera.hasTorch ? (on) => _setOption(_Option.flash, on) : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _QuickToggle(
                                    icon: Icons.motion_photos_auto_outlined,
                                    title: 'Auto',
                                    on: _autoCapture,
                                    onChanged: (on) => _setOption(_Option.auto, on),
                                  ),
                                ),
                              ],
                            ),
                            if (_retakeId != null) ...[
                              const SizedBox(height: 10),
                              _Banner(
                                icon: Icons.replay,
                                text: 'Retaking page $retakeNumber. Take the new photo.',
                                action: 'Cancel',
                                onAction: _cancelRetake,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: _toast == null
                              ? const SizedBox.shrink()
                              : _Toast(key: ValueKey(_toastSerial), text: _toast!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _ControlPanel(
                count: pages.length,
                showCount: _batch && _mode.addsPages,
                lastPage: last,
                saving: _saving > 0,
                shooting: _shooting || _reading,
                canShoot: ready && !_covered && !_reading,
                retaking: _retakeId != null,
                shutterLabel: _retakeId != null ? 'Take the new photo' : _mode.shutterLabel,
                autoProgress: autoRunning ? _tracker.progress : null,
                mode: _mode,
                onMode: _setMode,
                onShoot: _shoot,
                onPhotos: _openPhotos,
                onDiscard: _discard,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview() => switch (_status) {
    _CameraStatus.opening => const Center(child: CircularProgressIndicator(color: Colors.white)),
    _CameraStatus.ready =>
      _covered || !_camera.isReady
          ? const SizedBox.expand()
          : ClipRect(
              child: Center(
                child: _camera.buildPreview(
                  overlay: IgnorePointer(
                    child: _PreviewOverlay(
                      mode: _mode,
                      quad: _watchesPages ? _outline : null,
                      steady: _tracker.state == AutoCaptureState.capture,
                      qrFound: _mode == CameraMode.qr && _qrSeen != null,
                      grid: _grid,
                    ),
                  ),
                ),
              ),
            ),
    _CameraStatus.blocked => _CameraMessage(
      icon: Icons.no_photography_outlined,
      title: 'Camera access needed',
      body: _blockedPermanently
          ? 'Camera access is turned off. Turn it on in Settings to scan pages. Pages stay on this device.'
          : 'Allow camera access to scan pages. Pages stay on this device.',
      action: _blockedPermanently ? 'Open Settings' : 'Try again',
      onAction: _permissionHelp,
      secondary: 'Import photos',
      onSecondary: () => Navigator.of(context).pop(_importPhotosInstead),
    ),
    _CameraStatus.failed => _CameraMessage(
      icon: Icons.error_outline,
      title: 'The camera could not start',
      body: _failure ?? 'Try again.',
      action: 'Try again',
      onAction: _open,
    ),
  };
}

enum _Option { batch, flash, auto, crop, grid }

/// What was picked in Captured photos.
class _PhotosChoice {
  const _PhotosChoice.review() : review = true, retakeId = null;
  const _PhotosChoice.retake(String this.retakeId) : review = false;

  final bool review;
  final String? retakeId;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.72),
        foregroundColor: Colors.white,
        fixedSize: const Size(48, 48),
      ),
      icon: Icon(icon),
    );
  }
}

/// One of the Batch, Flash and Auto crop chips over the preview. They stay
/// in step with the same switches in Camera settings.
class _QuickToggle extends StatelessWidget {
  const _QuickToggle({required this.icon, required this.title, required this.on, required this.onChanged});

  final IconData icon;
  final String title;
  final bool on;

  /// Null when the control is not available, such as Flash without a torch.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.dark;
    final enabled = onChanged != null;
    final state = !enabled ? 'Not available' : (on ? 'On' : 'Off');
    return Semantics(
      button: true,
      toggled: on,
      enabled: enabled,
      label: '$title $state',
      excludeSemantics: true,
      child: Material(
        color: on && enabled ? colors.accent.withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.62),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: on && enabled ? colors.accent : Colors.white24),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => onChanged!(!on) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: enabled ? Colors.white : Colors.white38),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: enabled ? Colors.white : Colors.white38,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        enabled ? state : 'N/A',
                        style: TextStyle(color: enabled ? Colors.white70 : Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.dark;
    return Semantics(
      liveRegion: true,
      label: '$count page${count == 1 ? '' : 's'} captured',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(color: const Color(0xFF3C4648), borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Container(
                key: ValueKey(count),
                constraints: const BoxConstraints(minWidth: 26),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onAccent, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'pages captured',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The latest page, with the page count. Drawn from a small decode of the
/// photo, so it appears straight after the shot.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.page, required this.count, required this.saving});

  final ScanPage? page;
  final int count;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: page == null
                  ? Icon(Icons.description_outlined, color: colors.muted)
                  : Image.file(
                      File(page!.originalPath),
                      key: ValueKey(page!.id),
                      fit: BoxFit.cover,
                      cacheWidth: (52 * dpr).round(),
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => Icon(Icons.description_outlined, color: colors.muted),
                    ),
            ),
          ),
          if (saving)
            Positioned.fill(
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.accent),
                ),
              ),
            ),
          if (count > 0)
            Positioned(
              bottom: -6,
              right: -6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: LumaColors.dark.accent,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: LumaColors.dark.onAccent, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The white flash over the preview when a photo is taken.
class _CaptureFlash extends StatelessWidget {
  const _CaptureFlash({required this.serial});

  final int serial;

  @override
  Widget build(BuildContext context) {
    if (serial == 0 || MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      key: ValueKey(serial),
      tween: Tween(begin: 0.6, end: 0),
      duration: const Duration(milliseconds: 220),
      builder: (_, value, _) => ColoredBox(color: Colors.white.withValues(alpha: value)),
    );
  }
}

/// The 3 × 3 alignment grid.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

class _Toast extends StatelessWidget {
  const _Toast({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 18, color: LumaColors.dark.success),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.action, required this.onAction});

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.dark;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(color: colors.warning, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.black87),
              onPressed: onAction,
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    this.secondary,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white70),
            const SizedBox(height: Space.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Space.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: Space.lg),
            FilledButton(onPressed: onAction, child: Text(action)),
            if (secondary != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: onSecondary,
                child: Text(secondary!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Count, capture modes, then thumbnail, shutter and discard, as in the
/// prototype. The shutter stays enabled while the previous page is saved,
/// so pages can be taken back to back.
class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.count,
    required this.showCount,
    required this.lastPage,
    required this.saving,
    required this.shooting,
    required this.canShoot,
    required this.retaking,
    required this.shutterLabel,
    required this.autoProgress,
    required this.mode,
    required this.onMode,
    required this.onShoot,
    required this.onPhotos,
    required this.onDiscard,
  });

  final int count;
  final bool showCount;
  final ScanPage? lastPage;
  final bool saving;
  final bool shooting;
  final bool canShoot;
  final bool retaking;
  final String shutterLabel;

  /// How steady the page is while auto capture runs; null when it does not.
  final double? autoProgress;
  final CameraMode mode;
  final ValueChanged<CameraMode> onMode;
  final VoidCallback onShoot;
  final VoidCallback onPhotos;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  opacity: showCount ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: _CountPill(count: count),
                ),
              ),
              const SizedBox(height: 10),
              _ModeStrip(mode: mode, onMode: onMode),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        button: true,
                        label: count == 0
                            ? 'No captured photos yet'
                            : 'Open preview of $count captured photo${count == 1 ? '' : 's'}',
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onPhotos,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: _Thumbnail(page: lastPage, count: count, saving: saving),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _Shutter(
                    canShoot: canShoot,
                    shooting: shooting,
                    retaking: retaking,
                    label: shutterLabel,
                    progress: autoProgress,
                    onShoot: onShoot,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Semantics(
                        button: true,
                        label: 'Discard all captured photos and changes',
                        excludeSemantics: true,
                        child: IconButton(
                          onPressed: onDiscard,
                          style: IconButton.styleFrom(
                            backgroundColor: colors.danger,
                            foregroundColor: Colors.white,
                            fixedSize: const Size(56, 56),
                          ),
                          icon: const Icon(Icons.close, size: 28),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Docs, Book, Text, OCR Doc, QR and Photo, scrolling sideways when they do
/// not fit.
class _ModeStrip extends StatelessWidget {
  const _ModeStrip({required this.mode, required this.onMode});

  final CameraMode mode;
  final ValueChanged<CameraMode> onMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFF3C4648), borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final m in CameraMode.values)
              Semantics(
                button: true,
                selected: m == mode,
                label: '${m.label} capture mode',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => onMode(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    constraints: const BoxConstraints(minHeight: 36),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: m == mode ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      m.label,
                      style: TextStyle(
                        color: m == mode ? Colors.black : Colors.white,
                        fontWeight: m == mode ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({
    required this.canShoot,
    required this.shooting,
    required this.retaking,
    required this.label,
    required this.progress,
    required this.onShoot,
  });

  final bool canShoot;
  final bool shooting;
  final bool retaking;
  final String label;

  /// Fills the ring around the shutter as the page holds still.
  final double? progress;
  final VoidCallback onShoot;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return Semantics(
      button: true,
      enabled: canShoot,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: canShoot ? onShoot : null,
        child: SizedBox.square(
          dimension: 86,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (progress != null)
                SizedBox.square(
                  dimension: 86,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    color: LumaColors.dark.accent,
                    backgroundColor: colors.line,
                  ),
                ),
              AnimatedScale(
                scale: shooting ? 0.86 : 1,
                duration: const Duration(milliseconds: 90),
                child: Container(
                  width: 74,
                  height: 74,
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: retaking ? colors.warning : Colors.white,
                      border: Border.all(color: canShoot ? colors.ink : colors.line, width: 3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drawn over exactly the preview: the page found (teal outline with corner
/// dots, as in the prototype), the guides of the mode, and the grid.
class _PreviewOverlay extends StatelessWidget {
  const _PreviewOverlay({
    required this.mode,
    required this.quad,
    required this.steady,
    required this.qrFound,
    required this.grid,
  });

  final CameraMode mode;
  final CropQuad? quad;
  final bool steady;
  final bool qrFound;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final accent = LumaColors.dark.accent;
    const label = TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1);
    BoxDecoration tag(Color color) => BoxDecoration(color: color, borderRadius: BorderRadius.circular(8));
    return Stack(
      fit: StackFit.expand,
      children: [
        if (grid) const CustomPaint(painter: _GridPainter()),
        if (quad != null)
          CustomPaint(
            key: const ValueKey('page-outline'),
            painter: _QuadPainter(quad!, color: accent, steady: steady),
          ),
        if (mode == CameraMode.book && showsSpread(quad)) ...[
          Center(child: Container(width: 2, color: Colors.white70)),
          Align(
            alignment: const Alignment(-0.5, 0.75),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: tag(Colors.black54),
              child: const Text('LEFT PAGE', style: label),
            ),
          ),
          Align(
            alignment: const Alignment(0.5, 0.75),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: tag(Colors.black54),
              child: const Text('RIGHT PAGE', style: label),
            ),
          ),
        ],
        if (mode == CameraMode.text)
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.8,
              heightFactor: 0.4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: accent, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: tag(accent),
                    child: const Text('TEXT', style: label),
                  ),
                ),
              ),
            ),
          ),
        if (mode == CameraMode.ocrDoc)
          Align(
            alignment: const Alignment(0, 0.85),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: tag(Colors.black54),
              child: const Text('OCR · IMAGE + SEARCHABLE TEXT', style: label),
            ),
          ),
        if (mode == CameraMode.qr)
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.6,
              child: AspectRatio(
                aspectRatio: 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    border: Border.all(color: qrFound ? accent : Colors.white, width: qrFound ? 4 : 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: qrFound
                      ? Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: tag(accent),
                            child: const Text('QR DETECTED', style: label),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _QuadPainter extends CustomPainter {
  const _QuadPainter(this.quad, {required this.color, required this.steady});

  final CropQuad quad;
  final Color color;
  final bool steady;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [for (final p in quad.points) Offset(p.x * size.width, p.y * size.height)];
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: steady ? 0.28 : 0.14));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = steady ? 4 : 3,
    );
    for (final p in points) {
      canvas.drawCircle(p, 9, Paint()..color = Colors.white);
      canvas.drawCircle(p, 6, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) => old.quad != quad || old.steady != steady || old.color != color;
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.value, required this.flashAvailable, required this.onChanged});

  final bool Function(_Option) value;
  final bool flashAvailable;
  final void Function(_Option, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    Widget icon(IconData icon) => Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: colors.accentSoft, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: colors.accent),
    );
    Widget row(_Option option, IconData i, String title, String subtitle, {bool enabled = true}) => SwitchListTile(
      value: value(option),
      onChanged: enabled ? (on) => onChanged(option, on) : null,
      secondary: icon(i),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
    );
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Camera settings', style: Theme.of(context).textTheme.titleLarge),
                        Text('Capture options only', style: TextStyle(color: colors.muted)),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            row(_Option.batch, Icons.burst_mode_outlined, 'Batch mode', 'Keep capturing without review'),
            row(
              _Option.flash,
              Icons.flash_on,
              'Flashlight',
              flashAvailable ? 'Continuous light while scanning' : 'Not available on this camera',
              enabled: flashAvailable,
            ),
            row(_Option.auto, Icons.motion_photos_auto_outlined, 'Auto capture', 'Capture when edges are stable'),
            row(_Option.crop, Icons.crop_free, 'Auto crop', 'Find the page edges in each photo'),
            row(_Option.grid, Icons.grid_3x3, 'Alignment grid', 'Show a 3 × 3 guide'),
            ListTile(
              leading: icon(Icons.tune),
              title: const Text('More capture settings', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Resolution, shutter sound, save original'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Captured photos: every page so far, numbered, with Review all and
/// Continue scanning. Tapping a page retakes it. When text was read from
/// pages (OCR Doc), it can be copied from here.
class _CapturedPhotosSheet extends ConsumerWidget {
  const _CapturedPhotosSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(scanControllerProvider.select((s) => s.pages));
    final colors = LumaColors.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final count = pages.length;
    final text = [
      for (final p in pages)
        if (p.text != null && p.text!.trim().isNotEmpty) p.text!.trim(),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Captured photos', style: Theme.of(context).textTheme.titleLarge),
                        Text(
                          count == 0
                              ? 'No captured photos yet'
                              : '$count page${count == 1 ? '' : 's'} in this scan · tap one to retake it',
                          style: TextStyle(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close captured photos',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (count > 0)
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: count,
                  itemBuilder: (context, i) {
                    final page = pages[i];
                    return Semantics(
                      button: true,
                      label: 'Retake page ${i + 1}',
                      excludeSemantics: true,
                      child: Material(
                        color: colors.surfaceRaised,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, _PhotosChoice.retake(page.id)),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Image.file(
                                  File(page.originalPath),
                                  fit: BoxFit.contain,
                                  cacheWidth: (110 * dpr).round(),
                                  errorBuilder: (_, _, _) => Icon(Icons.description_outlined, color: colors.muted),
                                ),
                              ),
                              if (page.text != null && page.text!.trim().isNotEmpty)
                                Positioned(
                                  left: 8,
                                  bottom: 8,
                                  child: Icon(Icons.text_snippet_outlined, size: 18, color: colors.accent),
                                ),
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(color: colors.ink, borderRadius: BorderRadius.circular(6)),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(color: colors.surface, fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextButton.icon(
                  icon: const Icon(Icons.copy),
                  label: Text('Copy text of ${text.length} page${text.length == 1 ? '' : 's'}'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text.join('\n\n')));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Text copied')));
                    }
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: FilledButton(
                onPressed: count == 0 ? null : () => Navigator.pop(context, const _PhotosChoice.review()),
                child: Text(count == 0 ? 'Review all pages' : 'Review all $count page${count == 1 ? '' : 's'}'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Continue scanning')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text mode result: the text read, line by line. Tapping a line copies it;
/// links, email addresses and phone numbers open only when tapped and
/// confirmed. Pops true when the photo should be added as a page.
class _TextResultSheet extends StatelessWidget {
  const _TextResultSheet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    final lines = [
      for (final l in text.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    Future<void> copy(String value, String what) async {
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what copied')));
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recognized text', style: Theme.of(context).textTheme.titleLarge),
                        Text(
                          '${lines.length} line${lines.length == 1 ? '' : 's'} · tap a line to copy it',
                          style: TextStyle(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: lines.length,
                itemBuilder: (context, i) {
                  final line = lines[i];
                  final action = _LineAction.of(line);
                  return ListTile(
                    dense: true,
                    title: Text(line),
                    onTap: () => copy(line, 'Line'),
                    trailing: action == null
                        ? null
                        : IconButton(
                            tooltip: action.label,
                            icon: Icon(action.icon),
                            onPressed: () => _confirmAndOpen(context, action),
                          ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: FilledButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy all text'),
                onPressed: () => copy(lines.join('\n'), 'Text'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add photo as a page'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A safe action found in a line of text or a QR code: open a web link,
/// write an email or call a number. Nothing runs without a tap and a
/// confirmation.
class _LineAction {
  const _LineAction(this.uri, this.label, this.icon);

  final Uri uri;
  final String label;
  final IconData icon;

  static final _url = RegExp(r'https?://[^\s]+', caseSensitive: false);
  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final _phone = RegExp(r'\+?\d[\d\s().-]{7,}\d');

  static _LineAction? of(String line) {
    final url = _url.firstMatch(line)?.group(0);
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) return _LineAction(uri, 'Open link', Icons.open_in_new);
    }
    final email = _email.firstMatch(line)?.group(0);
    if (email != null) return _LineAction(Uri(scheme: 'mailto', path: email), 'Write email', Icons.mail_outline);
    final phone = _phone.firstMatch(line)?.group(0);
    if (phone != null) {
      return _LineAction(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), '')), 'Call', Icons.call);
    }
    return null;
  }
}

/// Shows where an action leads and runs it only on "Open".
Future<void> _confirmAndOpen(BuildContext context, _LineAction action) async {
  final target = switch (action.uri.scheme) {
    'mailto' || 'tel' => action.uri.path,
    _ => action.uri.toString(),
  };
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${action.label}?'),
      content: Text(target),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open')),
      ],
    ),
  );
  if (sure != true) return;
  final opened = await launchUrl(action.uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No app on this phone can open that')));
  }
}

/// QR mode result: what the code holds and what it would do. Nothing opens
/// without a tap and a confirmation (docs: "QR never executes a payload
/// without confirmation").
class _QrResultSheet extends StatelessWidget {
  const _QrResultSheet({required this.code});

  final QrResult code;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    final link = code.webLink;
    final (kind, icon) = switch (code.kind) {
      QrKind.link => ('Web link', Icons.link),
      QrKind.wifi => ('Wi-Fi network', Icons.wifi),
      QrKind.email => ('Email address', Icons.mail_outline),
      QrKind.phone => ('Phone number', Icons.call),
      QrKind.contact => ('Contact', Icons.person_outline),
      QrKind.text => ('Text', Icons.notes),
    };
    final action = link != null ? _LineAction(link, 'Open link', Icons.open_in_new) : _LineAction.of(code.raw);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.accent),
                const SizedBox(width: 10),
                Expanded(child: Text('QR code · $kind', style: Theme.of(context).textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: colors.surfaceRaised, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(code.raw, maxLines: 8),
            ),
            if (code.kind == QrKind.link && link == null) ...[
              const SizedBox(height: 8),
              Text(
                'This link is not a web address, so it is not offered to open.',
                style: TextStyle(color: colors.muted),
              ),
            ],
            const SizedBox(height: 16),
            if (action != null) ...[
              FilledButton.icon(
                icon: Icon(action.icon),
                label: Text(action.label),
                onPressed: () => _confirmAndOpen(context, action),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code.raw));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR code copied')));
                }
              },
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Scan again')),
          ],
        ),
      ),
    );
  }
}

class _DiscardDialog extends StatelessWidget {
  const _DiscardDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return AlertDialog(
      icon: Icon(Icons.close, color: colors.danger),
      title: const Text('Discard the photos?'),
      content: Text(
        'All $count photo${count == 1 ? '' : 's'} captured now and their changes will be removed '
        'and cannot be restored.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.danger, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Discard photos'),
        ),
        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep photos')),
      ],
    );
  }
}
