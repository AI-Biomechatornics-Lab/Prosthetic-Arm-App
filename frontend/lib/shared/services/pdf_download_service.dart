import 'dart:html' as html;
import 'package:dio/dio.dart' as dio;
import 'api_client.dart';

/// Requests the PDF log export from the backend and triggers a browser
/// download. Web-only (this project targets Flutter web exclusively).
Future<void> downloadLogsPdf(int userId) async {
  final res = await ApiClient.instance.dio.post<List<int>>(
    '/logs/$userId/export',
    options: dio.Options(responseType: dio.ResponseType.bytes),
  );

  final blob = html.Blob([res.data], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', 'session-log-$userId.pdf')
    ..click();
  html.Url.revokeObjectUrl(url);
}
