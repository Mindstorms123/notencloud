// ignore_for_file: avoid_print
// Prüft das Drehen der Seiten mit der echten PDF-Engine im Browser. Aufruf wie
// booklet_web_perf_test.dart (lokaler CORS-Server mit build/web auf Port 8794).
@TestOn('browser')
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

Future<Uint8List> portraitPdf() async {
  final doc = sf.PdfDocument();
  doc.pageSettings.size = sf.PdfPageSize.a4;
  for (var i = 0; i < 2; i++) {
    doc.pages.add().graphics.drawString('Seite ${i + 1}', sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 30));
  }
  final bytes = Uint8List.fromList(await doc.save());
  doc.dispose();
  return bytes;
}

void main() {
  testWidgets('rotating pages re-lays out the live viewer', (tester) async {
    Pdfrx.pdfiumWasmModulesUrl = 'http://127.0.0.1:8794/assets/packages/pdfrx/assets/';
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late Uint8List bytes;
    PdfDocument? document;
    final controller = PdfViewerController();
    var readyCount = 0;

    await tester.runAsync(() async {
      bytes = await portraitPdf();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer.data(
          bytes,
          sourceName: 'dreh-test',
          controller: controller,
          params: PdfViewerParams(
            onViewerReady: (doc, _) {
              document = doc;
              readyCount++;
            },
          ),
        ),
      ),
    ));

    Future<void> settle() => tester.runAsync(() async {
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump(const Duration(milliseconds: 100));
          }
        });

    await settle();
    expect(document, isNotNull, reason: 'Betrachter wurde nicht bereit');
    final before = document!.pages.first;
    print('vorher: ${before.width} x ${before.height}, Layout ${controller.layout.pageLayouts.first.size}');
    expect(before.height, greaterThan(before.width));
    final layoutBefore = controller.layout.pageLayouts.first.size;

    document!.pages = document!.pages.map((p) => p.rotatedCW90()).toList();
    await settle();

    final after = document!.pages.first;
    final layoutAfter = controller.layout.pageLayouts.first.size;
    print('nachher: ${after.width} x ${after.height}, Layout $layoutAfter, bereit-Meldungen: $readyCount');
    expect(after.width, greaterThan(after.height));
    expect(layoutAfter.width / layoutAfter.height, greaterThan(1));
    expect(layoutBefore.width / layoutBefore.height, lessThan(1));
    expect(tester.takeException(), isNull);
  });
}
