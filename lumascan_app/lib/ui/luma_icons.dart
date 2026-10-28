import 'package:flutter/material.dart';

/// Every icon the app shows, in one place. The look follows CamScanner-style
/// scanner apps: thin rounded line icons (Phosphor Regular), the filled
/// weight for a selected state, and two-tone icons on tool tiles. The
/// Phosphor fonts are bundled under assets/fonts/phosphor (MIT licence).
/// Auto capture and Split keep their Material icons on purpose. Swap an icon
/// here and it changes on every screen.
abstract final class LumaIcons {
  static const _regular = 'Phosphor';
  static const _fill = 'PhosphorFill';
  static const _duotone = 'PhosphorDuotone';

  static const IconData add = IconData(0xe3d4, fontFamily: _regular);
  static const IconData addImage = IconData(0xe2cc, fontFamily: _regular);
  static const IconData addPhoto = IconData(0xec58, fontFamily: _regular);
  static const IconData adjust = IconData(0xe434, fontFamily: _regular);
  static const IconData allFolders = IconData(0xe260, fontFamily: _regular);
  static const IconData analytics = IconData(0xe150, fontFamily: _regular);
  static const IconData article = IconData(0xe0a8, fontFamily: _regular);
  static const IconData autoCapture = Icons.motion_photos_auto_outlined; // kept on purpose
  static const IconData batch = IconData(0xe466, fontFamily: _regular);
  static const IconData batchEdit = IconData(0xe188, fontFamily: _regular);
  static const IconData blackAndWhite = IconData(0xe18c, fontFamily: _regular);
  static const IconData book = IconData(0xe0e6, fontFamily: _regular);
  static const IconData brokenImage = IconData(0xe7a8, fontFamily: _regular);
  static const IconData camera = IconData(0xe10e, fontFamily: _regular);
  static const IconData cameraFilled = IconData(0xe10e, fontFamily: _fill);
  static const IconData cancelled = IconData(0xe3de, fontFamily: _regular);
  static const IconData check = IconData(0xe182, fontFamily: _regular);
  static const IconData checkCircle = IconData(0xe184, fontFamily: _regular);
  static const IconData clearCache = IconData(0xec54, fontFamily: _regular);
  static const IconData clearFilter = IconData(0xe26c, fontFamily: _regular);
  static const IconData close = IconData(0xe4f6, fontFamily: _regular);
  static const IconData cloud = IconData(0xe1aa, fontFamily: _regular);
  static const IconData collage = IconData(0xe464, fontFamily: _regular);
  static const IconData compress = IconData(0xe09e, fontFamily: _regular);
  static const IconData contact = IconData(0xe6f8, fontFamily: _regular);
  static const IconData contrast = IconData(0xe18e, fontFamily: _regular);
  static const IconData copy = IconData(0xe1ca, fontFamily: _regular);
  static const IconData create = IconData(0xe236, fontFamily: _regular);
  static const IconData createNewFolder = IconData(0xe25e, fontFamily: _regular);
  static const IconData creditCard = IconData(0xe1d2, fontFamily: _regular);
  static const IconData crop = IconData(0xe1d4, fontFamily: _regular);
  static const IconData darkTheme = IconData(0xe330, fontFamily: _regular);
  static const IconData date = IconData(0xe10a, fontFamily: _regular);
  static const IconData delete = IconData(0xe4a6, fontFamily: _regular);
  static const IconData deselect = IconData(0xe69e, fontFamily: _regular);
  static const IconData device = IconData(0xe1e0, fontFamily: _regular);
  static const IconData document = IconData(0xe23a, fontFamily: _regular);
  static const IconData documentSelected = IconData(0xe710, fontFamily: _fill);
  static const IconData download = IconData(0xe20c, fontFamily: _regular);
  static const IconData dragHandle = IconData(0xeae2, fontFamily: _regular);
  static const IconData dropDown = IconData(0xe136, fontFamily: _regular);
  static const IconData duplicate = IconData(0xe1ca, fontFamily: _regular);
  static const IconData edit = IconData(0xe434, fontFamily: _regular);
  static const IconData editPdf = IconData(0xe34c, fontFamily: _regular);
  static const IconData enhance = IconData(0xe6b6, fontFamily: _regular);
  static const IconData erase = IconData(0xe21e, fontFamily: _regular);
  static const IconData error = IconData(0xe4e2, fontFamily: _regular);
  static const IconData extract = IconData(0xe1cc, fontFamily: _regular);
  static const IconData file = IconData(0xe230, fontFamily: _regular);
  static const IconData filter = IconData(0xe268, fontFamily: _regular);
  static const IconData fitSize = IconData(0xe232, fontFamily: _regular);
  static const IconData flash = IconData(0xe2de, fontFamily: _regular);
  static const IconData flashOff = IconData(0xe2e0, fontFamily: _regular);
  static const IconData folder = IconData(0xe25a, fontFamily: _regular);
  static const IconData folderOpen = IconData(0xe256, fontFamily: _regular);
  static const IconData forward = IconData(0xe06c, fontFamily: _regular);
  static const IconData fullPage = IconData(0xe626, fontFamily: _regular);
  static const IconData fullPhoto = IconData(0xe1d0, fontFamily: _regular);
  static const IconData gallery = IconData(0xe834, fontFamily: _regular);
  static const IconData googleDrive = IconData(0xe8f6, fontFamily: _regular);
  static const IconData grid = IconData(0xec8c, fontFamily: _regular);
  static const IconData gridView = IconData(0xe464, fontFamily: _regular);
  static const IconData hand = IconData(0xe298, fontFamily: _regular);
  static const IconData help = IconData(0xe3e8, fontFamily: _regular);
  static const IconData hide = IconData(0xe224, fontFamily: _regular);
  static const IconData highlight = IconData(0xec76, fontFamily: _regular);
  static const IconData home = IconData(0xe2c2, fontFamily: _regular);
  static const IconData hourglass = IconData(0xe2b8, fontFamily: _regular);
  static const IconData idCard = IconData(0xe2c8, fontFamily: _regular);
  static const IconData image = IconData(0xe2ca, fontFamily: _regular);
  static const IconData inbox = IconData(0xe4aa, fontFamily: _regular);
  static const IconData info = IconData(0xe2ce, fontFamily: _regular);
  static const IconData initials = IconData(0xe6ee, fontFamily: _regular);
  static const IconData insights = IconData(0xe156, fontFamily: _regular);
  static const IconData library = IconData(0xe758, fontFamily: _regular);
  static const IconData lightTheme = IconData(0xe472, fontFamily: _regular);
  static const IconData link = IconData(0xe2e6, fontFamily: _regular);
  static const IconData listView = IconData(0xe2f0, fontFamily: _regular);
  static const IconData lock = IconData(0xe308, fontFamily: _regular);
  static const IconData mail = IconData(0xe218, fontFamily: _regular);
  static const IconData merge = IconData(0xedf6, fontFamily: _regular);
  static const IconData more = IconData(0xe1fe, fontFamily: _regular);
  static const IconData move = IconData(0xe0a4, fontFamily: _regular);
  static const IconData moveDown = IconData(0xe03e, fontFamily: _regular);
  static const IconData moveToFolder = IconData(0xec2a, fontFamily: _regular);
  static const IconData moveUp = IconData(0xe08e, fontFamily: _regular);
  static const IconData nameAndDate = IconData(0xe6f6, fontFamily: _regular);
  static const IconData newTag = IconData(0xe478, fontFamily: _regular);
  static const IconData next = IconData(0xe13a, fontFamily: _regular);
  static const IconData noCamera = IconData(0xe110, fontFamily: _regular);
  static const IconData noResults = IconData(0xe30e, fontFamily: _regular);
  static const IconData noText = IconData(0xe32c, fontFamily: _regular);
  static const IconData offline = IconData(0xe1b6, fontFamily: _regular);
  static const IconData openExternal = IconData(0xe5de, fontFamily: _regular);
  static const IconData organizePages = IconData(0xe5a2, fontFamily: _regular);
  static const IconData pageNumbers = IconData(0xe2f6, fontFamily: _regular);
  static const IconData pageView = IconData(0xe230, fontFamily: _regular);
  static const IconData pdf = IconData(0xe702, fontFamily: _regular);
  static const IconData phone = IconData(0xe3b8, fontFamily: _regular);
  static const IconData previous = IconData(0xe138, fontFamily: _regular);
  static const IconData pro = IconData(0xe616, fontFamily: _regular);
  static const IconData profile = IconData(0xe4c4, fontFamily: _fill);
  static const IconData qrCode = IconData(0xe3e6, fontFamily: _regular);
  static const IconData radioOff = IconData(0xe18a, fontFamily: _regular);
  static const IconData radioOn = IconData(0xeb08, fontFamily: _fill);
  static const IconData redo = IconData(0xe08c, fontFamily: _regular);
  static const IconData remove = IconData(0xe32a, fontFamily: _regular);
  static const IconData removeDate = IconData(0xe10c, fontFamily: _regular);
  static const IconData rename = IconData(0xebc6, fontFamily: _regular);
  static const IconData reorder = IconData(0xe098, fontFamily: _regular);
  static const IconData replay = IconData(0xe038, fontFamily: _regular);
  static const IconData reset = IconData(0xe038, fontFamily: _regular);
  static const IconData retake = IconData(0xe7a4, fontFamily: _regular);
  static const IconData retry = IconData(0xe036, fontFamily: _regular);
  static const IconData rotateLeft = IconData(0xe014, fontFamily: _regular);
  static const IconData rotateRight = IconData(0xe016, fontFamily: _regular);
  static const IconData samplePages = IconData(0xe836, fontFamily: _regular);
  static const IconData save = IconData(0xe20c, fontFamily: _regular);
  static const IconData scan = IconData(0xebb6, fontFamily: _regular);
  static const IconData scanDocs = IconData(0xebb6, fontFamily: _regular);
  static const IconData schedule = IconData(0xe19a, fontFamily: _regular);
  static const IconData search = IconData(0xe30c, fontFamily: _regular);
  static const IconData select = IconData(0xe186, fontFamily: _regular);
  static const IconData selectAll = IconData(0xe746, fontFamily: _regular);
  static const IconData selected = IconData(0xe184, fontFamily: _fill);
  static const IconData share = IconData(0xeaf0, fontFamily: _regular);
  static const IconData sharedFolder = IconData(0xeb46, fontFamily: _regular);
  static const IconData shield = IconData(0xe40c, fontFamily: _regular);
  static const IconData show = IconData(0xe220, fontFamily: _regular);
  static const IconData sign = IconData(0xe3ac, fontFamily: _regular);
  static const IconData smart = IconData(0xe6a2, fontFamily: _regular);
  static const IconData sort = IconData(0xe444, fontFamily: _regular);
  static const IconData speed = IconData(0xe628, fontFamily: _regular);
  static const IconData split = Icons.call_split; // kept on purpose
  static const IconData storefront = IconData(0xe470, fontFamily: _regular);
  static const IconData sync = IconData(0xe094, fontFamily: _regular);
  static const IconData table = IconData(0xe476, fontFamily: _regular);
  static const IconData tag = IconData(0xe47a, fontFamily: _regular);
  static const IconData text = IconData(0xe484, fontFamily: _regular);
  static const IconData textResult = IconData(0xec96, fontFamily: _regular);
  static const IconData textTool = IconData(0xe48a, fontFamily: _regular);
  static const IconData themeSystem = IconData(0xe18c, fontFamily: _regular);
  static const IconData tools = IconData(0xe464, fontFamily: _regular);
  static const IconData toolsSelected = IconData(0xe464, fontFamily: _fill);
  static const IconData undo = IconData(0xe08a, fontFamily: _regular);
  static const IconData unselected = IconData(0xe18a, fontFamily: _regular);
  static const IconData watermark = IconData(0xea48, fontFamily: _regular);
  static const IconData watermarkFilled = IconData(0xea48, fontFamily: _fill);
  static const IconData wifi = IconData(0xe4ea, fontFamily: _regular);
  static const IconData zoomIn = IconData(0xe310, fontFamily: _regular);
  static const IconData zoomOut = IconData(0xe30e, fontFamily: _regular);

