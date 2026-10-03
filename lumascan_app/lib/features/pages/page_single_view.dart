import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../imaging/render_service.dart';
import 'page_actions.dart';
import 'page_image.dart';
import 'scan_controller.dart';

/// Single-page layout for the Pages screen: one large page you can swipe
/// through, previous/next buttons around a "Page X of N" label, a strip of
/// numbered thumbnails, and the page actions underneath.
class PageSingleView extends ConsumerStatefulWidget {
  const PageSingleView({super.key, required this.pages});

  final List<ScanPage> pages;

  @override
  ConsumerState<PageSingleView> createState() => _PageSingleViewState();
}

class _PageSingleViewState extends ConsumerState<PageSingleView> {
  static const _stripItemExtent = 72.0;

  final _pager = PageController();
  final _strip = ScrollController();
  var _index = 0;

  @override
  void dispose() {
    _pager.dispose();
    _strip.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PageSingleView old) {
    super.didUpdateWidget(old);
    // A delete can leave the selection past the end; keep the counter, the
    // big page and the strip on the same page.
    if (_index >= widget.pages.length && widget.pages.isNotEmpty) {
      _index = widget.pages.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pager.hasClients) _pager.jumpToPage(_index);
      });
    }
  }

  void _goTo(int i) {
    if (i < 0 || i >= widget.pages.length) return;
    _pager.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    if (_strip.hasClients) {
      final position = _strip.position;
      final target = i * _stripItemExtent - (position.viewportDimension - _stripItemExtent) / 2;
      _strip.animateTo(
        target.clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.pages;
    // Deleting the last page leaves the index past the end.
    final index = math.min(_index, pages.length - 1);
    final page = pages[index];
    final colors = LumaColors.of(context);
    final busy = ref.watch(scanControllerProvider.select((s) => s.busy));

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pager,
            itemCount: pages.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Semantics(
                image: true,
                label: 'Page ${i + 1} of ${pages.length}',
                child: PageImage(key: ValueKey(pages[i].id), page: pages[i], maxDimension: RenderService.previewSize),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Previous page',
                icon: const Icon(Icons.chevron_left),
                onPressed: index > 0 ? () => _goTo(index - 1) : null,
              ),
              Expanded(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: colors.surfaceRaised, borderRadius: BorderRadius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      child: Text(
                        'Page ${index + 1} of ${pages.length}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Next page',
                icon: const Icon(Icons.chevron_right),
                onPressed: index < pages.length - 1 ? () => _goTo(index + 1) : null,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 92,
          child: ListView.builder(
            controller: _strip,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemExtent: _stripItemExtent,
            itemCount: pages.length,
            itemBuilder: (context, i) => _StripThumb(
              key: ValueKey(pages[i].id),
              page: pages[i],
              number: i + 1,
              selected: i == index,
              onTap: () => _goTo(i),
            ),
          ),
        ),
        // One toolbar for the page's actions; it scrolls when large text
        // makes the buttons wider than the screen.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final a in PageAction.values)
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(56, 56)),
                    onPressed: busy ? null : () => runPageAction(context, ref, a, page, index),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(a.icon),
                        const SizedBox(height: 4),
                        Text(a.shortLabel, maxLines: 1, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StripThumb extends StatelessWidget {
  const _StripThumb({super.key, required this.page, required this.number, required this.selected, required this.onTap});

  final ScanPage page;
  final int number;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Page $number',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? colors.accent : Theme.of(context).dividerColor,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageImage(page: page),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        '$number',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
