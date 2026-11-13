import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const TradingApp());

class TradingApp extends StatelessWidget {
  const TradingApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Capital Candles',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    home: const TrackerScreen(),
  );
}

class Entry {
  final String id;
  final DateTime date;
  final double amount;
  final String kind; // trade or daily
  final String note;
  Entry(this.id, this.date, this.amount, this.kind, this.note);
  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'amount': amount,
    'kind': kind,
    'note': note,
  };
  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
    json['id'] as String,
    DateTime.parse(json['date'] as String),
    (json['amount'] as num).toDouble(),
    json['kind'] as String,
    (json['note'] ?? '') as String,
  );
}

class Candle {
  final String label;
  final double open, close;
  Candle(this.label, this.open, this.close);
  double get high => math.max(open, close);
  double get low => math.min(open, close);
  bool get positive => close >= open;
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String money(double v) => '\$${v.toStringAsFixed(2)}';

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key});
  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  double capital = 1000;
  List<Entry> entries = [];
  bool dailyView = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      capital = prefs.getDouble('capital') ?? 1000;
      entries = (jsonDecode(prefs.getString('entries') ?? '[]') as List)
          .map((e) => Entry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      entries = [];
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('capital', capital);
    await prefs.setString(
      'entries',
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  List<Entry> get sorted => [...entries]
    ..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });

  // Trade candles only use individual trade entries.
  // Daily candles aggregate both trade entries and manual daily totals.
  List<Candle> get candles {
    final ordered = sorted;
    if (!dailyView) {
      double balance = capital;
      final result = <Candle>[];
      var index = 0;
      for (final e in ordered) {
        // Daily summaries affect the running balance, but do not create trade candles.
        final before = balance;
        balance += e.amount;
        if (e.kind == 'trade')
          result.add(Candle('T${++index}', before, balance));
      }
      return result;
    }
    final grouped = <String, double>{};
    for (final e in ordered) {
      grouped.update(
        dayKey(e.date),
        (value) => value + e.amount,
        ifAbsent: () => e.amount,
      );
    }
    double balance = capital;
    return grouped.entries.map((group) {
      final before = balance;
      balance += group.value;
      return Candle(group.key.substring(5), before, balance);
    }).toList();
  }

  double get balance =>
      capital + entries.fold<double>(0, (s, e) => s + e.amount);

  Future<void> _capitalDialog() async {
    final ctrl = TextEditingController(text: capital.toStringAsFixed(2));
    final newCapital = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Initial capital'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: '\$',
            labelText: 'Starting balance',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(ctrl.text.trim());
              if (value == null || !value.isFinite || value < 0) return;
              Navigator.pop(ctx, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newCapital != null) {
      setState(() => capital = newCapital);
      await _save();
    }
  }

  Future<void> _addDialog() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var kind = 'trade';
    var profit = true;
    var date = DateTime.now();
    final result = await showDialog<Entry>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Record profit or loss'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'trade', label: Text('Trade')),
                    ButtonSegment(value: 'daily', label: Text('Daily total')),
                  ],
                  selected: {kind},
                  onSelectionChanged: (v) => update(() => kind = v.first),
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Profit')),
                    ButtonSegment(value: false, label: Text('Loss')),
                  ],
                  selected: {profit},
                  onSelectionChanged: (v) => update(() => profit = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '\$',
                  ),
                ),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(dayKey(date)),
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (selected != null)
                      update(
                        () => date = DateTime(
                          selected.year,
                          selected.month,
                          selected.day,
                          date.hour,
                          date.minute,
                          date.second,
                          date.millisecond,
                          date.microsecond,
                        ),
                      );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(amountCtrl.text.trim());
                if (value == null || !value.isFinite || value <= 0) return;
                final id = DateTime.now().microsecondsSinceEpoch.toString();
                Navigator.pop(
                  ctx,
                  Entry(
                    id,
                    date,
                    profit ? value : -value,
                    kind,
                    noteCtrl.text.trim(),
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
    noteCtrl.dispose();
    if (result != null) {
      setState(() => entries.add(result));
      await _save();
    }
  }

  Future<void> _delete(Entry entry) async {
    setState(() => entries.removeWhere((e) => e.id == entry.id));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final pnl = balance - capital;
    final chart = candles;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capital Candles'),
        actions: [
          IconButton(
            tooltip: 'Change initial capital',
            onPressed: _capitalDialog,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add result'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric('Initial capital', money(capital), Colors.indigo),
              _metric('Current balance', money(balance), Colors.blue),
              _metric(
                'Net P/L',
                '${pnl >= 0 ? '+' : ''}${money(pnl)}',
                pnl >= 0 ? Colors.green : Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Per trade')),
              ButtonSegment(value: true, label: Text('Per day')),
            ],
            selected: {dailyView},
            onSelectionChanged: (v) => setState(() => dailyView = v.first),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dailyView
                        ? 'Daily balance candles'
                        : 'Trade balance candles',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 300,
                    child: CandleChart(candles: chart, baseline: capital),
                  ),
                  const Text(
                    'Green = profit    Red = loss    Dashed = initial capital',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('History', style: Theme.of(context).textTheme.titleLarge),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No results yet. Tap Add result to create your first candle.',
              ),
            ),
          ...sorted.reversed.map(
            (e) => Card(
              child: ListTile(
                leading: Icon(
                  e.amount >= 0 ? Icons.trending_up : Icons.trending_down,
                  color: e.amount >= 0 ? Colors.green : Colors.red,
                ),
                title: Text(
                  '${e.kind == 'trade' ? 'Trade' : 'Daily'} • ${dayKey(e.date)}',
                ),
                subtitle: e.note.isEmpty ? null : Text(e.note),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${e.amount >= 0 ? '+' : ''}${money(e.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: e.amount >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete entry',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(e),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }

  Widget _metric(String title, String value, Color color) => Container(
    width: 165,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class CandleChart extends StatelessWidget {
  final List<Candle> candles;
  final double baseline;
  const CandleChart({super.key, required this.candles, required this.baseline});

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty)
      return const Center(child: Text('Add a result to see the chart'));
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = candles.length;
        final chartWidth = math.max(constraints.maxWidth, count * 45.0 + 65);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: chartWidth,
            height: constraints.maxHeight,
            child: CustomPaint(
              painter: _CandlePainter(
                candles,
                baseline,
                Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CandlePainter extends CustomPainter {
  final List<Candle> candles;
  final double baseline;
  final Color textColor;
  _CandlePainter(this.candles, this.baseline, this.textColor);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 65.0, right = 12.0, top = 18.0, bottom = 32.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;
    final values = [
      baseline,
      ...candles.expand((c) => [c.open, c.close]),
    ];
    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);
    final padding = math.max((maxValue - minValue) * .15, 1.0);
    minValue -= padding;
    maxValue += padding;
    double y(double value) =>
        top + (maxValue - value) / (maxValue - minValue) * height;
    void line(
      Offset a,
      Offset b,
      Color color,
      double stroke, {
      bool dashed = false,
    }) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = stroke;
      if (!dashed) {
        canvas.drawLine(a, b, paint);
        return;
      }
      for (double x = a.dx; x < b.dx; x += 11) {
        canvas.drawLine(
          Offset(x, a.dy),
          Offset(math.min(x + 6, b.dx), b.dy),
          paint,
        );
      }
    }

    void label(String text, Offset at, {double fontSize = 10}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontSize, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, at);
    }

    for (var i = 0; i <= 4; i++) {
      final value = minValue + (maxValue - minValue) * i / 4;
      final yy = y(value);
      line(
        Offset(left, yy),
        Offset(size.width - right, yy),
        textColor.withValues(alpha: .14),
        1,
      );
      label(value.toStringAsFixed(2), Offset(0, yy - 7));
    }
    line(
      Offset(left, y(baseline)),
      Offset(size.width - right, y(baseline)),
      Colors.indigo,
      1.5,
      dashed: true,
    );
    final step = width / candles.length;
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final x = left + step * (i + .5);
      final topY = y(c.high), bottomY = y(c.low);
      final color = c.positive ? Colors.green : Colors.red;
      final paint = Paint()..color = color;
      canvas.drawLine(
        Offset(x, topY),
        Offset(x, bottomY),
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
      final candleWidth = math.min(step * .55, 24.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - candleWidth / 2,
            topY,
            candleWidth,
            math.max(bottomY - topY, 2),
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      label(
        c.label,
        Offset(x - math.min(c.label.length * 3.2, 18), size.height - 22),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.baseline != baseline ||
      old.candles != candles ||
      old.textColor != textColor;
}
