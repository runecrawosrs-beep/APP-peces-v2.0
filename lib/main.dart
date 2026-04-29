import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const AlimentadorApp());
}

class AlimentadorApp extends StatelessWidget {
  const AlimentadorApp({super.key, this.enableAutoConnect = true});

  final bool enableAutoConnect;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alimentador Animal MQTT',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: MqttHomePage(enableAutoConnect: enableAutoConnect),
    );
  }
}

class MqttHomePage extends StatefulWidget {
  const MqttHomePage({super.key, this.enableAutoConnect = true});

  final bool enableAutoConnect;

  @override
  State<MqttHomePage> createState() => _MqttHomePageState();
}

class _MqttHomePageState extends State<MqttHomePage> {
  String _broker = 'broker.emqx.io';
  int _port = 1883;
  String _topic = 'alimentador/tor';
  final String _payloadAlimentar = 'alimentar';

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>?
  _updatesSubscription;
  String _status = 'Conectando...';
  bool _isDisposing = false;
  final List<String> _eventos = <String>[];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _setupClient();
    if (widget.enableAutoConnect) {
      _connect();
    } else {
      _status = 'Listo para conectar';
    }
  }

  void _setupClient() {
    final clientId =
        'flutter_alimentador_${DateTime.now().millisecondsSinceEpoch}';
    _client = MqttServerClient.withPort(_broker, clientId, _port)
      ..keepAlivePeriod = 20
      ..autoReconnect = true
      ..logging(on: false)
      ..onConnected = () {
        if (!mounted || _isDisposing) {
          return;
        }
        _suscribirATopic();
        setState(() {
          _status = 'Conectado a $_broker:$_port';
        });
        _agregarEvento('Conectado al broker');
      }
      ..onDisconnected = () {
        if (!mounted || _isDisposing) {
          return;
        }
        setState(() {
          _status = 'Desconectado';
        });
        _agregarEvento('Conexion cerrada');
      }
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean();
  }

  void _disposeClient() {
    _updatesSubscription?.cancel();
    _updatesSubscription = null;
    _client?.disconnect();
    _client = null;
  }

  Future<void> _connect() async {
    _disposeClient();
    _setupClient();

    try {
      await _client!.connect();
      if (!mounted) {
        return;
      }
      _registrarEscuchaMensajes();
      if (_client!.connectionStatus?.state != MqttConnectionState.connected) {
        setState(() {
          _status = 'No se pudo conectar';
        });
        _agregarEvento('Fallo de conexion');
      }
    } catch (_) {
      _client?.disconnect();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Error de conexion';
      });
      _agregarEvento('Error de conexion al broker');
    }
  }

  void _suscribirATopic() {
    _client?.subscribe(_topic, MqttQos.atLeastOnce);
    _agregarEvento('Suscrito a $_topic');
  }

  void _registrarEscuchaMensajes() {
    _updatesSubscription?.cancel();
    _updatesSubscription = _client?.updates?.listen((messages) {
      if (messages.isEmpty || !mounted || _isDisposing) {
        return;
      }
      final recMess = messages.first.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      final topic = messages.first.topic;
      _agregarEvento('Entrante [$topic]: $payload');
    });
  }

  Future<void> _reconectarManual() async {
    setState(() {
      _status = 'Reconectando...';
    });
    await _connect();
  }

  Future<void> _abrirPanelDesarrollador() async {
    final brokerController = TextEditingController(text: _broker);
    final portController = TextEditingController(text: _port.toString());
    final topicController = TextEditingController(text: _topic);
    String panelMensaje = '';
    Color panelColor = const Color(0xFF1F7A4A);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1B2D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setPanelState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 14,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.78,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Panel de desarrollador',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Estado: $_status',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (panelMensaje.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: panelColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: panelColor),
                          ),
                          child: Text(
                            panelMensaje,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: brokerController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _panelInputDecoration(
                          label: 'Broker',
                          hint: 'broker.emqx.io',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: portController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        decoration: _panelInputDecoration(
                          label: 'Puerto',
                          hint: '1883',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: topicController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _panelInputDecoration(
                          label: 'Topic',
                          hint: 'alimentador/tor',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final broker = brokerController.text.trim();
                                final topic = topicController.text.trim();
                                final port = int.tryParse(
                                  portController.text.trim(),
                                );
                                if (broker.isEmpty ||
                                    topic.isEmpty ||
                                    port == null) {
                                  setPanelState(() {
                                    panelColor = const Color(0xFFB00020);
                                    panelMensaje =
                                        'Datos invalidos. Revisa broker, puerto y topic.';
                                  });
                                  return;
                                }

                                setState(() {
                                  _broker = broker;
                                  _port = port;
                                  _topic = topic;
                                  _status = 'Configuracion guardada';
                                });
                                _agregarEvento(
                                  'Config actualizada: $_broker:$_port | $_topic',
                                );
                                await _connect();

                                setPanelState(() {
                                  panelColor = const Color(0xFF1F7A4A);
                                  panelMensaje =
                                      'Configuracion guardada correctamente.';
                                });
                              },
                              icon: const Icon(Icons.save),
                              label: const Text('Guardar y reconectar'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _reconectarManual,
                              icon: const Icon(Icons.sync),
                              label: const Text('Reconectar ahora'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _eventos.clear();
                                });
                                setPanelState(() {
                                  panelColor = const Color(0xFF1F7A4A);
                                  panelMensaje = 'Historial borrado.';
                                });
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Borrar historial'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Logs y respuestas MQTT',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.26),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: _eventos.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Sin logs todavia',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _eventos.length,
                                  itemBuilder: (context, index) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                      ),
                                      child: Text(
                                        _eventos[index],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  InputDecoration _panelInputDecoration({
    required String label,
    required String hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white30),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.lightBlueAccent),
      ),
    );
  }

  void _agregarEvento(String mensaje) {
    final timestamp = _horaActual();
    if (!mounted || _isDisposing) {
      return;
    }
    setState(() {
      _eventos.insert(0, '[$timestamp] $mensaje');
      if (_eventos.length > 30) {
        _eventos.removeLast();
      }
    });
  }

  String _horaActual() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  void _enviarComandoAlimentar() {
    SystemSound.play(SystemSoundType.click);

    if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
      setState(() {
        _status = 'Sin conexion al broker';
      });
      _agregarEvento('No se envio: sin conexion');
      return;
    }

    final builder = MqttClientPayloadBuilder()..addString(_payloadAlimentar);
    _client?.publishMessage(_topic, MqttQos.atLeastOnce, builder.payload!);

    setState(() {
      _status = 'Mensaje enviado a $_topic';
    });
    _agregarEvento('Enviado local: $_payloadAlimentar');
  }

  void _mostrarInfoApp() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Informacion'),
          content: const Text(
            'Desarrollado por Torelec.com\n\n'
            'Esta app permite enviar de forma simple el comando de alimentacion para animales desde tu dispositivo al sistema MQTT.',
          ),
          actions: [
            TextButton.icon(
              onPressed: _abrirSitioTorelec,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Ir a Torelec.com'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _abrirSitioTorelec() async {
    final uri = Uri.parse('https://www.torelec.com');
    final sePudoAbrir = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!sePudoAbrir && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace.')),
      );
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    _disposeClient();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conectado =
        _client?.connectionStatus?.state == MqttConnectionState.connected;
    final double outerDiameter = (MediaQuery.sizeOf(context).height * 0.42)
        .clamp(230.0, 290.0);
    final double innerDiameter = outerDiameter - 42;

    return Scaffold(
      backgroundColor: const Color(0xFFEAF7FF),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE9F9FF), Color(0xFFCBEFFE), Color(0xFF99E1FA)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(top: -70, right: -55, child: _bubble(220, 0x66FFFFFF)),
            Positioned(bottom: -90, left: -60, child: _bubble(210, 0x44FFFFFF)),
            Positioned(top: 220, left: -35, child: _bubble(120, 0x55FFFFFF)),
            Positioned(
              left: 10,
              bottom: 12,
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _mostrarInfoApp,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D597F).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF0D597F).withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Color(0xFF0E5D8A),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Panel desarrollador',
                        onPressed: _abrirPanelDesarrollador,
                        color: const Color(0xFF0E5D8A),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 6),
                    const Text(
                      'Alimentador de Animales',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF0A3550),
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      conectado
                          ? 'Todo listo para alimentar a tus animales'
                          : 'Conectando con el dispensador...',
                      style: const TextStyle(
                        color: Color(0xFF275B78),
                        fontSize: 15,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.96, end: 1.04),
                        duration: const Duration(milliseconds: 1700),
                        curve: Curves.easeInOut,
                        builder: (context, scale, child) {
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: SizedBox(
                          width: outerDiameter,
                          height: outerDiameter,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: outerDiameter,
                                height: outerDiameter,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0x55FF6A00),
                                    width: 12,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: innerDiameter,
                                height: innerDiameter,
                                child: ElevatedButton(
                                  onPressed: _enviarComandoAlimentar,
                                  style: ElevatedButton.styleFrom(
                                    shape: const CircleBorder(),
                                    backgroundColor: const Color(0xFFFF5A1F),
                                    foregroundColor: Colors.white,
                                    elevation: 16,
                                    shadowColor: Colors.black.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.set_meal, size: 58),
                                      SizedBox(height: 10),
                                      Text(
                                        'ALIMENTAR',
                                        style: TextStyle(
                                          fontSize: 30,
                                          letterSpacing: 1.2,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D597F).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF0D597F).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              conectado ? Icons.circle : Icons.sync_problem,
                              size: 10,
                              color: conectado
                                  ? const Color(0xFF7CFC00)
                                  : Colors.amberAccent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              conectado ? 'Conectado' : 'Sin conexion',
                              style: const TextStyle(
                                color: Color(0xFF0A3550),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(double size, int colorHex) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Color(colorHex)),
    );
  }
}
