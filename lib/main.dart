import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// URL del sitio hosteado en Firebase Hosting. Cada `firebase deploy
/// --only hosting` a este destino actualiza el contenido dentro de la app
/// al instante, sin publicar una nueva versión en las tiendas.
const String kHomeUrl = 'https://taxicab-a92b9.web.app/';

void main() {
  runApp(const TaxiCabViewerApp());
}

class TaxiCabViewerApp extends StatelessWidget {
  const TaxiCabViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kaiteki Anzen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
  }

  WebViewController _buildController() {
    final PlatformWebViewControllerCreationParams params =
        WebViewPlatform.instance is AndroidWebViewPlatform
        ? AndroidWebViewControllerCreationParams()
        : const PlatformWebViewControllerCreationParams();

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(kHomeUrl));

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform
        ..setGeolocationEnabled(true)
        ..setMediaPlaybackRequiresUserGesture(false)
        ..setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: (request) async {
            final granted = await _ensurePermission(Permission.location);
            return GeolocationPermissionsResponse(
              allow: granted,
              retain: true,
            );
          },
        )
        ..setOnShowFileSelector(_onShowFileSelector);
    }

    return controller;
  }

  Future<bool> _ensurePermission(Permission permission) async {
    final status = await permission.status;
    if (status.isGranted) return true;
    final result = await permission.request();
    return result.isGranted;
  }

  /// Responde al `<input type="file">` de la página web. Si el input pide
  /// captura directa (`capture` attribute), abre la cámara; si no, deja
  /// elegir entre cámara o galería.
  Future<List<String>> _onShowFileSelector(FileSelectorParams params) async {
    final source = params.isCaptureEnabled
        ? ImageSource.camera
        : await _pickImageSource();
    if (source == null) return <String>[];

    if (source == ImageSource.camera) {
      final granted = await _ensurePermission(Permission.camera);
      if (!granted) return <String>[];
    }

    if (params.mode == FileSelectorMode.openMultiple &&
        source == ImageSource.gallery) {
      final photos = await ImagePicker().pickMultiImage(imageQuality: 85);
      return photos.map((f) => _toFileUri(f.path)).toList();
    }

    final photo = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (photo == null) return <String>[];
    return <String>[_toFileUri(photo.path)];
  }

  String _toFileUri(String path) => Uri.file(path).toString();

  Future<ImageSource?> _pickImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _handleBackNavigation() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _handleBackNavigation();
        if (shouldPop && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading) const LinearProgressIndicator(minHeight: 2),
            ],
          ),
        ),
      ),
    );
  }
}
