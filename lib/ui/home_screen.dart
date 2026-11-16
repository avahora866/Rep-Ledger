import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import 'config_screen.dart';
import 'day_view.dart';
import 'log_sheet.dart';

/// Pages are indexed relative to today so the user can swipe freely in both
/// directions; [_todayPage] is today.
const _todayPage = 100000;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repo});

  final LedgerRepository repo;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pageController = PageController(initialPage: _todayPage);
  late DateTime _today = _dateOnly(DateTime.now());
  int _page = _todayPage;

  DateTime _dayForPage(int page) =>
      DateTime(_today.year, _today.month, _today.day + (page - _todayPage));

  // Compare as UTC calendar dates so DST changes don't skew the day count.
  int _pageForDay(DateTime day) =>
      _todayPage +
      DateTime.utc(
        day.year,
        day.month,
        day.day,
      ).difference(DateTime.utc(_today.year, _today.month, _today.day)).inDays;

  DateTime get _currentDay => _dayForPage(_page);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page, {bool animate = true}) {
    if ((page - _page).abs() > 1 || !animate) {
      _pageController.jumpToPage(page);
    } else {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentDay,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) _goTo(_pageForDay(picked));
  }

  String _title(DateTime day) {
    final diff = _page - _todayPage;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    final fmt = day.year == _today.year
        ? DateFormat('EEE d MMM')
        : DateFormat('EEE d MMM y');
    return fmt.format(day);
  }

  @override
  Widget build(BuildContext context) {
    // If the app stays open past midnight, keep "Today" accurate.
    final now = _dateOnly(DateTime.now());
    if (now != _today) {
      final viewing = _currentDay;
      _today = now;
      _page = _pageForDay(viewing);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _goTo(_page, animate: false),
      );
    }
    final day = _currentDay;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Previous day',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _goTo(_page - 1),
        ),
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _pickDate,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_title(day)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _goTo(_page + 1),
          ),
          if (_page != _todayPage)
            IconButton(
              tooltip: 'Jump to today',
              icon: const Icon(Icons.today),
              onPressed: () => _goTo(_todayPage),
            ),
          IconButton(
            tooltip: 'Exercises & data',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ConfigScreen(repo: widget.repo),
              ),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (p) => setState(() => _page = p),
        itemBuilder: (context, page) => DayView(
          key: ValueKey(_dayForPage(page)),
          repo: widget.repo,
          day: _dayForPage(page),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showLogSheet(context, repo: widget.repo, day: day),
        icon: const Icon(Icons.add),
        label: const Text('Log'),
      ),
    );
  }
}
