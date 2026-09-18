import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'services/route_alarm_service.dart';
import 'widgets/alarm_ring_overlay.dart';

/// URL del sitio hosteado en Firebase Hosting. Cada `firebase deploy
/// --only hosting` a este destino actualiza el contenido dentro de la app
/// al instante, sin publicar una nueva versión en las tiendas.
const String kHomeUrl = 'https://taxicab-a92b9.web.app/';

/// Nombre del canal JavaScript que la página web usa para mandarle las
/// rutas de hoy del chofer a este app nativo (ver
/// lib/features/chofer/chofer_routes/data/services/web_alarm_bridge_web.dart
/// en el repo principal de TaxiCab).
const String kNativeBridgeChannel = 'TaxiCabNative';

/// Procesa un mensaje de FCM del tipo "route_reminder_30": programa
/// localmente la alarma de 15 min para esa ruta. Se llama tanto si el
/// mensaje llega con la app en primer plano como en segundo plano/cerrada
/// (ver `_firebaseMessagingBackgroundHandler`). Esto es lo que resuelve el
/// caso de un chofer que nunca abrió la app desde que le asignaron la
/// ruta: el push del servidor despierta la app a tiempo para agendar la
/// alarma, sin depender de que la app ya estuviera corriendo antes.
///
/// También se agenda con "route_reminder_15" (el respaldo que el servidor
/// manda justo a los 15 min): Android ya muestra ESE push directo usando
/// el canal `RouteAlarmService.hardAlarmChannelId` aunque la app nunca
/// llegue a correr este código, así que la notificación con sonido de
/// alarma siempre llega de todos modos. Pero si la app sí logra
/// despertar con este segundo push (p. ej. porque el primero de 30 min no
/// la despertó a tiempo), programamos aquí también la alarma completa del
/// paquete `alarm` — con pantalla y botón "Detener" — en vez de dejar al
/// chofer solo con el sonido de la notificación de respaldo y sin nada
/// visible con qué apagarlo. `syncAlarms` hace sonar de inmediato una
/// alarma cuya hora ya se cumplió en vez de descartarla, así que esto
/// funciona aunque para este momento ya hayan pasado los 15 min.
Future<void> _handleRouteReminderMessage(RemoteMessage message) async {
  final type = message.data['type'];
  if (type != 'route_reminder_30' && type != 'route_reminder_15') return;
  try {
    await RouteAlarmService().init();
    final route = {
      'id': message.data['scheduleId'],
      'ruta': message.data['ruta'],
      'estado': 'confirmado',
      'dia': message.data['dia'],
      'hora': message.data['hora'],
    };
    await RouteAlarmService().syncAlarms([route]);
  } catch (e) {
    debugPrint('Error procesando push de recordatorio: $e');
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _handleRouteReminderMessage(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_handleRouteReminderMessage);
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
  try {
    await Alarm.init();
    await RouteAlarmService().init();
  } catch (e) {
    debugPrint('Alarm init failed: $e');
  }
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
      builder: (context, child) =>
          AlarmRingOverlay(child: child ?? const SizedBox.shrink()),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _registeredChoferId;
  String? _lastIdToken;
  String? _lastFcmToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = _buildController();
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      final choferId = _registeredChoferId;
      final idToken = _lastIdToken;
      // El idToken guardado puede haber expirado (dura ~1 hora); si ya no
      // sirve, el servidor simplemente rechaza este reenvío puntual — el
      // registro original ya se hizo bien y sigue vigente.
      if (choferId != null && idToken != null) {
        _sendTokenToServer(choferId, idToken, newToken);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Si el chofer ignoró o negó el permiso de pantalla completa / batería
    // la primera vez, cada vez que vuelve a la app (p. ej. después de que
    // le suene la alarma sin nada visible con qué apagarla, y la abra a
    // mano) se lo volvemos a pedir — de lo contrario se queda sin esos
    // permisos para siempre y el problema nunca se corrige solo.
    if (state == AppLifecycleState.resumed) {
      RouteAlarmService().init();
    }
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
          onNavigationRequest: _handleNavigationRequest,
        ),
      )
      // Debe agregarse ANTES de loadRequest: un canal nuevo solo surte
      // efecto a partir de la siguiente carga de página.
      ..addJavaScriptChannel(
        kNativeBridgeChannel,
        onMessageReceived: _onRoutesFromWebApp,
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

  /// Intercepta la navegación ANTES de que el WebView intente cargarla.
  ///
  /// Necesario para los links de "Navegar ruta completa" (Google Maps):
  /// si se dejan cargar dentro del WebView, la propia página de Google
  /// detecta que está en un WebView y se auto-redirige a un link
  /// `intent://...`, que un WebView normal no sabe interpretar y truena
  /// con "net::ERR_UNKNOWN_URL_SCHEME". Por eso cualquier link de Maps (o
  /// cualquier esquema que no sea http/https, como `tel:`, `mailto:`,
  /// `geo:` o el propio `intent://` si llegara a aparecer) se manda a una
  /// app externa en vez de dejarlo cargar aquí.
  NavigationDecision _handleNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    final isWebScheme = uri.scheme == 'http' || uri.scheme == 'https';
    final isMapsLink = isWebScheme &&
        (uri.host == 'maps.google.com' ||
            uri.host == 'maps.app.goo.gl' ||
            (uri.host.endsWith('google.com') &&
                uri.path.startsWith('/maps')));

    if (!isWebScheme || isMapsLink) {
      _openExternally(uri);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _openExternally(Uri uri) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('No se pudo abrir externamente $uri: $e');
    }
  }

  /// Recibe los mensajes que la página web manda por
  /// `TaxiCabNative.postMessage(...)`.
  ///
  /// Si trae `{action: 'logout'}`, ver [_onLogoutFromWebApp]. Si no, se
  /// asume `{choferId, idToken, routes}`: programa el aviso de 30 min y la
  /// alarma de 15 min para cada ruta, y registra el token de push del
  /// chofer para que el servidor pueda avisarle aunque nunca haya abierto
  /// la app desde que le asignaron la ruta.
  ///
  /// `idToken` es un token de identidad fresco de la sesión de Firebase
  /// Auth de la propia página web (este app no tiene sesión nativa propia
  /// — el login vive dentro del webview). Se lo pasamos al servidor para
  /// que pueda verificar que quien registra el aviso push es de verdad
  /// ese chofer, no alguien adivinando su ID.
  void _onRoutesFromWebApp(JavaScriptMessage message) {
    debugPrint('[TaxiCabNative] mensaje recibido: ${message.message}');
    try {
      final decoded = jsonDecode(message.message) as Map<String, dynamic>;

      if (decoded['action'] == 'logout') {
        _onLogoutFromWebApp(decoded);
        return;
      }

      final choferId = decoded['choferId'] as String?;
      final idToken = decoded['idToken'] as String?;
      final routesRaw = decoded['routes'] as List<dynamic>? ?? [];
      final routes = routesRaw.cast<Map<String, dynamic>>();

      RouteAlarmService().syncAlarms(routes);

      if (choferId != null &&
          choferId.isNotEmpty &&
          idToken != null &&
          idToken.isNotEmpty &&
          choferId != _registeredChoferId) {
        _registeredChoferId = choferId;
        _registerFcmToken(choferId, idToken);
      }
    } catch (e) {
      debugPrint('Error procesando rutas del webview: $e');
    }
  }

  /// El chofer cerró sesión en la página web: cancela lo que quedó
  /// programado en el sistema operativo (no depende de la sesión web, así
  /// que seguiría sonando si no se cancela explícitamente) y da de baja el
  /// token de push para que el servidor deje de mandarle recordatorios a
  /// este dispositivo.
  Future<void> _onLogoutFromWebApp(Map<String, dynamic> decoded) async {
    debugPrint('[TaxiCabNative] logout recibido, cancelando alarmas');
    await RouteAlarmService().cancelAll();

    final choferId = (decoded['choferId'] as String?) ?? _registeredChoferId;
    final token = _lastFcmToken;
    if (choferId != null && choferId.isNotEmpty && token != null) {
      try {
        await FirebaseFunctions.instance
            .httpsCallable('unregisterChoferFcmToken')
            .call({'choferId': choferId, 'fcmToken': token});
        debugPrint('Token FCM dado de baja para $choferId');
      } catch (e) {
        debugPrint('Error dando de baja el token FCM: $e');
      }
    }

    _registeredChoferId = null;
    _lastIdToken = null;
    _lastFcmToken = null;
  }

  Future<void> _registerFcmToken(String choferId, String idToken) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      _lastIdToken = idToken;
      await _sendTokenToServer(choferId, idToken, token);
    } catch (e) {
      debugPrint('Error obteniendo token FCM: $e');
    }
  }

  /// [idToken] es el token de identidad de la sesión web del chofer (ver
  /// `_onRoutesFromWebApp`); el servidor lo verifica para confirmar que
  /// quien registra el token de push es de verdad ese chofer.
  Future<void> _sendTokenToServer(
    String choferId,
    String idToken,
    String fcmToken,
  ) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('registerChoferFcmToken')
          .call({
        'choferId': choferId,
        'idToken': idToken,
        'fcmToken': fcmToken,
      });
      _lastFcmToken = fcmToken;
      debugPrint('Token FCM registrado para $choferId');
    } catch (e) {
      debugPrint('Error registrando token FCM: $e');
    }
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
