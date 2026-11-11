import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SabaBabakApp());
}

const categories = <String>[
  'خوراک',
  'لوازم منزل',
  'درمان',
  'آرایشی',
  'آموزشی و تفریحی',
  'سایر',
];

const monthNames = <String>[
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

const cardColor = Color(0xFF20283B);
const accentColor = Color(0xFF9B8CFF);

String persianDigits(String text) {
  const english = '0123456789';
  const persian = '۰۱۲۳۴۵۶۷۸۹';

  return text.replaceAllMapped(
    RegExp(r'[0-9]'),
    (match) => persian[english.indexOf(match.group(0)!)],
  );
}

String groupedNumber(int value) {
  final text = value.toString();
  final buffer = StringBuffer();

  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) {
      buffer.write('٬');
    }
    buffer.write(text[i]);
  }

  return persianDigits(buffer.toString());
}

String money(int amount) => '${groupedNumber(amount)} تومان';

String shamsiDate(DateTime date) {
  final jalali = Jalali.fromDateTime(date);
  return persianDigits(
    '${jalali.day} ${monthNames[jalali.month - 1]} ${jalali.year}',
  );
}

int? parseToman(String input) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final normalized = StringBuffer();

  for (final character in input.split('')) {
    final faIndex = persian.indexOf(character);
    final arIndex = arabic.indexOf(character);

    if (faIndex >= 0) {
      normalized.write(faIndex);
    } else if (arIndex >= 0) {
      normalized.write(arIndex);
    } else if ('0123456789'.contains(character)) {
      normalized.write(character);
    }
  }

  return int.tryParse(normalized.toString());
}

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.title,
    required this.done,
  });

  final int id;
  final String title;
  final bool done;

  factory ShoppingItem.fromMap(Map<String, Object?> map) {
    return ShoppingItem(
      id: map['id'] as int,
      title: map['title'] as String,
      done: (map['done'] as int) == 1,
    );
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.settled,
    this.receiptPath,
  });

  final int id;
  final String title;
  final int amount;
  final String category;
  final DateTime date;
  final bool settled;
  final String? receiptPath;

  factory Expense.fromMap(Map<String, Object?> map) {
    return Expense(
      id: map['id'] as int,
      title: map['title'] as String,
      amount: map['amount'] as int,
      category: map['category'] as String,
      date: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      settled: (map['settled'] as int) == 1,
      receiptPath: map['receipt_path'] as String?,
    );
  }
}

class ExpenseDraft {
  const ExpenseDraft({
    required this.title,
    required this.amount,
    required this.category,
    this.receipt,
  });

  final String title;
  final int amount;
  final String category;
  final XFile? receipt;
}

class HouseholdStore {
  late final Future<Database> _database = _open();

