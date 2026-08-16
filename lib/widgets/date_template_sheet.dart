import 'package:flutter/material.dart';

/// A checkbox picker that builds a caption string from a clip's recorded
/// date/time — check whichever of 年/月/日/時間 to include, then press OK
/// to get the combined text back via [Navigator.pop].
class DateTemplateSheet extends StatefulWidget {
  const DateTemplateSheet({super.key, required this.dateTime});

  final DateTime dateTime;

  @override
  State<DateTemplateSheet> createState() => _DateTemplateSheetState();
}

class _DateTemplateSheetState extends State<DateTemplateSheet> {
  bool _year = true;
  bool _month = true;
  bool _day = true;
  bool _time = false;

  String get _composedText {
    final dateParts = <String>[
      if (_year) '${widget.dateTime.year}年',
      if (_month) '${widget.dateTime.month}月',
      if (_day) '${widget.dateTime.day}日',
    ];
    final parts = <String>[
      if (dateParts.isNotEmpty) dateParts.join(),
      if (_time)
        '${widget.dateTime.hour.toString().padLeft(2, '0')}:'
            '${widget.dateTime.minute.toString().padLeft(2, '0')}',
    ];
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final text = _composedText;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('テンプレート', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '撮影した日時から表示する項目を選んでください',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('年'),
              value: _year,
              onChanged: (v) => setState(() => _year = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('月'),
              value: _month,
              onChanged: (v) => setState(() => _month = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('日'),
              value: _day,
              onChanged: (v) => setState(() => _day = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('時間'),
              value: _time,
              onChanged: (v) => setState(() => _time = v ?? false),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                text.isEmpty ? '(何も選択されていません)' : text,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('キャンセル'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: text.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(text),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
