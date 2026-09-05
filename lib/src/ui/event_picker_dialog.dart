import 'package:flutter/material.dart';

import 'package:statbotics_client/statbotics_client.dart';

import '../state/event_controller.dart';

Future<void> showEventPicker(
  BuildContext context,
  EventController eventController,
) async {
  final year = DateTime.now().year;
  if (eventController.availableEvents.isEmpty &&
      !eventController.eventsLoading) {
    await eventController.loadEventsForYear(year);
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) =>
        EventPickerDialog(eventController: eventController, initialYear: year),
  );
}

class EventPickerDialog extends StatefulWidget {
  const EventPickerDialog({
    required this.eventController,
    required this.initialYear,
    super.key,
  });

  final EventController eventController;
  final int initialYear;

  @override
  State<EventPickerDialog> createState() => _EventPickerDialogState();
}

class _EventPickerDialogState extends State<EventPickerDialog> {
  late int _year;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

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

  Future<void> _selectEvent(StatboticsEvent event) async {
    Navigator.of(context).pop();
    await widget.eventController.setEventKey(event.key);
  }

  List<StatboticsEvent> get _filteredEvents {
    final events = widget.eventController.availableEvents;
    if (_query.isEmpty) return events;
    return events
        .where(
          (e) =>
              e.name.toLowerCase().contains(_query) ||
              e.key.toLowerCase().contains(_query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.eventController,
      builder: (context, _) {
        final filtered = _filteredEvents;

        return AlertDialog(
          title: const Text('Select Event'),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          content: SizedBox(
            width: double.maxFinite,
            height: 480,
            child: Column(
              children: [
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
                      ? const Center(child: Text('No events found.'))
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
