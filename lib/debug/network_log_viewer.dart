import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'network_log.dart';
import 'shake_detector.dart';

/// DEBUG BUILDS ONLY — see network_log.dart's header.
///
/// Wraps the whole app (via `MaterialApp.builder`) and opens the network log
/// on a shake. The log is drawn on top of the app with its own [Navigator],
/// not pushed onto the app's: `MaterialApp.builder` sits above the app's
/// navigator, and the app's navigator is rebuilt from scratch on every
/// sign-in/sign-out (see `SduiDemoApp`), so there's no stable one to push
/// onto. Closing the log leaves the app exactly where it was.
class NetworkLogShakeListener extends StatefulWidget {
  final Widget child;
  final NetworkLog log;

  /// Scripted readings for tests; the device accelerometer when null.
  final Stream<Acceleration>? readings;

  const NetworkLogShakeListener({super.key, required this.child, required this.log, this.readings});

  @override
  State<NetworkLogShakeListener> createState() => _NetworkLogShakeListenerState();
}

class _NetworkLogShakeListenerState extends State<NetworkLogShakeListener> {
  late final ShakeDetector _detector = ShakeDetector(onShake: _show);
  bool _open = false;

  void _show() {
    if (mounted && !_open) setState(() => _open = true);
  }

  @override
  void initState() {
    super.initState();
    _detector.start(widget.readings);
  }

  @override
  void dispose() {
    _detector.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_open)
          Positioned.fill(
            // Its own hero scope: MaterialApp's HeroController may only
            // serve one Navigator, and it already serves the app's.
            child: HeroControllerScope.none(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => NetworkLogScreen(log: widget.log, onClose: () => setState(() => _open = false)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class NetworkLogScreen extends StatelessWidget {
  final NetworkLog log;
  final VoidCallback onClose;

  const NetworkLogScreen({super.key, required this.log, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network log (debug build)'),
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: onClose),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Clear', onPressed: log.clear),
        ],
      ),
      body: ListenableBuilder(
        listenable: log,
        builder: (context, _) {
          final entries = log.entries;
          if (entries.isEmpty) {
            return const Center(child: Text('No requests yet.'));
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = entries[i];
              return ListTile(
                dense: true,
                leading: _StatusChip(entry: e),
                title: Text('${e.method} ${Uri.parse(e.url).path}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${_time(e.startedAt)} · ${e.duration == null ? '…' : '${e.duration!.inMilliseconds} ms'}'
                  ' · ${Uri.parse(e.url).host}',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => NetworkLogDetailScreen(entry: e)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class NetworkLogDetailScreen extends StatelessWidget {
  final NetworkLogEntry entry;

  const NetworkLogDetailScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final summary = [
      '${e.method} ${e.url}',
      'Status: ${e.statusCode ?? e.error ?? 'pending'}',
      'Started: ${e.startedAt.toIso8601String()}',
      if (e.duration != null) 'Duration: ${e.duration!.inMilliseconds} ms',
    ].join('\n');
    return Scaffold(
      appBar: AppBar(
        title: Text('#${e.id} ${e.method}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy (already redacted)',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _asText(e, summary)));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText(summary),
          _section(context, 'Request headers', _headers(e.requestHeaders)),
          _section(context, 'Request body', e.requestBody ?? '(none)'),
          _section(context, 'Response headers', _headers(e.responseHeaders)),
          _section(context, 'Response body', e.responseBody ?? '(none)'),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, String body) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            SelectableText(body, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
      );
}

class _StatusChip extends StatelessWidget {
  final NetworkLogEntry entry;
  const _StatusChip({required this.entry});

  @override
  Widget build(BuildContext context) {
    final code = entry.statusCode;
    final color = switch (code) {
      null when entry.isPending => Colors.grey,
      null => Colors.deepOrange,
      < 300 => Colors.green,
      < 400 => Colors.blueGrey,
      < 500 => Colors.orange,
      _ => Colors.red,
    };
    return SizedBox(
      width: 44,
      child: Text(
        code?.toString() ?? (entry.isPending ? '…' : 'ERR'),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

String _time(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

String _headers(Map<String, String> headers) =>
    headers.isEmpty ? '(none)' : headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');

String _asText(NetworkLogEntry e, String summary) => [
      summary,
      '\nRequest headers:\n${_headers(e.requestHeaders)}',
      '\nRequest body:\n${e.requestBody ?? '(none)'}',
      '\nResponse headers:\n${_headers(e.responseHeaders)}',
      '\nResponse body:\n${e.responseBody ?? '(none)'}',
    ].join('\n');
