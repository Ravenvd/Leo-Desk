import 'package:flutter/material.dart';

import '../models/consumable.dart';
import '../models/inventory_activity.dart';
import '../models/thread_spool.dart';
import '../repositories/consumable_repository.dart';

class ConsumablesScreen extends StatefulWidget {
  const ConsumablesScreen({super.key, required this.repository});

  final ConsumableRepository repository;

  @override
  State<ConsumablesScreen> createState() => _ConsumablesScreenState();
}

class _ConsumablesScreenState extends State<ConsumablesScreen> {
  List<Consumable> _items = [];
  List<ThreadSpool> _lowSpools = [];
  List<Consumable> _lowStock = [];
  bool _loading = true;
  String? _category;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.repository.getConsumables(category: _category);
      final lowSpools = await widget.repository.getLowThreadSpools();
      final lowStock = await widget.repository.getLowStockConsumables();
      if (!mounted) return;
      setState(() {
        _items = items.where((item) =>
          _query.isEmpty ||
          item.name.toLowerCase().contains(_query.toLowerCase()) ||
          item.category.toLowerCase().contains(_query.toLowerCase()) ||
          (item.colour ?? '').toLowerCase().contains(_query.toLowerCase())
        ).toList();
        _lowSpools = lowSpools;
        _lowStock = lowStock;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Load consumables error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load consumables. Please retry.')),
        );
      }
    }
  }

  Future<void> _addConsumable() async {
    final result = await showDialog<Consumable>(
      context: context,
      builder: (_) => const _ConsumableFormDialog(),
    );
    if (result == null) return;
    try {
      await widget.repository.insertConsumable(result);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save consumable: $error')),
      );
    }
  }

  Future<void> _addStock(Consumable item) async {
    if (item.trackingType == Consumable.trackingPercentage) {
      await _addSpool(item);
      return;
    }
    final values = await showDialog<_StockEntry>(
      context: context,
      builder: (_) => _StockEntryDialog(item: item),
    );
    if (values == null) return;
    try {
      await widget.repository.recordStockIn(
        consumable: item,
        quantity: values.quantity,
        activityType: values.opening
            ? InventoryActivity.openingStock
            : InventoryActivity.purchase,
        totalCostPaise: values.costPaise,
        notes: values.notes,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not record stock: $error')),
      );
    }
  }

  Future<void> _addSpool(Consumable item) async {
    final values = await showDialog<_SpoolEntry>(
      context: context,
      builder: (_) => _SpoolEntryDialog(item: item),
    );
    if (values == null) return;
    try {
      await widget.repository.addThreadSpool(
        consumable: item,
        approximateLengthM: values.lengthM,
        purchaseDate: DateTime.now(),
        purchaseCostPaise: values.costPaise,
        notes: values.notes,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add spool: $error')),
      );
    }
  }

  Future<void> _manageSpools(Consumable item) async {
    final spools = await widget.repository.getSpools(item.id!);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 640,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                if (spools.isEmpty) const Text('No spools recorded yet.'),
                ...spools.map((spool) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${spool.approximateLengthM.toStringAsFixed(0)} m spool'),
                  subtitle: Text(spool.isEmpty
                    ? 'Empty'
                    : '${spool.remainingPercent.toStringAsFixed(0)}% remaining • about ${spool.estimatedRemainingMetres.toStringAsFixed(0)} m'),
                  trailing: spool.isEmpty
                    ? const Icon(Icons.check_circle_outline)
                    : PopupMenuButton<String>(
                        onSelected: (value) async {
                          Navigator.of(sheetContext).pop();
                          if (value == 'empty') {
                            await _markEmpty(spool);
                          } else {
                            await _updateSpool(spool);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'update', child: Text('Update remaining %')),
                          PopupMenuItem(value: 'empty', child: Text('Mark empty')),
                        ],
                      ),
                )),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _addSpool(item);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add spool'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await _load();
  }

  Future<void> _updateSpool(ThreadSpool spool) async {
    final controller = TextEditingController(
      text: spool.remainingPercent.toStringAsFixed(0),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update thread remaining'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Remaining percentage',
            suffixText: '%',
            helperText: 'Enter a value between 0 and the current percentage.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed == null || parsed < 0 || parsed > spool.remainingPercent) return;
              Navigator.pop(context, parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      await widget.repository.updateSpoolRemaining(
        spool: spool,
        remainingPercent: value,
        notes: 'Remaining percentage updated manually',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update spool: $error')));
    }
  }

  Future<void> _markEmpty(ThreadSpool spool) async {
    final controller = TextEditingController(text: '0');
    final wastage = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark spool empty'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Estimated wastage',
            suffixText: '% of spool',
            helperText: 'Current estimate remaining: ${spool.remainingPercent.toStringAsFixed(0)}%',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed == null || parsed < 0 || parsed > spool.remainingPercent) return;
              Navigator.pop(context, parsed);
            },
            child: const Text('Confirm empty'),
          ),
        ],
      ),
    );
    if (wastage == null) return;
    try {
      await widget.repository.markSpoolEmpty(
        spool: spool,
        estimatedWastagePercent: wastage,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not mark spool empty: $error')));
    }
  }

  Future<void> _observeStock(Consumable item) async {
    final current = await widget.repository.getCurrentStock(item.id!);
    if (!mounted) return;
    final controller = TextEditingController(text: current.toStringAsFixed(2));
    final observed = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record observed stock'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity in ${item.stockUnit}',
            helperText: 'This records a physical observation; it is not automatic consumption.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed == null || parsed < 0) return;
              Navigator.pop(context, parsed);
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (observed == null) return;
    try {
      await widget.repository.recordStockObservation(
        consumable: item,
        observedQuantity: observed,
        notes: 'Physical stock observation',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not record observation: $error')));
    }
  }

  Future<void> _showHistory(Consumable item) async {
    final activities = await widget.repository.getActivityHistory(item.id!);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.name} activity'),
        content: SizedBox(
          width: 520,
          child: activities.isEmpty
            ? const Text('No activity recorded yet.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: activities.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, index) {
                  final activity = activities[index];
                  final date = activity.createdAt.toLocal().toString().split('.').first;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_activityLabel(activity.activityType)),
                    subtitle: Text('$date${activity.notes == null ? '' : '\n${activity.notes}'}'),
                    trailing: activity.afterQuantity == null
                      ? null
                      : Text('${activity.afterQuantity!.toStringAsFixed(1)} ${activity.unit ?? ''}'),
                  );
                },
              ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  String _activityLabel(String type) {
    switch (type) {
      case InventoryActivity.purchase: return 'Purchase';
      case InventoryActivity.openingStock: return 'Opening stock';
      case InventoryActivity.threadUsage: return 'Thread usage';
      case InventoryActivity.threadExhausted: return 'Spool marked empty';
      case InventoryActivity.stockObservation: return 'Stock observation';
      case InventoryActivity.stockAdjustment: return 'Stock adjustment';
      default: return type;
    }
  }

  String _quantityLabel(Consumable item, double quantity) {
    if (item.stockUnit == Consumable.unitGrams) {
      return '${(quantity / 1000).toStringAsFixed(2)} kg';
    }
    if (item.stockUnit == Consumable.unitMillilitres) {
      return '${quantity.toStringAsFixed(0)} ml';
    }
    if (item.stockUnit == Consumable.unitMetres) {
      return '${quantity.toStringAsFixed(0)} m';
    }
    return '${quantity.toStringAsFixed(0)} pcs';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconButton(
                  tooltip: 'Back to inventory',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Consumables', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text('${_items.length} items', style: Theme.of(context).textTheme.bodyLarge),
                  ],
                )),
                OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
                const SizedBox(width: 8),
                FilledButton.icon(onPressed: _addConsumable, icon: const Icon(Icons.add), label: const Text('Add item')),
              ]),
              const SizedBox(height: 20),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name, category or colour',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  _query = value;
                  _load();
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: const Text('All categories'), selected: _category == null, onSelected: (_) { setState(() => _category = null); _load(); }),
                    ),
                    ...Consumable.categories.map((category) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (_) { setState(() => _category = _category == category ? null : category); _load(); },
                      ),
                    )),
                  ],
                ),
              ),
              if (_lowSpools.isNotEmpty || _lowStock.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        '${_lowSpools.length} thread spool(s) below 10% and ${_lowStock.length} supply item(s) at or below reorder level.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                      )),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                    ? const Center(child: Text('No consumables yet. Add thread, beads, sequins or other supplies to begin.'))
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _buildItem(_items[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(Consumable item) {
    return FutureBuilder<double>(
      future: item.trackingType == Consumable.trackingPercentage
          ? Future<double>.value(0)
          : widget.repository.getCurrentStock(item.id!),
      builder: (context, snapshot) {
        final stock = snapshot.data ?? 0;
        final thread = item.trackingType == Consumable.trackingPercentage;
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(child: Icon(thread ? Icons.color_lens_outlined : Icons.inventory_2_outlined)),
            title: Text(item.name),
            subtitle: Text([
              item.category,
              if (item.colour?.isNotEmpty == true) 'Colour: ${item.colour}',
              if (item.size?.isNotEmpty == true) 'Size: ${item.size}',
              if (item.finish?.isNotEmpty == true) item.finish!,
              if (thread) 'Tracked by spool'
              else 'Stock: ${_quantityLabel(item, stock)} • Reorder at ${_quantityLabel(item, item.reorderLevel)}',
            ].join(' • ')),
            isThreeLine: true,
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(tooltip: 'Activity history', onPressed: () => _showHistory(item), icon: const Icon(Icons.history)),
                if (thread)
                  IconButton(tooltip: 'Manage spools', onPressed: () => _manageSpools(item), icon: const Icon(Icons.view_list))
                else
                  IconButton(tooltip: 'Record observed stock', onPressed: () => _observeStock(item), icon: const Icon(Icons.scale_outlined)),
                IconButton(tooltip: thread ? 'Add spool' : 'Record purchase', onPressed: () => _addStock(item), icon: const Icon(Icons.add_shopping_cart)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConsumableFormDialog extends StatefulWidget {
  const _ConsumableFormDialog();

  @override
  State<_ConsumableFormDialog> createState() => _ConsumableFormDialogState();
}

class _ConsumableFormDialogState extends State<_ConsumableFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _colour = TextEditingController();
  final _size = TextEditingController();
  final _finish = TextEditingController();
  final _pack = TextEditingController();
  final _reorder = TextEditingController();
  String _category = Consumable.categoryEmbroideryThread;

  bool get _thread => [
    Consumable.categoryEmbroideryThread,
    Consumable.categoryAariThread,
    Consumable.categoryBobbinThread,
  ].contains(_category);

  String get _unit => _thread
      ? Consumable.unitMetres
      : _category == Consumable.categoryBeads || _category == Consumable.categoryStabilizers
          ? Consumable.unitGrams
          : _category == Consumable.categoryOils
              ? Consumable.unitMillilitres
              : Consumable.unitCount;

  String get _tracking => _thread
      ? Consumable.trackingPercentage
      : _unit == Consumable.unitCount
          ? Consumable.trackingCount
          : Consumable.trackingQuantity;

  double get _defaultReorder => _thread ? 10 : _unit == Consumable.unitGrams ? 200 : 0;

  @override
  void initState() {
    super.initState();
    _reorder.text = _defaultReorder.toString();
    _pack.text = _thread ? '2000' : _unit == Consumable.unitGrams ? '500' : '';
  }

  @override
  void dispose() {
    _name.dispose();
    _colour.dispose();
    _size.dispose();
    _finish.dispose();
    _pack.dispose();
    _reorder.dispose();
    super.dispose();
  }

  void _categoryChanged(String? value) {
    if (value == null) return;
    setState(() {
      _category = value;
      _reorder.text = _defaultReorder.toString();
      _pack.text = _thread ? '2000' : _unit == Consumable.unitGrams ? '500' : '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add consumable'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: Consumable.categories.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                onChanged: _categoryChanged,
              ),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Item name'), validator: (value) => value == null || value.trim().isEmpty ? 'Enter a name' : null),
              TextFormField(controller: _colour, decoration: const InputDecoration(labelText: 'Colour / colour code (optional)')),
              if (_category == Consumable.categoryBeads) ...[
                TextFormField(controller: _size, decoration: const InputDecoration(labelText: 'Size (e.g. 2mm, 2.5mm, 4mm)')),
                TextFormField(controller: _finish, decoration: const InputDecoration(labelText: 'Finish / type (e.g. Cut, Zardosi)')),
              ],
              if (_category == Consumable.categoryStabilizers)
                DropdownButtonFormField<String>(
                  value: _finish.text.isEmpty ? null : _finish.text,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'Tear-away', child: Text('Tear-away')),
                    DropdownMenuItem(value: 'Cut-away', child: Text('Cut-away')),
                    DropdownMenuItem(value: 'Water-soluble', child: Text('Water-soluble')),
                  ],
                  onChanged: (value) => _finish.text = value ?? '',
                ),
              TextFormField(
                controller: _pack,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: _thread ? 'Default spool length (m)' : 'Default pack quantity ($_unit)'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final parsed = double.tryParse(value);
                  return parsed == null || parsed <= 0 ? 'Enter a positive quantity' : null;
                },
              ),
              TextFormField(
                controller: _reorder,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Reorder threshold ($_unit)'),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  return parsed == null || parsed < 0 ? 'Enter zero or a positive quantity' : null;
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_thread
                  ? 'Thread is tracked per spool. Low-stock alert is below 10% remaining.'
                  : _unit == Consumable.unitGrams
                    ? 'Stock is stored in grams and displayed in kilograms.'
                    : _unit == Consumable.unitCount
                      ? 'Stock is tracked as pieces / cassettes.'
                      : 'Stock is tracked in millilitres.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final now = DateTime.now();
            final packText = _pack.text.trim();
            Navigator.pop(context, Consumable(
              category: _category,
              name: _name.text.trim(),
              colour: _colour.text.trim().isEmpty ? null : _colour.text.trim(),
              size: _size.text.trim().isEmpty ? null : _size.text.trim(),
              finish: _finish.text.trim().isEmpty ? null : _finish.text.trim(),
              trackingType: _tracking,
              stockUnit: _unit,
              reorderLevel: double.parse(_reorder.text.trim()),
              defaultPackQuantity: packText.isEmpty ? null : double.parse(packText),
              createdAt: now,
              updatedAt: now,
            ));
          },
          child: const Text('Save item'),
        ),
      ],
    );
  }
}

class _StockEntry {
  const _StockEntry(this.quantity, this.opening, this.costPaise, this.notes);
  final double quantity;
  final bool opening;
  final int? costPaise;
  final String? notes;
}

class _StockEntryDialog extends StatefulWidget {
  const _StockEntryDialog({required this.item});
  final Consumable item;

  @override
  State<_StockEntryDialog> createState() => _StockEntryDialogState();
}

class _StockEntryDialogState extends State<_StockEntryDialog> {
  final _quantity = TextEditingController();
  final _cost = TextEditingController();
  final _notes = TextEditingController();
  bool _opening = false;

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_opening ? 'Record opening stock' : 'Record purchase'),
    content: SizedBox(
      width: 420,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Quantity (${widget.item.stockUnit})')),
        TextField(controller: _cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total cost (₹, optional)')),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('This is opening stock'), value: _opening, onChanged: (value) => setState(() => _opening = value)),
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () {
        final quantity = double.tryParse(_quantity.text.trim());
        final cost = _cost.text.trim().isEmpty ? null : double.tryParse(_cost.text.trim());
        if (quantity == null || quantity <= 0 || (cost != null && cost < 0)) return;
        Navigator.pop(context, _StockEntry(
          quantity,
          _opening,
          cost == null ? null : (cost * 100).round(),
          _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        ));
      }, child: const Text('Save')),
    ],
  );
}

