import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_info.dart';
import 'device_auth.dart';
import 'preferences.dart';
import 'theme.dart';

/// The app lock for this run of the app.
@immutable
class AppLockState {
  const AppLockState({this.unlocked = false, this.busy = false, this.message});

  /// The owner proved it is them since the app last locked.
  final bool unlocked;

  /// The system prompt is showing. Leaving the app for it does not count as
  /// leaving the app.
  final bool busy;

  /// Shown on the lock screen after a check that went wrong.
  final String? message;
}

/// The time now; tests move it on.
final appLockClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(AppLockController.new);

/// Whether the lock screen covers the app. The setting is read on every
/// plan: turning the lock on needs Pro, but it stays on until turned off.
final appLockedProvider = Provider<bool>(
  (ref) => ref.watch(appSettingsProvider.select((s) => s.appLock)) && !ref.watch(appLockProvider).unlocked,
);

class AppLockController extends Notifier<AppLockState> {
  DateTime? _leftAt;

  @override
  AppLockState build() => const AppLockState();

  /// The app went to the background.
  void wentAway() {
    if (state.busy) return;
    _leftAt ??= ref.read(appLockClockProvider)();
  }

  /// The app is on screen again: locks when it was away for the chosen time.
  void cameBack() {
    final left = _leftAt;
    _leftAt = null;
    if (left == null || state.busy || !state.unlocked) return;
    final delay = ref.read(appSettingsProvider).appLockDelay.duration;
    if (ref.read(appLockClockProvider)().difference(left) >= delay) state = const AppLockState();
  }

  /// Asks for fingerprint, face or PIN and opens the app when it is them.
  Future<void> unlock() async {
    final result = await _ask('Unlock to see your documents');
    if (result == null) return;
    switch (result) {
      case DeviceAuthResult.success:
        state = const AppLockState(unlocked: true);
      case DeviceAuthResult.cancelled:
        state = const AppLockState();
      case DeviceAuthResult.unavailable:
        // The phone's screen lock was removed, which needed its PIN; with
        // nothing left to check against, the app lock turns itself off.
        ref.read(appSettingsProvider.notifier).setAppLock(false);
        state = const AppLockState(unlocked: true);
      case DeviceAuthResult.failed:
        state = const AppLockState(message: "Couldn't check it's you. Try again.");
    }
  }

  /// Asks the owner to confirm a change to the lock in Settings. The app is
  /// open, so a success also counts as unlocking it.
  Future<DeviceAuthResult?> confirm(String reason) async {
    final result = await _ask(reason);
    if (result == DeviceAuthResult.success) state = const AppLockState(unlocked: true);
    return result;
  }

  /// Null when a prompt is already showing.
  Future<DeviceAuthResult?> _ask(String reason) async {
    if (state.busy) return null;
    final before = state;
    state = AppLockState(unlocked: before.unlocked, busy: true);
    try {
      return await ref.read(deviceAuthProvider).authenticate(reason);
    } finally {
      _leftAt = null;
      if (ref.mounted) state = AppLockState(unlocked: before.unlocked);
    }
  }
}

/// Wraps the MaterialApp and tells the lock when the app leaves the screen
/// and comes back. It sits above the MaterialApp so it hears the back button
/// first, and keeps it from closing pages hidden behind the lock screen.
class AppLockScope extends ConsumerStatefulWidget {
  const AppLockScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockScope> createState() => _AppLockScopeState();
}

class _AppLockScopeState extends ConsumerState<AppLockScope> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final lock = ref.read(appLockProvider.notifier);
    switch (lifecycle) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        lock.wentAway();
      case AppLifecycleState.resumed:
        lock.cameBack();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  @override
  Future<bool> didPopRoute() async => ref.read(appLockedProvider);

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Covers [child] with the lock screen while the app is locked. [child]
/// stays built underneath, so whatever was open is there after unlocking.
class AppLockOverlay extends ConsumerWidget {
  const AppLockOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(appLockedProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: locked,
          child: ExcludeFocus(excluding: locked, child: child),
        ),
        if (locked) const LockScreen(),
      ],
    );
  }
}

/// Shown while the app is locked. Asks once on its own; after that the
/// Unlock button asks again.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appLockProvider.notifier).unlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    final lock = ref.watch(appLockProvider);
    return Material(
      color: c.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(Space.lg),
                decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                child: Icon(Icons.lock_outline, size: 40, color: c.ink),
              ),
              const SizedBox(height: Space.lg),
              Semantics(header: true, child: Text('$appName is locked', style: text.headlineSmall)),
              const SizedBox(height: Space.sm),
              Text(
                'Use your fingerprint, face or phone PIN to open it.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: c.muted),
              ),
              if (lock.message case final message?) ...[
                const SizedBox(height: Space.md),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: c.danger),
                ),
              ],
              const SizedBox(height: Space.xl),
              FilledButton.icon(
                onPressed: lock.busy ? null : () => ref.read(appLockProvider.notifier).unlock(),
                icon: const Icon(Icons.fingerprint),
                label: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
