import 'dart:html' as html;

class PlatformDownload {
  static void downloadFile(String url, String fileName) {
    final anchor = html.AnchorElement(href: url)
      ..target = '_blank'
      ..download = fileName;
    anchor.click();
  }
}