class _SpoolEntry {
  const _SpoolEntry(this.lengthM, this.costPaise, this.notes);
  final double lengthM;
  final int? costPaise;
  final String? notes;
}

class _SpoolEntryDialog extends StatefulWidget {
  const _SpoolEntryDialog({required this.item});
  final Consumable item;

  @override
  State<_SpoolEntryDialog> createState() => _SpoolEntryDialogState();
}

class _SpoolEntryDialogState extends State<_SpoolEntryDialog> {
  late final TextEditingController _length;
  final _cost = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _length = TextEditingController(text: (widget.item.defaultPackQuantity ?? 2000).toStringAsFixed(0));
  }

  @override
  void dispose() {
    _length.dispose();
    _cost.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Add ${widget.item.name} spool'),
    content: SizedBox(
      width: 420,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _length, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Approximate spool length (m)')),
        TextField(controller: _cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost (₹, optional)')),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)')),
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () {
        final length = double.tryParse(_length.text.trim());
        final cost = _cost.text.trim().isEmpty ? null : double.tryParse(_cost.text.trim());
        if (length == null || length <= 0 || (cost != null && cost < 0)) return;
        Navigator.pop(context, _SpoolEntry(
          length,
          cost == null ? null : (cost * 100).round(),
          _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        ));
      }, child: const Text('Add spool')),
    ],
  );
}
