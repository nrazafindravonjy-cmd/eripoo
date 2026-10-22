import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../usage/domain/usage_event.dart';
import '../../usage/presentation/usage_providers.dart';
import 'document_model.dart';

enum PdfKind { dossier, pitchDeck }

/// Words written by the PDF itself (not the user's).
class PdfLabels {
  const PdfLabels({required this.missingTitle, required this.footer});

  /// Heading of the list of chapters still to work on.
  final String missingTitle;

  /// Bottom of every page, from the page number and the page count.
  final String Function(int page, int pages) footer;
}

/// Bundled so every character of mg, fr and en prints (Apache 2.0,
/// assets/fonts/Roboto_LICENSE.txt).
const _regularFont = 'assets/fonts/Roboto-Regular.ttf';
const _boldFont = 'assets/fonts/Roboto-Bold.ttf';

/// Builds the PDF: A4 portrait for the file, A4 landscape slides for the
/// pitch deck. Pure: same input, same document.
Future<Uint8List> buildPdf({
  required PdfKind kind,
  required String title,
  required List<DocPart> parts,
  required List<DocPart> missing,
  required PdfLabels labels,
  required ByteData regular,
  required ByteData bold,
}) {
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(regular),
    bold: pw.Font.ttf(bold),
  );
  final doc = pw.Document(theme: theme, title: title, creator: 'Eripoo');

  pw.Widget items(List<DocItem> list, {double size = 11}) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final item in list)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: switch (item) {
            DocParagraph(:final text) => pw.Text(
              text,
              style: pw.TextStyle(fontSize: size),
            ),
            DocLabeled(:final label, :final text) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  label,
                  style: pw.TextStyle(
                    fontSize: size - 1,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(text, style: pw.TextStyle(fontSize: size)),
              ],
            ),
            DocBullet(:final text) => pw.Bullet(
              text: text,
              style: pw.TextStyle(fontSize: size),
            ),
          },
        ),
    ],
  );

  pw.Widget footer(pw.Context context) {
    final line = labels.footer(context.pageNumber, context.pagesCount);
    return pw.Text(
      line,
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
    );
  }

  switch (kind) {
    case PdfKind.dossier:
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          footer: footer,
          build: (_) => [
            pw.Header(level: 0, text: title),
            for (final part in parts) ...[
              pw.Header(level: 1, text: part.title),
              items(part.items),
            ],
            if (missing.isNotEmpty) ...[
              pw.Header(level: 1, text: labels.missingTitle),
              for (final part in missing) pw.Bullet(text: part.title),
            ],
          ],
        ),
      );
    case PdfKind.pitchDeck:
      for (final (i, slide) in parts.indexed) {
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(48),
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  slide.title,
                  style: pw.TextStyle(
                    fontSize: i == 0 ? 36 : 26,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 16),
                items(slide.items, size: 18),
                pw.Spacer(),
                footer(context),
              ],
            ),
          ),
        );
      }
  }
  return doc.save();
}

/// Hands a finished PDF to the system share sheet (replaced in tests).
abstract interface class PdfSharer {
  Future<void> share(File file, String title);
}

class SystemPdfSharer implements PdfSharer {
  @override
  Future<void> share(File file, String title) async {
    await SharePlus.instance.share(
      ShareParams(
        title: title,
        files: [XFile(file.path, mimeType: 'application/pdf')],
      ),
    );
  }
}

final pdfSharerProvider = Provider<PdfSharer>((ref) => SystemPdfSharer());

/// Where exported files wait while being shared: emptied after each share
/// and at start-up (they are in clear, unlike everything else).
final exportDirProvider = FutureProvider<Directory>(
  (ref) async => Directory('${(await getTemporaryDirectory()).path}/export'),
);

/// Deletes exported files left behind: ours (the app was closed while
/// the share sheet was open) and the copy the share sheet keeps in the
/// same cache until the next share (share_plus, Android).
Future<void> purgeExports(Directory dir) async {
  for (final d in [dir, Directory('${dir.parent.path}/share_plus')]) {
    if (await d.exists()) await d.delete(recursive: true);
  }
}

/// A file name without anything the file system could misread.
String exportFileName(String title, PdfKind kind) {
  final base = title
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final safe = base.isEmpty ? 'eripoo' : base;
  final cut = safe.length > 40 ? safe.substring(0, 40) : safe;
  return '${cut}_${kind == PdfKind.dossier ? 'dossier' : 'pitch'}.pdf';
}

/// Warns that the file leaves Eripoo's protection, builds it off the UI
/// thread, shares it, then deletes it.
Future<void> exportPdf(
  BuildContext context,
  WidgetRef ref, {
  required PdfKind kind,
  required String title,
  required List<DocPart> parts,
  List<DocPart> missing = const [],
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.exportWarningTitle),
      content: Text(l10n.exportWarningBody),
      actions: [
        EripooButton(
          label: l10n.actionCancel,
          variant: EripooButtonVariant.tertiary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        EripooButton(
          label: l10n.exportContinue,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (go != true) return;
  final labels = PdfLabels(
    missingTitle: l10n.dossierMissing,
    footer: l10n.exportFooter,
  );
  final sharer = ref.read(pdfSharerProvider);
  final dirFuture = ref.read(exportDirProvider.future);
  File? file;
  try {
    final regular = await rootBundle.load(_regularFont);
    final bold = await rootBundle.load(_boldFont);
    final bytes = await Isolate.run(
      () => buildPdf(
        kind: kind,
        title: title,
        parts: parts,
        missing: missing,
        labels: labels,
        regular: regular,
        bold: bold,
      ),
    );
    final dir = await dirFuture;
    await dir.create(recursive: true);
    file = File('${dir.path}/${exportFileName(title, kind)}');
    await file.writeAsBytes(bytes, flush: true);
    final record = ref.read(usageRecorderProvider);
    await sharer.share(file, title);
    await record(UsageEvent.pdfExported);
  } on Exception {
    messenger.showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
  } finally {
    if (file != null && await file.exists()) await file.delete();
  }
}
