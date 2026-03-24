// ignore_for_file: avoid_print
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  final pdf = pw.Document();

  final theme = pw.ThemeData.withFont(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
  );

  final skyBlue = PdfColor.fromInt(0xFF007BFF);
  final darkText = PdfColor.fromInt(0xFF333333);
  final lightText = PdfColor.fromInt(0xFF666666);

  // --- Slide 1: Title ---
  pdf.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(800, 600),
      theme: theme,
      build: (context) {
        return pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                'LabSense',
                style: pw.TextStyle(
                  fontSize: 64,
                  fontWeight: pw.FontWeight.bold,
                  color: skyBlue,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Intelligent Personal Health Dashboard',
                style: pw.TextStyle(fontSize: 32, color: darkText),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Privacy, Clarity, and Control for Your Medical Data',
                style: pw.TextStyle(fontSize: 24, color: lightText),
              ),
            ],
          ),
        );
      },
    ),
  );

  // --- Slide 2: The Problem ---
  pdf.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(800, 600),
      theme: theme,
      build: (context) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(40),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'The Problem',
                style: pw.TextStyle(
                  fontSize: 40,
                  fontWeight: pw.FontWeight.bold,
                  color: skyBlue,
                ),
              ),
              pw.SizedBox(height: 40),
              pw.Text(
                '"Medical data is complex, fragmented, and often unintelligible."',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontStyle: pw.FontStyle.italic,
                  color: darkText,
                ),
              ),
              pw.SizedBox(height: 40),
              _buildBulletPoint(
                'Complexity Barrier: Lab reports are full of jargon and confusing numbers.',
                darkText,
              ),
              _buildBulletPoint(
                'Fragmented History: Records scattered across clinics and paper files.',
                darkText,
              ),
              _buildBulletPoint(
                'Privacy Concerns: Lack of trust in how health data is handled.',
                darkText,
              ),
            ],
          ),
        );
      },
    ),
  );

  // --- Slide 3: The Solution (LabSense) ---
  pdf.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(800, 600),
      theme: theme,
      build: (context) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(40),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'The Solution: LabSense',
                style: pw.TextStyle(
                  fontSize: 40,
                  fontWeight: pw.FontWeight.bold,
                  color: skyBlue,
                ),
              ),
              pw.SizedBox(height: 30),
              pw.Text(
                'A privacy-first, AI-powered health analytics platform.',
                style: pw.TextStyle(fontSize: 24, color: darkText),
              ),
              pw.SizedBox(height: 40),
              _buildBulletPoint(
                'Intelligent Interpreter: AI explains "Why" a result is abnormal.',
                darkText,
              ),
              _buildBulletPoint(
                'Unified Timeline: Aggregates disparate reports into one view.',
                darkText,
              ),
              _buildBulletPoint(
                'Privacy by Design: HIPAA/DPDP compliant with End-to-End principles.',
                darkText,
              ),
              _buildBulletPoint(
                'Universal Ingestion: Photo-to-Data parsing for any lab report.',
                darkText,
              ),
            ],
          ),
        );
      },
    ),
  );

  // --- Slide 4: Key Features ---
  pdf.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(800, 600),
      theme: theme,
      build: (context) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(40),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Key Features',
                style: pw.TextStyle(
                  fontSize: 40,
                  fontWeight: pw.FontWeight.bold,
                  color: skyBlue,
                ),
              ),
              pw.SizedBox(height: 30),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildFeatureItem(
                          'AI-Powered Analysis',
                          'Instant, plain-English explanations.',
                          skyBlue,
                          darkText,
                        ),
                        pw.SizedBox(height: 20),
                        _buildFeatureItem(
                          'Dynamic Trend Tracking',
                          'Visualize health over years.',
                          skyBlue,
                          darkText,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildFeatureItem(
                          'Secure Storage',
                          'RLS & Audit Logging.',
                          skyBlue,
                          darkText,
                        ),
                        pw.SizedBox(height: 20),
                        _buildFeatureItem(
                          'Health Circles',
                          'Securely share data with family.',
                          skyBlue,
                          darkText,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  // --- Slide 5: Tech Stack ---
  pdf.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(800, 600),
      theme: theme,
      build: (context) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(40),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Technology Stack',
                style: pw.TextStyle(
                  fontSize: 40,
                  fontWeight: pw.FontWeight.bold,
                  color: skyBlue,
                ),
              ),
              pw.SizedBox(height: 40),
              _buildStackItem('Frontend', 'Flutter (Web & Mobile)', darkText),
              _buildStackItem(
                'Backend',
                'Supabase (PostgreSQL, Auth, RLS)',
                darkText,
              ),
              _buildStackItem('AI Engine', 'NVIDIA NIM 2.0 Flash', darkText),
              _buildStackItem(
                'Security',
                'Row Level Security & AES Encryption',
                darkText,
              ),
            ],
          ),
        );
      },
    ),
  );

  final file = File('LabSense_Project_Deck.pdf');
  await file.writeAsBytes(await pdf.save());
  print('PDF presentation deck generated: ${file.absolute.path}');
}

pw.Widget _buildBulletPoint(String text, PdfColor color) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 15),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '• ',
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
        pw.Expanded(
          child: pw.Text(text, style: pw.TextStyle(fontSize: 20, color: color)),
        ),
      ],
    ),
  );
}

pw.Widget _buildFeatureItem(
  String title,
  String desc,
  PdfColor titleColor,
  PdfColor descColor,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 24,
          fontWeight: pw.FontWeight.bold,
          color: titleColor,
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Text(desc, style: pw.TextStyle(fontSize: 18, color: descColor)),
    ],
  );
}

pw.Widget _buildStackItem(String label, String value, PdfColor color) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 20),
    child: pw.Row(
      children: [
        pw.Text(
          '$label: ',
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
        pw.Text(value, style: pw.TextStyle(fontSize: 24, color: color)),
      ],
    ),
  );
}