  Future<Database> _open() async {
    final dbPath = p.join(await getDatabasesPath(), 'saba_babak_home.db');

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE shopping (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            done INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            amount INTEGER NOT NULL,
            category TEXT NOT NULL,
            receipt_path TEXT,
            settled INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<List<ShoppingItem>> shoppingItems() async {
    final db = await _database;
    final rows = await db.query(
      'shopping',
      orderBy: 'done ASC, created_at DESC, id DESC',
    );
    return rows.map(ShoppingItem.fromMap).toList();
  }

  Future<void> addShoppingItem(String title) async {
    final db = await _database;
    await db.insert('shopping', {
      'title': title,
      'done': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> setShoppingDone(int id, bool done) async {
    final db = await _database;
    await db.update(
      'shopping',
      {'done': done ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteShoppingItem(int id) async {
    final db = await _database;
    await db.delete('shopping', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Expense>> expenses() async {
    final db = await _database;
    final rows = await db.query(
      'expenses',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<void> addExpense(ExpenseDraft draft) async {
    String? savedReceipt;

    if (draft.receipt != null) {
      final documents = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(documents.path, 'receipts'));
      await folder.create(recursive: true);

      final extension = p.extension(draft.receipt!.path);
      final name =
          'receipt_${DateTime.now().microsecondsSinceEpoch}'
          '${extension.isEmpty ? '.jpg' : extension}';

      savedReceipt = p.join(folder.path, name);
      await File(draft.receipt!.path).copy(savedReceipt);
    }

    try {
      final db = await _database;
      await db.insert('expenses', {
        'title': draft.title,
        'amount': draft.amount,
        'category': draft.category,
        'receipt_path': savedReceipt,
        'settled': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      if (savedReceipt != null) {
        final file = File(savedReceipt);
        if (await file.exists()) {
          await file.delete();
        }
      }
      rethrow;
    }
  }

  Future<void> setExpenseSettled(int id, bool settled) async {
    final db = await _database;
    await db.update(
      'expenses',
      {'settled': settled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteExpense(Expense expense) async {
    final db = await _database;
    await db.delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [expense.id],
    );

    if (expense.receiptPath != null) {
      final file = File(expense.receiptPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}

class SabaBabakApp extends StatelessWidget {
  const SabaBabakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'خانه صبا و بابک',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121725),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF171D2E),
          centerTitle: true,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF293248),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HouseholdStore _store = HouseholdStore();

  List<ShoppingItem> _shopping = [];
  List<Expense> _expenses = [];
  int _tab = 0;
  bool _loading = true;

  late Jalali _reportMonth = Jalali.fromDateTime(DateTime.now());

  int get _outstanding => _expenses
      .where((expense) => !expense.settled)
      .fold<int>(0, (sum, expense) => sum + expense.amount);

  List<Expense> get _monthExpenses => _expenses.where((expense) {
    final date = Jalali.fromDateTime(expense.date);
    return date.year == _reportMonth.year &&
        date.month == _reportMonth.month;
  }).toList();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final shopping = await _store.shoppingItems();
      final expenses = await _store.expenses();

      if (!mounted) return;
      setState(() {
        _shopping = shopping;
        _expenses = expenses;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('خطا در ذخیره یا خواندن اطلاعات: $error')),
    );
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _addShopping() async {
    final controller = TextEditingController();

    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('کالای جدید'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'مثلاً شیر، برنج یا لامپ',
          ),
          onSubmitted: (value) {
            final text = value.trim();
            if (text.isNotEmpty) {
              Navigator.pop(dialogContext, text);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(dialogContext, text);
              }
            },
            child: const Text('افزودن'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (!mounted || title == null) return;

    await _perform(() => _store.addShoppingItem(title));
  }

  Future<void> _addExpense() async {
    final draft = await showModalBottomSheet<ExpenseDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF20283B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => const ExpenseForm(),
    );

    if (!mounted || draft == null) return;
    await _perform(() => _store.addExpense(draft));
  }

  Future<void> _deleteExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف هزینه'),
        content: Text('«${expense.title}» و رسید آن حذف شوند؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;
    await _perform(() => _store.deleteExpense(expense));
  }

  void _showReceipt(String path) {
    final file = File(path);

    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فایل رسید در این گوشی پیدا نشد.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF101522),
        insetPadding: const EdgeInsets.all(14),
        child: SizedBox(
          height: MediaQuery.sizeOf(dialogContext).height * 0.76,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Center(
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Text('نمایش رسید ممکن نیست.'),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  tooltip: 'بستن',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _changeMonth(int offset) {
    setState(() {
      _reportMonth = Jalali(
        _reportMonth.year,
        _reportMonth.month,
        1,
      ).addMonths(offset);
    });
  }

  Widget _panel({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }

  Widget _empty(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 38),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60),
        ),
      ),
    );
  }

  Widget _shoppingPage() {
    final remaining = _shopping.where((item) => !item.done).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _panel(
          child: Row(
            children: [
              const Icon(Icons.shopping_basket_outlined, color: accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${persianDigits('$remaining')} قلم برای خرید باقی مانده',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: _addShopping,
          icon: const Icon(Icons.add),
          label: const Text('افزودن کالا'),
        ),
        const SizedBox(height: 16),
        if (_shopping.isEmpty)
          _empty('فهرست خرید خالی است.\nاولین کالا را اضافه کن.'),
        for (final item in _shopping)
          _panel(
            child: Row(
              children: [
                Checkbox(
                  value: item.done,
                  onChanged: (value) {
                    _perform(
                      () => _store.setShoppingDone(
                        item.id,
                        value ?? false,
                      ),
                    );
                  },
                ),
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 16,
                      decoration:
                          item.done ? TextDecoration.lineThrough : null,
                      color: item.done ? Colors.white54 : Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف کالا',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    _perform(() => _store.deleteShoppingItem(item.id));
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _expenseCard(Expense expense) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: accentColor.withValues(alpha: 0.16),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${expense.category} • ${shamsiDate(expense.date)}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'گزینه‌های هزینه',
                onSelected: (choice) {
                  if (choice == 'delete') _deleteExpense(expense);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('حذف هزینه'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12),
          Row(
            children: [
              Expanded(
                child: Text(
                  money(expense.amount),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (expense.receiptPath != null)
                IconButton(
                  tooltip: 'دیدن رسید و بزرگ‌نمایی',
                  onPressed: () =>
                      _showReceipt(expense.receiptPath!),
                  icon: const Icon(Icons.image_outlined),
                ),
              Text(
                expense.settled ? 'تسویه‌شده' : 'تسویه‌نشده',
                style: const TextStyle(fontSize: 11),
              ),
              Switch.adaptive(
                value: expense.settled,
                onChanged: (value) {
                  _perform(
                    () => _store.setExpenseSettled(
                      expense.id,
                      value,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ledgerPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF473A91),
                Color(0xFF263A70),
                Color(0xFF20283B),
              ],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ماندهٔ پرداخت‌نشده به صبا'),
              const SizedBox(height: 12),
              Text(
                money(_outstanding),
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'مجموع هزینه‌هایی که هنوز تسویه نشده‌اند',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _addExpense,
          icon: const Icon(Icons.add),
          label: const Text('ثبت هزینهٔ جدید'),
        ),
        const SizedBox(height: 18),
        const Text(
          'هزینه‌ها',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (_expenses.isEmpty)
          _empty('هنوز هزینه‌ای ثبت نشده است.'),
        for (final expense in _expenses) _expenseCard(expense),
      ],
    );
  }

  Widget _reportPage() {
    final monthly = _monthExpenses;
    final total = monthly.fold<int>(
      0,
      (sum, expense) => sum + expense.amount,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _panel(
          child: Row(
            children: [
              IconButton(
                tooltip: 'ماه قبل',
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_right),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    persianDigits(
                      '${monthNames[_reportMonth.month - 1]} '
                      '${_reportMonth.year}',
                    ),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'ماه بعد',
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_left),
              ),
            ],
          ),
        ),
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('مجموع خریدهای ماه'),
              const SizedBox(height: 10),
              Text(
                money(total),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${persianDigits('${monthly.length}')} هزینه ثبت‌شده',
                style: const TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'گزارش دسته‌بندی',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        for (final category in categories)
          Builder(
            builder: (_) {
              final amount = monthly
                  .where((expense) => expense.category == category)
                  .fold<int>(
                    0,
                    (sum, expense) => sum + expense.amount,
                  );

              return _panel(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(category)),
                        Text(money(amount)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: total == 0 ? 0 : amount / total,
                      minHeight: 7,
                      borderRadius: BorderRadius.circular(10),
                      color: accentColor,
                      backgroundColor: Colors.white12,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('خانه صبا و بابک'),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF171D31),
              Color(0xFF121725),
              Color(0xFF211D38),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _tab,
                children: [
                  _shoppingPage(),
                  _ledgerPage(),
                  _reportPage(),
                ],
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          setState(() => _tab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart),
            label: 'خرید',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'هزینه‌ها',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'گزارش ماهانه',
          ),
        ],
      ),
    );
  }
}

class ExpenseForm extends StatefulWidget {
  const ExpenseForm({super.key});

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  String _category = categories.first;
  XFile? _receipt;
  String? _validationError;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
      );

      if (!mounted || image == null) return;
      setState(() => _receipt = image);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _validationError = 'انتخاب تصویر انجام نشد: $error';
      });
    }
  }

  void _save() {
    final title = _titleController.text.trim();
    final amount = parseToman(_amountController.text);

    if (title.isEmpty || amount == null || amount <= 0) {
      setState(() {
        _validationError =
            'عنوان را بنویس و مبلغی بزرگ‌تر از صفر وارد کن.';
      });
      return;
    }

    Navigator.pop(
      context,
      ExpenseDraft(
        title: title,
        amount: amount,
        category: _category,
        receipt: _receipt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        24,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'ثبت هزینهٔ صبا',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'مبلغ تا زمان تسویه، به ماندهٔ بدهی اضافه می‌شود.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'عنوان خرید',
              hintText: 'مثلاً خرید سوپرمارکت',
            ),
          ),
