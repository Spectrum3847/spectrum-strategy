import 'package:flutter/material.dart';

import 'package:statbotics_client/statbotics_client.dart';

import '../state/event_controller.dart';
import '../widgets/glass_modal.dart';
import 'glass_chrome.dart';

Future<void> showEventPicker(
  BuildContext context,
  EventController eventController,
) async {
  final year = DateTime.now().year;

  final events = eventController.availableEvents;
  if ((events.isEmpty || events.any((e) => e.year != year)) &&
      !eventController.eventsLoading) {
    await eventController.loadEventsForYear(year);
  }
  if (!context.mounted) return;

  final glass = GlassChrome.isEnabled(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => EventPickerDialog(
      eventController: eventController,
      initialYear: year,
      glass: glass,
    ),
  );
}

bool isEventNearby(
  String? startDate,
  String? endDate,
  DateTime today, {
  int days = 3,
}) {
  final start = startDate == null ? null : DateTime.tryParse(startDate);
  final end = endDate == null ? start : DateTime.tryParse(endDate);
  if (start == null || end == null) return false;
  final startsBy = DateTime(today.year, today.month, today.day + days);
  final endedAfter = DateTime(today.year, today.month, today.day - days);
  return !start.isAfter(startsBy) && !end.isBefore(endedAfter);
}

class EventPickerDialog extends StatefulWidget {
  const EventPickerDialog({
    required this.eventController,
    required this.initialYear,
    this.glass = false,
    super.key,
  });

  final EventController eventController;
  final int initialYear;

  final bool glass;

  @override
  State<EventPickerDialog> createState() => _EventPickerDialogState();
}

class _EventPickerDialogState extends State<EventPickerDialog> {
  late int _year;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadYear(int year) async {
    setState(() {
      _year = year;
    });
    await widget.eventController.loadEventsForYear(year);
    if (mounted) setState(() {});
  }

  Future<void> _setShowAll(bool value) async {
    setState(() => _showAll = value);
    if (!value && _year != widget.initialYear) {
      await _loadYear(widget.initialYear);
    }
  }

  Future<void> _selectEvent(StatboticsEvent event) async {
    Navigator.of(context).pop();
    await widget.eventController.setEventKey(event.key);
  }

  List<StatboticsEvent> get _filteredEvents {
    final now = DateTime.now();
    return widget.eventController.availableEvents
        .where(
          (e) =>
              (_showAll ||
                  _query.isNotEmpty ||
                  isEventNearby(e.startDate, e.endDate, now)) &&
              (e.name.toLowerCase().contains(_query) ||
                  e.key.toLowerCase().contains(_query)),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.eventController,
      builder: (context, _) {
        final filtered = _filteredEvents;

        return GlassAlertDialogShell(
          glass: widget.glass,
          title: 'Select Event',
          content: SizedBox(
            width: double.maxFinite,
            height: 480,
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show all events'),
                  value: _showAll,
                  onChanged: _setShowAll,
                ),
                if (_showAll)
                  Row(
                    children: [
                      IconButton(
                        onPressed: _year > 2000
                            ? () => _loadYear(_year - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        tooltip: 'Previous year',
                      ),
                      Expanded(
                        child: Text(
                          _year.toString(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: _year < widget.initialYear
                            ? () => _loadYear(_year + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                        tooltip: 'Next year',
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search events...',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: widget.eventController.eventsLoading
                      ? const Center(child: CircularProgressIndicator())
                      : widget.eventController.eventsError != null
                      ? Center(
                          child: Text(
                            widget.eventController.eventsError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        )
                      : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _showAll || _query.isNotEmpty
                                ? 'No events found.'
                                : 'No nearby events. Turn on Show all '
                                      'events to pick another.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final event = filtered[index];
                            final weekLabel = event.week != null
                                ? 'Week ${event.week}'
                                : 'CMP';
                            return ListTile(
                              dense: true,
                              title: Text(event.name),
                              subtitle: Text('$weekLabel  •  ${event.key}'),
                              onTap: () => _selectEvent(event),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}