  // Meanings that used to share an icon with something else.
  static const IconData proBadge = IconData(0xe616, fontFamily: _fill);
  static const IconData password = IconData(0xe2fe, fontFamily: _regular);
  static const IconData pen = IconData(0xe3aa, fontFamily: _regular);
  static const IconData export = IconData(0xeaf0, fontFamily: _regular);
  static const IconData docsTab = IconData(0xe710, fontFamily: _regular);

  // Two-tone icons for the tool tiles.
  static const LumaDuotone toolIdCard = LumaDuotone(
    IconData(0xe2c8, fontFamily: _duotone),
    IconData(0xe2c9, fontFamily: _duotone),
  );
  static const LumaDuotone toolScanDocs = LumaDuotone(
    IconData(0xebb6, fontFamily: _duotone),
    IconData(0xebb7, fontFamily: _duotone),
  );
  static const LumaDuotone toolBook = LumaDuotone(
    IconData(0xe0e6, fontFamily: _duotone),
    IconData(0xe0e7, fontFamily: _duotone),
  );
  static const LumaDuotone toolQr = LumaDuotone(
    IconData(0xe3e6, fontFamily: _duotone),
    IconData(0xe3e7, fontFamily: _duotone),
  );
  static const LumaDuotone toolText = LumaDuotone(
    IconData(0xe48a, fontFamily: _duotone),
    IconData(0xe48b, fontFamily: _duotone),
  );
  static const LumaDuotone toolTable = LumaDuotone(
    IconData(0xe476, fontFamily: _duotone),
    IconData(0xe477, fontFamily: _duotone),
  );
  static const LumaDuotone toolPhotos = LumaDuotone(
    IconData(0xe834, fontFamily: _duotone),
    IconData(0xe835, fontFamily: _duotone),
  );
  static const LumaDuotone toolPdfToWord = LumaDuotone(
    IconData(0xe23a, fontFamily: _duotone),
    IconData(0xe23b, fontFamily: _duotone),
  );
  static const LumaDuotone toolWordToPdf = LumaDuotone(
    IconData(0xe702, fontFamily: _duotone),
    IconData(0xe703, fontFamily: _duotone),
  );
  static const LumaDuotone toolMerge = LumaDuotone(
    IconData(0xedf6, fontFamily: _duotone),
    IconData(0xedf7, fontFamily: _duotone),
  );
  static const LumaDuotone toolSign = LumaDuotone(
    IconData(0xe3ac, fontFamily: _duotone),
    IconData(0xe3ad, fontFamily: _duotone),
  );
  static const LumaDuotone toolEditPdf = LumaDuotone(
    IconData(0xe34c, fontFamily: _duotone),
    IconData(0xe34d, fontFamily: _duotone),
  );
  static const LumaDuotone toolSplit = LumaDuotone.single(split); // kept on purpose
  static const LumaDuotone toolReorder = LumaDuotone(
    IconData(0xe5a2, fontFamily: _duotone),
    IconData(0xe5a3, fontFamily: _duotone),
  );
}

/// A two-tone icon: a faint back layer under the line drawing.
@immutable
class LumaDuotone {
  const LumaDuotone(this.back, this.front);

  /// A one-layer icon shown where a two-tone one is expected.
  const LumaDuotone.single(this.front) : back = null;

  final IconData? back;
  final IconData front;
}

/// Draws a [LumaDuotone] in one colour, the back layer at 20% opacity.
class DuotoneIcon extends StatelessWidget {
  const DuotoneIcon(this.icon, {super.key, this.size, this.color});

  final LumaDuotone icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colour = color ?? IconTheme.of(context).color;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (icon.back != null) Icon(icon.back, size: size, color: colour?.withValues(alpha: 0.2)),
        Icon(icon.front, size: size, color: colour),
      ],
    );
  }
}
