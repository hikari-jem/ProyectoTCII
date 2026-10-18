import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const String kServiceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String kCharNotifyUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a9";
const String kCharWriteUuid = "82b99a01-596c-4527-983a-0123456789ab";

const List<String> frasesMemoria = [
  "",
  "Hola", "Ayuda", "Necesito asistencia ahora", "Llama a un medico", "Llama a mi familia",
  "Me siento muy mal", "Me cai y no puedo levantarme", "Me falta el aire", "Me duele el pecho", 
  "Me duele la cabeza muy fuerte", "Estoy mareado", "Siento que me voy a desmayar", "Voy a Convulsionarme", 
  "Hay un incendio", "Alguien entro a la casa", "Me lastime", "Estoy sangrando", "No me puedo mover", 
  "Acercate, por favor", "Quedate conmigo", "Ayudame a sentarme", "Ayudame a acostarme", 
  "Necesito mi medicamento", "Tengo hambre", "Tengo sed", "Quiero agua", "Quiero cafe", "Quiero te", 
  "Quiero jugo", "Quiero leche", "Gracias", "Aun tengo hambre", "Ya estoy satisfecho", 
  "La comida esta muy caliente", "La comida esta muy fria", "No me gusta esto", "Esta delicioso", 
  "Quiero mas, por favor", "Necesito una servilleta", "Necesito una cuchara", "Necesito un tenedor", 
  "Necesito un cuchillo", "Quiero comer algo dulce", "Quiero comer algo salado", "A que hora comemos?", 
  "Pasame la sal, por favor", "Necesito ir al bano", "Ayudame a ir al bano", "Necesito papel higienico", 
  "Necesito lavarme las manos", "Necesito lavarme los dientes", "Quiero banarme", "Necesito cambiarme de ropa", 
  "Tengo frio en los pies", "Tengo calor", "Estoy sudando", "Quiero peinarme", "Necesito cortarme las unas", 
  "Necesito crema hidratante", "Me apreta la ropa", "Quitame los zapatos", "Ponme los zapatos", 
  "Ayudame a vestirme", "Ayudame a desvestirme", "Limpiame la cara", "Necesito mi silla de ruedas", 
  "Necesito mi baston", "Me duele", "Me duele aqui", "Me Duele el estomago", 
  "Me Duele la espalda", "Me Duelen las piernas", "Me Duele la garganta", "Me Duelen los oidos", "Tengo Nauseas", 
  "Quiero Vomitar", "SI", "NO", "Tengo Escalofrios", "Me Siento debil", "Estoy Cansado", "Tengo Sueno", "No Puedo dormir", 
  "A que Hora me toca mi pastilla?", "Tengo lo Lentes sucios", "Tal vez", "No se", "Por favor", "Gracias", "De nada", 
  "Lo siento", "Perdon", "Disculpa", "Esta bien", "No importa", "Un momento", "Ahora no", 
  "Mas tarde", "Aqui", "Alli"
];

// ================= FUNCIONES DE ARCHIVO FÍSICO PERMANENTE EN DISCO =================
Future<File> _obtenerArchivoPermanente() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/comfred_datos_permanentes.json');
}

Future<Map<String, dynamic>> leerConfiguracionPermanente() async {
  try {
    final archivo = await _obtenerArchivoPermanente();
    if (await archivo.exists()) {
      final contenido = await archivo.readAsString();
      if (contenido.trim().isNotEmpty) {
        return jsonDecode(contenido) as Map<String, dynamic>;
      }
    }
  } catch (_) {}

  // Respaldo desde SharedPreferences si es la primera vez
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  List<int> botones = List.generate(10, (i) => prefs.getInt('btn_id_$i') ?? (i + 1));
  List<String> grabadosStr = prefs.getStringList('audios_grabados_v2') ?? [];
  List<dynamic> grabadosJson = grabadosStr.map((s) => jsonDecode(s)).toList();

  return {
    'nombrePersona': prefs.getString('nombrePersona') ?? "",
    'carpetaSeleccionada': prefs.getInt('carpetaSeleccionada') ?? 1,
    'codigoCaja': prefs.getString('codigoCaja') ?? "COMFRED_CRISTIAN_01",
    'botonAudioId': botones,
    'audiosPersonalizados': grabadosJson,
  };
}

