import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/theme.dart';

/// First-run intro: three short pages, then one question about usage data.
/// Skip goes to that question, and the answer never limits what the app can
/// do. Shown once, and again from Settings (Replay intro).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called when the user answers the last question. A replay closes the
  /// screen here; on first run the app swaps to Home.
  final VoidCallback onDone;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _pages = <_IntroPage>[
    _IntroPage(
      Icons.document_scanner_outlined,
      'Scan anything',
      'Point your camera at a page. LumaScan finds the edges and cleans it up, or turn photos you already have into pages.',
    ),
    _IntroPage(
      Icons.edit_document,
      'Edit and sign',
      'Mark up a page, add text, or sign a PDF. Your original stays as it was until you save.',
    ),
    _IntroPage(
      Icons.ios_share,
      'Save and send',
      'Keep your PDFs on this device, and send one as it is or as a smaller copy when you are ready.',
    ),
  ];

  final _controller = PageController();
  int _page = 0;

  int get _last => _pages.length; // the question after the intro pages

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _controller.animateToPage(page, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _finish(bool? analytics) {
    ref.read(appSettingsProvider.notifier).completeOnboarding(analytics: analytics);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final onQuestion = _page == _last;
    return PopScope(
      // Back steps to the previous page. On the first page it leaves the
      // screen, which closes a replay.
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_page - 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 56,
                  child: onQuestion ? null : TextButton(onPressed: () => _goTo(_last), child: const Text('Skip')),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    for (final page in _pages) _IntroView(page),
                    _ConsentView(onAnswer: _finish),
                  ],
                ),
              ),
              if (!onQuestion)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.page, Space.md, Space.page, Space.xl),
                  child: Column(
                    children: [
                      _Dots(count: _pages.length, index: _page),
                      const SizedBox(height: Space.xl),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(onPressed: () => _goTo(_page + 1), child: const Text('Next')),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroPage {
  const _IntroPage(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

class _IntroView extends StatelessWidget {
  const _IntroView(this.page);

  final _IntroPage page;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Space.page + Space.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height * 0.5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                child: Icon(page.icon, size: 56, color: c.accent),
              ),
            ),
            const SizedBox(height: Space.xxl),
            Semantics(
              header: true,
              child: Text(page.title, style: text.headlineMedium, textAlign: TextAlign.center),
            ),
            const SizedBox(height: Space.md),
            Text(
              page.body,
              style: text.bodyLarge?.copyWith(color: c.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentView extends StatelessWidget {
  const _ConsentView({required this.onAnswer});

  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.page + Space.sm, 0, Space.page + Space.sm, Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Space.xl),
          Center(
            child: ExcludeSemantics(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                child: Icon(Icons.insights_outlined, size: 56, color: c.accent),
              ),
            ),
          ),
          const SizedBox(height: Space.xxl),
          Semantics(
            header: true,
            child: Text('Help improve LumaScan?', style: text.headlineMedium, textAlign: TextAlign.center),
          ),
          const SizedBox(height: Space.md),
          Text(
            'You can share anonymous usage data, such as which features are used and where the app fails. '
            'Your documents, pages and file names are never part of it.',
            style: text.bodyLarge?.copyWith(color: c.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.md),
          Text(
            'This is optional and LumaScan works the same either way. You can change it any time in Settings.',
            style: text.bodyMedium?.copyWith(color: c.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xxl),
          FilledButton(onPressed: () => onAnswer(true), child: const Text('Share usage data')),
          const SizedBox(height: Space.md),
          OutlinedButton(onPressed: () => onAnswer(false), child: const Text('No thanks')),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    return Semantics(
      label: 'Step ${index + 1} of $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == index ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == index ? c.accent : c.accentSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