Future<void> guardarConfiguracionPermanente({
  required String nombrePersona,
  required int carpetaSeleccionada,
  required String codigoCaja,
  required List<int> botonAudioId,
  required List<AudioPersonalizado> audiosPersonalizados,
}) async {
  final mapa = {
    'nombrePersona': nombrePersona,
    'carpetaSeleccionada': carpetaSeleccionada,
    'codigoCaja': codigoCaja,
    'botonAudioId': botonAudioId,
    'audiosPersonalizados': audiosPersonalizados.map((a) => a.toJson()).toList(),
  };

  try {
    final archivo = await _obtenerArchivoPermanente();
    await archivo.writeAsString(jsonEncode(mapa), flush: true);
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('nombrePersona', nombrePersona);
  await prefs.setInt('carpetaSeleccionada', carpetaSeleccionada);
  await prefs.setString('codigoCaja', codigoCaja);
  for (int i = 0; i < 10; i++) {
    await prefs.setInt('btn_id_$i', botonAudioId[i]);
  }
  await prefs.setStringList(
    'audios_grabados_v2',
    audiosPersonalizados.map((a) => jsonEncode(a.toJson())).toList(),
  );
}

// ================= SERVICIO 24/7 QUE CORRE CON LA APLICACIÓN CERRADA =================
@pragma('vm:entry-point')
void servicioSegundoPlanoComFred(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin notificaciones = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notificaciones.initialize(const InitializationSettings(android: androidInit));

  final FlutterTts tts = FlutterTts();
  final AudioPlayer reproductor = AudioPlayer();

  try {
    await tts.setEngine("com.google.android.tts");
  } catch (_) {}
  await tts.setLanguage("es-MX");
  await tts.setVolume(1.0);

  bool appEnPrimerPlano = false;
  MqttServerClient? mqttBg;
  DateTime ultimoEventoBg = DateTime.fromMillisecondsSinceEpoch(0);

  service.on('estado_ui').listen((event) {
    if (event != null && event['abierta'] != null) {
      appEnPrimerPlano = event['abierta'] == true;
    }
  });

  Future<void> hablarEnSegundoPlano(int idAudio, int genero, List<AudioPersonalizado> personalizados) async {
    await reproductor.stop();
    await tts.stop();
    await reproductor.setVolume(1.0);
    await tts.setVolume(1.0);

    if (idAudio >= 101) {
      final coincidencia = personalizados.where((a) => a.id == idAudio).toList();
      if (coincidencia.isNotEmpty) {
        final item = coincidencia.first;
        if (!item.esTextoEscrito && item.rutaArchivo.isNotEmpty && File(item.rutaArchivo).existsSync()) {
          await reproductor.play(DeviceFileSource(item.rutaArchivo));
          return;
        }
        await tts.setPitch(genero == 1 ? 0.78 : 1.25);
        await tts.setSpeechRate(0.48);
        await tts.speak(item.titulo);
        return;
      }
    }

    if (idAudio >= 1 && idAudio < frasesMemoria.length) {
      await tts.setPitch(genero == 1 ? 0.78 : 1.25);
      await tts.setSpeechRate(0.48);
      await tts.speak(frasesMemoria[idAudio]);
    }
  }

  Future<void> conectarMqttSegundoPlano() async {
    if (mqttBg != null && mqttBg!.connectionStatus?.state == MqttConnectionState.connected) {
      return;
    }

    final config = await leerConfiguracionPermanente();
    final String codigoCaja = (config['codigoCaja'] ?? "COMFRED_CRISTIAN_01").toString().trim();

    try {
      mqttBg?.disconnect();
    } catch (_) {}

    final clientId = 'ComFredBG_${DateTime.now().millisecondsSinceEpoch}';
    mqttBg = MqttServerClient('broker.emqx.io', clientId);
    mqttBg!.port = 1883;
    mqttBg!.keepAlivePeriod = 30;
    mqttBg!.autoReconnect = true;
    mqttBg!.setProtocolV311();
    mqttBg!.logging(on: false);

    mqttBg!.onConnected = () {
      mqttBg!.subscribe('$codigoCaja/evento', MqttQos.atLeastOnce);
      mqttBg!.subscribe('$codigoCaja/bateria', MqttQos.atLeastOnce);
    };

    try {
      await mqttBg!.connect();
      mqttBg!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? eventos) async {
        if (eventos == null || eventos.isEmpty) return;

        // Si la pantalla de la app está cerrada o en segundo plano, este servicio procesa todo:
        if (appEnPrimerPlano) return;

        final topico = eventos[0].topic;
        final recMess = eventos[0].payload as MqttPublishMessage;
        final payloadTexto = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

        if (topico.endsWith('/evento')) {
          final ahora = DateTime.now();
          if (ahora.difference(ultimoEventoBg).inMilliseconds < 800) return;
          ultimoEventoBg = ahora;

          try {
            final data = jsonDecode(payloadTexto);
            int numBoton = int.tryParse(data['boton'].toString()) ?? 1;
            if (numBoton < 1 || numBoton > 10) numBoton = 1;

            // Lee los datos guardados en disco para respetar el nombre y los audios personalizados
            final cfgActual = await leerConfiguracionPermanente();
            final String nombreGuardado = (cfgActual['nombrePersona'] ?? "").toString().trim();
            final String tituloAlerta = nombreGuardado.isEmpty ? "COM-FRED" : nombreGuardado;
            final int genero = (cfgActual['carpetaSeleccionada'] ?? 1) as int;

            List<int> botonesIds = List<int>.from(cfgActual['botonAudioId'] ?? [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
            List<AudioPersonalizado> listaAudios = (cfgActual['audiosPersonalizados'] as List? ?? [])
                .map((e) => AudioPersonalizado.fromJson(Map<String, dynamic>.from(e)))
                .toList();

            int idAudio = botonesIds[numBoton - 1];
            String fraseTexto = "Audio #$idAudio";
            if (idAudio >= 1 && idAudio < frasesMemoria.length) {
              fraseTexto = frasesMemoria[idAudio];
            } else {
              final enc = listaAudios.where((a) => a.id == idAudio).toList();
              if (enc.isNotEmpty) fraseTexto = enc.first.titulo;
            }

            const detallesAndroid = AndroidNotificationDetails(
              'canal_comfred_urgente',
              'Alertas COM-FRED',
              channelDescription: 'Notificaciones sonoras con la app cerrada',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              fullScreenIntent: true,
            );
            await notificaciones.show(
              DateTime.now().millisecond,
              "🚨 $tituloAlerta",
              fraseTexto,
              const NotificationDetails(android: detallesAndroid),
            );

            await hablarEnSegundoPlano(idAudio, genero, listaAudios);
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  // Conecta al arrancar y verifica cada 15 segundos que nunca se desconecte
  await conectarMqttSegundoPlano();
  Timer.periodic(const Duration(seconds: 15), (_) async {
    await conectarMqttSegundoPlano();
  });
}

Future<void> inicializarServicioPermanente() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'canal_servicio_permanente',
    'Monitoreo Continuo COM-FRED',
    description: 'Mantiene la conexión automática las 24 horas',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: servicioSegundoPlanoComFred,
      autoStart: true,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: 'canal_servicio_permanente',
      initialNotificationTitle: 'COM-FRED Activo',
      initialNotificationContent: 'Conectado automáticamente para recibir alertas 24/7',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: servicioSegundoPlanoComFred,
    ),
  );

  await service.startService();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await inicializarServicioPermanente();
  runApp(const ComFredApp());
}

class ComFredApp extends StatelessWidget {
  const ComFredApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'COM-FRED',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: false),
      home: const PantallaComFred(),
    );
  }
}

class AudioPersonalizado {
  final int id;
  final String titulo;
  final String rutaArchivo;
  final bool esTextoEscrito;

  AudioPersonalizado({
    required this.id,
    required this.titulo,
    required this.rutaArchivo,
    required this.esTextoEscrito,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'ruta': rutaArchivo,
        'esTexto': esTextoEscrito,
      };

  factory AudioPersonalizado.fromJson(Map<String, dynamic> j) => AudioPersonalizado(
        id: j['id'] ?? 101,
        titulo: j['titulo'] ?? '',
        rutaArchivo: j['ruta'] ?? '',
        esTextoEscrito: j['esTexto'] ?? (j['ruta'] == null || j['ruta'].toString().isEmpty),
      );
}

class PantallaComFred extends StatefulWidget {
  const PantallaComFred({super.key});

  @override
  State<PantallaComFred> createState() => _PantallaComFredState();
}

class _PantallaComFredState extends State<PantallaComFred> with WidgetsBindingObserver {
  int _pestanaActual = 0;
  String _textoBusqueda = "";

  String _nombrePersona = "";
  final TextEditingController _ctrlNombrePersona = TextEditingController();

  int _carpetaSeleccionada = 1;

  Map<String, String>? _vozMasculinaSistema;
  Map<String, String>? _vozFemeninaSistema;

  int? _porcentajeBateria;
  bool _alertaBateriaBajaEnviada = false;

  List<int> _botonAudioId = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  List<int> _botonCarpeta = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1];

  List<AudioPersonalizado> _audiosPersonalizados = [];

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _reproductor = AudioPlayer();
  final AudioRecorder _grabadora = AudioRecorder();
  final FlutterLocalNotificationsPlugin _notificaciones = FlutterLocalNotificationsPlugin();

  bool _grabandoAhora = false;
  final TextEditingController _ctrlNombreGrabacion = TextEditingController();
  final TextEditingController _ctrlCodigoCaja = TextEditingController(text: "COMFRED_CRISTIAN_01");

  final TextEditingController _ctrlWifiSsid = TextEditingController();
  final TextEditingController _ctrlWifiPass = TextEditingController();

  MqttServerClient? _mqttClient;
  bool _appConectadaANube = false;
  bool _cajaTieneInternet = false;
  String _estadoInternetCaja = "Verificando conexión a Internet de la botonera...";
  Timer? _timerReconexionAutomatica;

  BluetoothDevice? _dispositivoBle;
  BluetoothCharacteristic? _bleWriteChar;
  StreamSubscription? _scanSubscription;
  bool _bleConectado = false;
  bool _buscandoBle = false;

  String _estadoUltimoEvento = "Listo para recibir alertas por Internet o Bluetooth";
  DateTime _ultimoDisparoVoz = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FlutterBackgroundService().invoke('estado_ui', {'abierta': true});
    _iniciarServicios();
  }

  @override
  void dispose() {
    FlutterBackgroundService().invoke('estado_ui', {'abierta': false});
    _timerReconexionAutomatica?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FlutterBackgroundService().invoke('estado_ui', {'abierta': true});
      _cargarDatosGuardados();
      if (!_appConectadaANube) _conectarNubeMQTT();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      // Al minimizar o cerrar la app, el servicio 24/7 toma el control inmediato
      FlutterBackgroundService().invoke('estado_ui', {'abierta': false});
    }
  }

  Future<void> _iniciarServicios() async {
    await _cargarDatosGuardados();

    await [
      Permission.notification,
      Permission.microphone,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.ignoreBatteryOptimizations,
    ].request();

    await _iniciarNotificaciones();
    await _iniciarMotorVozYGeneros();

    // 1. Conecta automáticamente por Internet
    _conectarNubeMQTT();

    // 2. Intenta conectar automáticamente por Bluetooth por si no hubiera Internet
    _conectarBluetoothBLE();

    // 3. Vigilante automático: si se cae el internet del teléfono, reconecta solo cada 10s
    _timerReconexionAutomatica = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_appConectadaANube ||
          _mqttClient?.connectionStatus?.state != MqttConnectionState.connected) {
        _conectarNubeMQTT();
      }
    });
  }

  Future<void> _iniciarNotificaciones() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _notificaciones.initialize(settings);
  }

  Future<void> _lanzarNotificacion(String titulo, String mensaje) async {
    const detallesAndroid = AndroidNotificationDetails(
      'canal_comfred_urgente',
      'Alertas COM-FRED',
      channelDescription: 'Notificaciones sonoras cuando se presiona un botón físico',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
    );
    await _notificaciones.show(
      DateTime.now().millisecond,
      titulo,
      mensaje,
      const NotificationDetails(android: detallesAndroid),
    );
  }

  Future<void> _iniciarMotorVozYGeneros() async {
    try {
      await _tts.setEngine("com.google.android.tts");
    } catch (_) {}

    await _tts.setLanguage("es-MX");
    await _tts.setVolume(1.0);

    try {
      final dynamic vocesRaw = await _tts.getVoices;
      if (vocesRaw is List) {
        List<Map<String, String>> vocesEsp = [];
        for (var v in vocesRaw) {
          if (v is Map) {
            String name = (v['name'] ?? '').toString();
            String locale = (v['locale'] ?? '').toString();
            if (locale.toLowerCase().startsWith('es')) {
              vocesEsp.add({'name': name, 'locale': locale});
            }
          }
        }

        for (var v in vocesEsp) {
          String n = v['name']!.toLowerCase();
          if (n.contains('sfd') ||
              n.contains('eef') ||
              n.contains('eed') ||
              n.contains('esc') ||
              (n.contains('male') && !n.contains('female'))) {
            _vozMasculinaSistema = v;
            if (v['locale']!.toLowerCase().contains('mx') || v['locale']!.toLowerCase().contains('us')) {
              break;
            }
          }
        }

        for (var v in vocesEsp) {
          String n = v['name']!.toLowerCase();
          if (n.contains('sfb') ||
              n.contains('eea') ||
              n.contains('eec') ||
              n.contains('female')) {
            _vozFemeninaSistema = v;
            if (v['locale']!.toLowerCase().contains('mx') || v['locale']!.toLowerCase().contains('us')) {
              break;
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _aplicarVozPorGenero(int genero) async {
    await _tts.setVolume(1.0);

    if (genero == 1) {
      if (_vozMasculinaSistema != null) {
        await _tts.setVoice(_vozMasculinaSistema!);
        await _tts.setPitch(0.85);
        await _tts.setSpeechRate(0.48);
      } else {
        await _tts.setLanguage("es-US");
        await _tts.setPitch(0.60);
        await _tts.setSpeechRate(0.46);
      }
    } else {
      if (_vozFemeninaSistema != null) {
        await _tts.setVoice(_vozFemeninaSistema!);
        await _tts.setPitch(1.10);
        await _tts.setSpeechRate(0.50);
      } else {
        await _tts.setLanguage("es-MX");
        await _tts.setPitch(1.35);
        await _tts.setSpeechRate(0.50);
      }
    }
  }

  void _actualizarNivelBateria(dynamic valor) {
    if (valor == null) return;
    int? nuevoNivel = int.tryParse(valor.toString());
    if (nuevoNivel == null) return;
    nuevoNivel = nuevoNivel.clamp(0, 100);

    if (mounted) {
      setState(() => _porcentajeBateria = nuevoNivel);
    }

    if (nuevoNivel <= 15 && !_alertaBateriaBajaEnviada) {
      _alertaBateriaBajaEnviada = true;
      String nombreActual = _obtenerNombreAMostrar();
      _lanzarNotificacion(
        "⚠️ Batería Baja: $nombreActual",
        "El dispositivo tiene $nuevoNivel% de batería. Conéctalo a cargar.",
      );
    } else if (nuevoNivel > 20) {
      _alertaBateriaBajaEnviada = false;
    }
  }

  String _obtenerNombreAMostrar() {
    return _nombrePersona.trim().isEmpty ? "COM-FRED" : _nombrePersona.trim();
  }

  void _procesarBotonRecibido(int numBoton, String origen) {
    final ahora = DateTime.now();
    if (origen != "Tablero App" && ahora.difference(_ultimoDisparoVoz).inMilliseconds < 800) return;
    _ultimoDisparoVoz = ahora;

    if (numBoton < 1 || numBoton > 10) numBoton = 1;

    int idAudio = _botonAudioId[numBoton - 1];
    int generoReproduccion = _carpetaSeleccionada;
    String textoFrase = _obtenerTextoPorId(idAudio);
    String nombreActual = _obtenerNombreAMostrar();

    if (mounted) {
      setState(() {
        _estadoUltimoEvento = "$nombreActual: \"$textoFrase\"";
      });
    }

    _lanzarNotificacion("🚨 $nombreActual", textoFrase);
    _reproducirAudioEnMovilYAltavoz(idAudio, generoReproduccion);
  }

  Future<void> _reproducirAudioEnMovilYAltavoz(int idAudio, int genero) async {
    await _reproductor.stop();
    await _tts.stop();
    await _reproductor.setVolume(1.0);

    String fraseParaAltavoz = _obtenerTextoPorId(idAudio);

    if (_mqttClient != null && _appConectadaANube) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode({
        'id': idAudio,
        'texto': fraseParaAltavoz,
        'persona': _obtenerNombreAMostrar(),
        'genero': genero == 1 ? 'hombre' : 'mujer',
      }));
      _mqttClient!.publishMessage(
        '${_ctrlCodigoCaja.text.trim()}/altavoz',
        MqttQos.atLeastOnce,
        builder.payload!,
      );
    }

    if (idAudio >= 101) {
      final coincidencia = _audiosPersonalizados.where((a) => a.id == idAudio).toList();
      if (coincidencia.isNotEmpty) {
        final item = coincidencia.first;
        if (!item.esTextoEscrito && item.rutaArchivo.isNotEmpty && File(item.rutaArchivo).existsSync()) {
          await _reproductor.play(DeviceFileSource(item.rutaArchivo));
          return;
        }
        await _aplicarVozPorGenero(_carpetaSeleccionada);
        await _tts.speak(item.titulo);
        return;
      }
    }

    if (idAudio >= 1 && idAudio < frasesMemoria.length) {
      String frase = frasesMemoria[idAudio];
      await _aplicarVozPorGenero(_carpetaSeleccionada);
      await _tts.speak(frase);
    }
  }

  void _enviarComandoAlESP32(String cmd) {
    if (_mqttClient != null && _appConectadaANube) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(cmd);
      _mqttClient!.publishMessage(
        '${_ctrlCodigoCaja.text.trim()}/config',
        MqttQos.atLeastOnce,
        builder.payload!,
      );
    }
    if (_bleConectado) {
      _enviarComandoBLE(cmd);
    }
  }

  Future<void> _conectarNubeMQTT() async {
    if (_mqttClient != null &&
        _mqttClient!.connectionStatus?.state == MqttConnectionState.connected) {
      if (mounted) setState(() => _appConectadaANube = true);
      return;
    }

    try {
      _mqttClient?.disconnect();
    } catch (_) {}

    final clientId = 'ComFredUI_${DateTime.now().millisecondsSinceEpoch}';
    _mqttClient = MqttServerClient('broker.emqx.io', clientId);
    _mqttClient!.port = 1883;
    _mqttClient!.keepAlivePeriod = 30;
    _mqttClient!.autoReconnect = true;
    _mqttClient!.setProtocolV311();
    _mqttClient!.logging(on: false);

    _mqttClient!.onConnected = () {
      if (mounted) setState(() => _appConectadaANube = true);
      final base = _ctrlCodigoCaja.text.trim();
      _mqttClient!.subscribe('$base/evento', MqttQos.atLeastOnce);
      _mqttClient!.subscribe('$base/estado_wifi', MqttQos.atLeastOnce);
      _mqttClient!.subscribe('$base/bateria', MqttQos.atLeastOnce);

      _enviarComandoAlESP32("STATUS?");
    };

    _mqttClient!.onDisconnected = () {
      if (mounted) setState(() => _appConectadaANube = false);
    };

    try {
      await _mqttClient!.connect();
      _mqttClient!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? eventos) {
        if (eventos == null || eventos.isEmpty) return;
        final topico = eventos[0].topic;
        final recMess = eventos[0].payload as MqttPublishMessage;
        final payloadTexto = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

        if (topico.endsWith('/bateria')) {
          _actualizarNivelBateria(payloadTexto);
        } else if (topico.endsWith('/evento')) {
          try {
            final data = jsonDecode(payloadTexto);
            if (data['bateria'] != null) _actualizarNivelBateria(data['bateria']);
            int numBoton = int.tryParse(data['boton'].toString()) ?? 1;
            _procesarBotonRecibido(numBoton, "Internet");
          } catch (_) {}
        } else if (topico.endsWith('/estado_wifi')) {
          try {
            final data = jsonDecode(payloadTexto);
            if (data['bateria'] != null) _actualizarNivelBateria(data['bateria']);
            bool conectado = data['online'] == true;
            String ssid = data['ssid'] ?? "";
            String mensaje = data['msg'] ?? "Desconectado";
            if (mounted) {
              setState(() {
                _cajaTieneInternet = conectado;
                if (conectado) {
                  _estadoInternetCaja = "BOTONERA CONECTADA A INTERNET\nRed: $ssid";
                } else {
                  _estadoInternetCaja = "SIN INTERNET ($mensaje)\nRespaldo Bluetooth Activo";
                }
              });
            }
          } catch (_) {}
        }
      });
    } catch (_) {
      if (mounted) setState(() => _appConectadaANube = false);
    }
  }

  Future<void> _conectarBluetoothBLE() async {
    if (_bleConectado || _buscandoBle) return;
    setState(() => _buscandoBle = true);
    try {
      await _scanSubscription?.cancel();
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          if (r.device.platformName == "COM-FRED-BLE" ||
              r.advertisementData.advName == "COM-FRED-BLE") {
            await FlutterBluePlus.stopScan();
            _dispositivoBle = r.device;
            await _dispositivoBle!.connect(autoConnect: false);

            if (Platform.isAndroid) {
              try {
                await _dispositivoBle!.requestMtu(256);
              } catch (_) {}
            }

            _dispositivoBle!.connectionState.listen((state) {
              if (mounted) {
                setState(() => _bleConectado = (state == BluetoothConnectionState.connected));
              }
            });

            List<BluetoothService> services = await _dispositivoBle!.discoverServices();
            for (var s in services) {
              if (s.uuid.toString().toLowerCase() == kServiceUuid) {
                for (var c in s.characteristics) {
                  String uuid = c.uuid.toString().toLowerCase();
                  if (uuid == kCharWriteUuid) {
                    _bleWriteChar = c;
                  } else if (uuid == kCharNotifyUuid) {
                    await c.setNotifyValue(true);
                    c.onValueReceived.listen((value) {
                      String jsonStr = utf8.decode(value);
                      _procesarMensajeBLE(jsonStr);
                    });
                  }
                }
              }
            }
            await _enviarComandoBLE("GEN:$_carpetaSeleccionada");
            await _enviarComandoBLE("STATUS?");
            break;
          }
        }
      });
    } catch (_) {}
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) setState(() => _buscandoBle = false);
    });
  }

  void _procesarMensajeBLE(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      if (data['bateria'] != null) {
        _actualizarNivelBateria(data['bateria']);
      }

      if (data['tipo'] == 'boton') {
        int b = int.tryParse(data['boton'].toString()) ?? 1;
        _procesarBotonRecibido(b, "Bluetooth");
      } else if (data['tipo'] == 'wifi') {
        bool conectado = data['conectado'] == true;
        String ssid = data['ssid'] ?? "";
        String mensaje = data['msg'] ?? "";

        if (mounted) {
          setState(() {
            _cajaTieneInternet = conectado;
            if (conectado) {
              _estadoInternetCaja = "BOTONERA CONECTADA A INTERNET\nRed: $ssid";
            } else {
              _estadoInternetCaja = "SIN INTERNET ($mensaje)\nRespaldo Bluetooth Activo";
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _enviarComandoBLE(String cmd) async {
    if (_bleConectado && _bleWriteChar != null) {
      try {
        await _bleWriteChar!.write(utf8.encode(cmd), withoutResponse: false);
      } catch (_) {}
    }
  }

  Future<void> _cambiarRedWifiDelDispositivo() async {
    String ssid = _ctrlWifiSsid.text.trim();
    String pass = _ctrlWifiPass.text.trim();
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Escribe el nombre de la red Wi-Fi (SSID)")),
      );
      return;
    }

    setState(() {
      _estadoInternetCaja = "⏳ Conectando botonera a la red '$ssid'...\nEspera unos 10 segundos.";
    });

    String comando = "WIFI:$ssid|$pass";

    if (_appConectadaANube || _bleConectado) {
      _enviarComandoAlESP32(comando);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nueva red Wi-Fi enviada al dispositivo.")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Conéctate por Internet o por Bluetooth para enviar la nueva red.")),
      );
    }
  }

  String _obtenerTextoPorId(int id) {
    if (id >= 1 && id < frasesMemoria.length) return frasesMemoria[id];
    final encontrado = _audiosPersonalizados.where((a) => a.id == id).toList();
    if (encontrado.isNotEmpty) return encontrado.first.titulo;
    return "Audio #$id";
  }

  // Carga los datos desde el archivo permanente en disco
  Future<void> _cargarDatosGuardados() async {
    final cfg = await leerConfiguracionPermanente();
    final List<AudioPersonalizado> cargados = (cfg['audiosPersonalizados'] as List? ?? [])
        .map((e) => AudioPersonalizado.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final List<int> botones = List<int>.from(cfg['botonAudioId'] ?? [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

    if (mounted) {
      setState(() {
        _nombrePersona = (cfg['nombrePersona'] ?? "").toString();
        if (_ctrlNombrePersona.text != _nombrePersona) {
          _ctrlNombrePersona.text = _nombrePersona;
        }
        _carpetaSeleccionada = (cfg['carpetaSeleccionada'] ?? 1) as int;
        _ctrlCodigoCaja.text = (cfg['codigoCaja'] ?? "COMFRED_CRISTIAN_01").toString();
        _audiosPersonalizados = cargados;
        _botonAudioId = botones;
      });
    }
  }

  Future<void> _sincronizarTodoEnDisco() async {
    await guardarConfiguracionPermanente(
      nombrePersona: _nombrePersona,
      carpetaSeleccionada: _carpetaSeleccionada,
      codigoCaja: _ctrlCodigoCaja.text.trim(),
      botonAudioId: _botonAudioId,
      audiosPersonalizados: _audiosPersonalizados,
    );
  }

  Future<void> _guardarNombrePersona(String valor) async {
    setState(() {
      _nombrePersona = valor.trim();
    });
    await _sincronizarTodoEnDisco();
  }

  int _calcularSiguienteIdDisponible() {
    int maxId = 100;
    for (var a in _audiosPersonalizados) {
      if (a.id > maxId) maxId = a.id;
    }
    return maxId + 1;
  }

  Future<void> _guardarFraseSoloEscrita() async {
    final texto = _ctrlNombreGrabacion.text.trim();
    if (texto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Escribe primero la frase que deseas agregar")),
      );
      return;
    }

    final nuevoId = _calcularSiguienteIdDisponible();
    final nuevoAudio = AudioPersonalizado(
      id: nuevoId,
      titulo: texto,
      rutaArchivo: "",
      esTextoEscrito: true,
    );

    setState(() {
      _audiosPersonalizados.add(nuevoAudio);
      _ctrlNombreGrabacion.clear();
    });

    await _sincronizarTodoEnDisco();
    _reproducirAudioEnMovilYAltavoz(nuevoId, _carpetaSeleccionada);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Frase guardada permanentemente en memoria")),
      );
    }
  }

  Future<void> _alternarGrabacionVoz() async {
    if (!_grabandoAhora) {
      if (_ctrlNombreGrabacion.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Escribe primero el nombre o frase del audio a grabar")),
        );
        return;
      }
      if (await _grabadora.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final nuevoId = _calcularSiguienteIdDisponible();
        final ruta = '${dir.path}/audio_extra_$nuevoId.m4a';

        await _grabadora.start(const RecordConfig(), path: ruta);
        setState(() => _grabandoAhora = true);
      }
    } else {
      final rutaFinal = await _grabadora.stop();
      setState(() => _grabandoAhora = false);

      if (rutaFinal != null) {
        final nuevoId = _calcularSiguienteIdDisponible();
        final nuevo = AudioPersonalizado(
          id: nuevoId,
          titulo: _controladorTextoSeguro(_ctrlNombreGrabacion.text),
          rutaArchivo: rutaFinal,
          esTextoEscrito: false,
        );
        setState(() {
          _audiosPersonalizados.add(nuevo);
          _ctrlNombreGrabacion.clear();
        });
        await _sincronizarTodoEnDisco();
        _reproducirAudioEnMovilYAltavoz(nuevoId, 3);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("🎙️ Audio grabado y guardado permanentemente")),
          );
        }
      }
    }
  }

  Future<void> _asignarAudioABotonFisico(int numeroBoton1a10, int idAudio, int carpeta) async {
    int idx = numeroBoton1a10 - 1;

    setState(() {
      _botonAudioId[idx] = idAudio;
      _botonCarpeta[idx] = carpeta;
      _estadoUltimoEvento = "${_obtenerNombreAMostrar()}: \"${_obtenerTextoPorId(idAudio)}\"";
    });

    await _sincronizarTodoEnDisco();
    _reproducirAudioEnMovilYAltavoz(idAudio, _carpetaSeleccionada);
    _enviarComandoAlESP32("MAP:$numeroBoton1a10=$idAudio,$_carpetaSeleccionada");
  }

  Widget _construirRectanguloBotonesAmarillos({required Function(int numeroBoton) alPresionarBoton}) {
    final filaArriba = [6, 7, 8, 9, 10];
    final filaAbajo = [1, 2, 3, 4, 5];

    Widget construirBotonAmarillo(int numBoton) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFEB3B),
                foregroundColor: Colors.black,
                elevation: 4,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFFBC02D), width: 2.5),
                ),
              ),
              onPressed: () => alPresionarBoton(numBoton),
              child: Text(
                "$numBoton",
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF37474F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black54, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: filaArriba.map((n) => construirBotonAmarillo(n)).toList()),
          const SizedBox(height: 10),
          Row(children: filaAbajo.map((n) => construirBotonAmarillo(n)).toList()),
        ],
      ),
    );
  }

  void _abrirSelectorDeBoton(int idAudio, String frase, int carpeta) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Toca el botón (1 al 10) para guardar:\n#$idAudio: \"$frase\"",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _construirRectanguloBotonesAmarillos(
                alPresionarBoton: (numBoton) {
                  Navigator.pop(ctx);
                  _asignarAudioABotonFisico(numBoton, idAudio, carpeta);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("✅ Guardado permanentemente en el botón $numBoton"),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  String _controladorTextoSeguro(String t) => t.trim().isEmpty ? "Grabación" : t.trim();

  Widget _construirIndicadorBateria() {
    final int nivel = _porcentajeBateria ?? -1;
    Color colorBat = Colors.blueGrey;
    IconData iconoBat = Icons.battery_unknown;

    if (nivel >= 0) {
      if (nivel > 50) {
        colorBat = Colors.green.shade700;
        iconoBat = Icons.battery_full;
      } else if (nivel > 20) {
        colorBat = Colors.orange.shade800;
        iconoBat = Icons.battery_3_bar;
      } else {
        colorBat = Colors.red.shade700;
        iconoBat = Icons.battery_alert;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorBat.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorBat, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconoBat, size: 18, color: colorBat),
          const SizedBox(width: 4),
          Text(
            nivel >= 0 ? "$nivel%" : "--%",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: colorBat),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color colorFondoDinamico = _carpetaSeleccionada == 2
        ? const Color(0xFFF8BBD0) // Rosa
        : const Color(0xFFAEEEEE); // Azul Menta

    final String nombreParaTitulo = _obtenerNombreAMostrar();

    return Scaffold(
      backgroundColor: colorFondoDinamico,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10.0, bottom: 4.0, left: 16.0, right: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 68),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("🤖 ", style: TextStyle(fontSize: 22)),
                        Flexible(
                          child: Text(
                            nombreParaTitulo,
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                              color: _carpetaSeleccionada == 2 ? const Color(0xFFC2185B) : const Color(0xFFF06292),
                              letterSpacing: 1.1,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Text(" 🐻", style: TextStyle(fontSize: 22)),
                      ],
                    ),
                  ),
                  _construirIndicadorBateria(),
                ],
              ),
            ),

            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.94),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.public,
                            size: 15,
                            color: _appConectadaANube ? Colors.green.shade700 : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _appConectadaANube
                                ? (_cajaTieneInternet ? "Internet: En Línea (24/7)" : "Internet: Automático 24/7")
                                : "Reconectando...",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _appConectadaANube ? Colors.green.shade800 : Colors.orange.shade900,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.bluetooth,
                            size: 15,
                            color: _bleConectado ? Colors.blue.shade700 : Colors.grey,
                          ),
                          Text(
                            _bleConectado ? "BT: Activo" : "BT: Respaldo",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _bleConectado ? Colors.blue.shade800 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _porcentajeBateria != null ? "🔋 ${_porcentajeBateria!}%" : "🔋 --%",
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.black87),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _estadoUltimoEvento,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            Expanded(
              child: IndexedStack(
                index: _pestanaActual,
                children: [
                  _vistaCatalogoPrototipo(),
                  _vistaTableroAmarillo(),
                  _vistaGrabarOEscribirAudio(),
                  _vistaRedYBluetooth(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _pestanaActual,
        onTap: (index) => setState(() => _pestanaActual = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: _carpetaSeleccionada == 2 ? const Color(0xFFD81B60) : const Color(0xFF0288D1),
        unselectedItemColor: Colors.black54,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.queue_music), label: "Catálogo"),
          BottomNavigationBarItem(icon: Icon(Icons.grid_on_rounded), label: "Tablero 1-10"),
          BottomNavigationBarItem(icon: Icon(Icons.mic_external_on), label: "Grabar Nuevo"),
          BottomNavigationBarItem(icon: Icon(Icons.cloud_sync), label: "Internet / BLE"),
        ],
      ),
    );
  }

  Widget _vistaCatalogoPrototipo() {
    List<Map<String, dynamic>> itemsFiltrados = [];

    for (var g in _audiosPersonalizados.reversed) {
      if (g.titulo.toLowerCase().contains(_textoBusqueda.toLowerCase()) ||
          g.id.toString().contains(_textoBusqueda)) {
        String sufijo = g.esTextoEscrito ? "✍️ Escrito" : "🎙️ Grabado";
        itemsFiltrados.add({
          'id': g.id,
          'texto': "${g.titulo} ($sufijo)",
          'fraseLimpia': g.titulo,
          'carpeta': 3,
        });
      }
    }

    for (int i = 1; i < frasesMemoria.length; i++) {
      final frase = frasesMemoria[i];
      if (frase.toLowerCase().contains(_textoBusqueda.toLowerCase()) ||
          i.toString().contains(_textoBusqueda)) {
        itemsFiltrados.add({
          'id': i,
          'texto': frase,
          'fraseLimpia': frase,
          'carpeta': _carpetaSeleccionada,
        });
      }
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFFB74D), width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text("👨 Voz Hombre", style: TextStyle(fontWeight: FontWeight.bold)),
                      selected: _carpetaSeleccionada == 1,
                      selectedColor: const Color(0xFFAEEEEE),
                      onSelected: (_) async {
                        setState(() {
                          _carpetaSeleccionada = 1;
                          for (int i = 0; i < 10; i++) {
                            if (_botonAudioId[i] <= 100) _botonCarpeta[i] = 1;
                          }
                        });
                        await _sincronizarTodoEnDisco();
                        _enviarComandoAlESP32("GEN:1");
                        _reproducirAudioEnMovilYAltavoz(1, 1);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text("👩 Voz Mujer", style: TextStyle(fontWeight: FontWeight.bold)),
                      selected: _carpetaSeleccionada == 2,
                      selectedColor: const Color(0xFFF48FB1),
                      onSelected: (_) async {
                        setState(() {
                          _carpetaSeleccionada = 2;
                          for (int i = 0; i < 10; i++) {
                            if (_botonAudioId[i] <= 100) _botonCarpeta[i] = 2;
                          }
                        });
                        await _sincronizarTodoEnDisco();
                        _enviarComandoAlESP32("GEN:2");
                        _reproducirAudioEnMovilYAltavoz(1, 2);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (valor) => setState(() => _textoBusqueda = valor),
                decoration: InputDecoration(
                  hintText: "🔍 Busca una frase aquí...",
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(color: Color(0xFF42A5F5), width: 1.8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(color: Color(0xFF1E88E5), width: 2.2),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: itemsFiltrados.length,
            itemBuilder: (context, index) {
              final item = itemsFiltrados[index];
              final int id = item['id'];
              final String texto = item['texto'];
              final String fraseLimpia = item['fraseLimpia'];
              final int carpeta = item['carpeta'];

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "🎵 #$id: $texto",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF263238)),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _carpetaSeleccionada == 2
                              ? const Color(0xFFF48FB1)
                              : const Color(0xFF64B5F6),
                          foregroundColor: Colors.black87,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => _abrirSelectorDeBoton(id, fraseLimpia, carpeta),
                        child: const Text(
                          "Añadir a Botón ↓",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _vistaTableroAmarillo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                const Text(
                  "Disposición de la Caja",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Toca cualquier botón amarillo (1 al 10) para escuchar su frase asignada.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                _construirRectanguloBotonesAmarillos(
                  alPresionarBoton: (numBoton) {
                    _procesarBotonRecibido(numBoton, "Tablero App");
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(10, (i) {
            int numBoton = i + 1;
            int idAudio = _botonAudioId[i];

            return InkWell(
              onTap: () => _procesarBotonRecibido(numBoton, "Tablero App"),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEB3B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFBC02D), width: 2),
                      ),
                      child: Text("$numBoton", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "#$idAudio: ${_obtenerTextoPorId(idAudio)}",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.volume_up_rounded, color: Colors.blueGrey),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _vistaGrabarOEscribirAudio() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                const Text(
                  "Agregar Nuevo Audio",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Escribe la frase y guárdala con voz automática o grábala con tu micrófono. Quedan guardados permanentemente aunque cierres la app.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrlNombreGrabacion,
                  decoration: InputDecoration(
                    labelText: "Escribe aquí la frase que deseas agregar...",
                    prefixIcon: const Icon(Icons.edit_note),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFEB3B),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _grabandoAhora ? null : _guardarFraseSoloEscrita,
                    icon: const Icon(Icons.speaker_notes),
                    label: const Text(
                      "✍️ Guardar Frase Escrita (Voz Automática)",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _grabandoAhora ? Colors.redAccent : const Color(0xFF64B5F6),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _alternarGrabacionVoz,
                    icon: Icon(_grabandoAhora ? Icons.stop_circle : Icons.mic),
                    label: Text(
                      _grabandoAhora ? "⏹️ Detener y Guardar Grabación" : "🎙️ Grabar con mi Voz (Micrófono)",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _audiosPersonalizados.isEmpty
                ? const Center(child: Text("Aún no has agregado frases nuevas (#101+)."))
                : ListView.builder(
                    itemCount: _audiosPersonalizados.length,
                    itemBuilder: (ctx, i) {
                      final audio = _audiosPersonalizados[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: IconButton(
                            icon: Icon(
                              audio.esTextoEscrito ? Icons.volume_up : Icons.play_circle_fill,
                              color: Colors.blueAccent,
                              size: 30,
                            ),
                            onPressed: () => _reproducirAudioEnMovilYAltavoz(audio.id, _carpetaSeleccionada),
                          ),
                          title: Text(
                            "#${audio.id}: ${audio.titulo}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            audio.esTextoEscrito ? "Frase Escrita" : "Nota de Voz",
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFEB3B)),
                            onPressed: () => _abrirSelectorDeBoton(audio.id, audio.titulo, 3),
                            child: const Text(
                              "Añadir a Botón ↓",
                              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _vistaRedYBluetooth() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // SECCIÓN 0: NOMBRE DE LA PERSONA CON GUARDADO PERMANENTE
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Nombre de la Persona (Botonera)",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Escribe el nombre de quien usará la botonera. Si lo dejas vacío, se mostrará COM-FRED por defecto.",
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrlNombrePersona,
                  onChanged: (val) => _guardarNombrePersona(val),
                  decoration: InputDecoration(
                    labelText: "Nombre de la persona (Ej: Mamá, Abuelito)",
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFEB3B),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      await _guardarNombrePersona(_ctrlNombrePersona.text);
                      if (mounted) {
                        FocusScope.of(context).unfocus();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("✅ Nombre '${_obtenerNombreAMostrar()}' guardado permanentemente"),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.save),
                    label: const Text(
                      "Guardar Nombre Permanentemente",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // SECCIÓN 1: CONEXIÓN AUTOMÁTICA POR INTERNET
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "1. Conexión por Internet (Automática 24/7)",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "La aplicación se mantiene conectada automáticamente en segundo plano aunque la cierres por completo.",
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _cajaTieneInternet ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _cajaTieneInternet ? Colors.green : Colors.orange.shade800,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    _estadoInternetCaja,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: _cajaTieneInternet ? Colors.green.shade900 : Colors.deepOrange.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // SECCIÓN 2: CAMBIAR RED WI-FI
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "2. Cambiar Red Wi-Fi de la Caja COM-FRED",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Para acceder a internet, ingresa los datos aquí:",
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrlWifiSsid,
                  decoration: InputDecoration(
                    labelText: "Nombre de la Red Wi-Fi (SSID)",
                    prefixIcon: const Icon(Icons.wifi),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _ctrlWifiPass,
                  decoration: InputDecoration(
                    labelText: "Contraseña del Wi-Fi",
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFEB3B),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _cambiarRedWifiDelDispositivo,
                    icon: const Icon(Icons.send_to_mobile),
                    label: const Text(
                      "Guardar y Conectar Caja a esta Red",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // SECCIÓN 3: RESPALDO POR BLUETOOTH
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "3. Respaldo por Bluetooth (Solo si no hay Internet)",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Úsalo únicamente cuando no exista red Wi-Fi o para acceder a la red Wi-Fi",
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _bleConectado ? Colors.green.shade600 : const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _buscandoBle ? null : _conectarBluetoothBLE,
                    icon: Icon(_bleConectado ? Icons.bluetooth_connected : Icons.bluetooth_searching),
                    label: Text(
                      _bleConectado
                          ? "🔵 Respaldo Bluetooth Conectado"
                          : (_buscandoBle ? "Buscando COM-FRED-BLE..." : "Activar Bluetooth (Sin Internet)"),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}