import 'package:flutter/material.dart';

import '../../customers/models/customer.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../repositories/bill_repository.dart';

class CreateBillScreen extends StatefulWidget {
  const CreateBillScreen({super.key, required this.customer, required this.repository});
  final Customer customer;
  final BillRepository repository;
  @override
  State<CreateBillScreen> createState() => _CreateBillScreenState();
}

class _CreateBillScreenState extends State<CreateBillScreen> {
  final _formKey = GlobalKey<FormState>();
  final _discountController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');
  final _amountPaidController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  DateTime _billDate = DateTime.now();
  bool _isSaving = false;
  final List<_BillLineController> _items = [_BillLineController()];

  @override
  void initState() { super.initState(); _discountController.addListener(_refresh); _taxController.addListener(_refresh); _amountPaidController.addListener(_refresh); }
  @override
  void dispose() { _discountController..removeListener(_refresh)..dispose(); _taxController..removeListener(_refresh)..dispose(); _amountPaidController..removeListener(_refresh)..dispose(); _notesController.dispose(); for (final i in _items) { i.dispose(); } super.dispose(); }
  void _refresh() { if (mounted) setState(() {}); }
  int _paise(String v) => ((double.tryParse(v.trim()) ?? 0) * 100).round();
  int get _subtotal => _items.fold(0, (s, i) => s + i.amountPaise);
  int get _discount => _paise(_discountController.text);
  int get _tax => _paise(_taxController.text);
  int get _total => _subtotal - _discount + _tax;
  int get _received => _paise(_amountPaidController.text);
  String _money(int p) => 'Rs. ${(p / 100).toStringAsFixed(2)}';
  String _billNumber() { final n = DateTime.now(); return 'BILL-${n.year}${n.month.toString().padLeft(2,'0')}${n.day.toString().padLeft(2,'0')}-${n.hour.toString().padLeft(2,'0')}${n.minute.toString().padLeft(2,'0')}${n.second.toString().padLeft(2,'0')}'; }

  Future<void> _saveBill() async {
    if (!_formKey.currentState!.validate()) return;
    if (_total < 0) { _error('Total cannot be negative.'); return; }
    if (_received != _total) { _error('The full amount must be received before a bill can be created.'); return; }
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final bill = Bill(customerId: widget.customer.id!, billNumber: _billNumber(), billDate: _billDate, subtotalPaise: _subtotal, discountPaise: _discount, taxPaise: _tax, totalPaise: _total, amountPaidPaise: _received, notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(), createdAt: now, updatedAt: now);
      final items = _items.map((i) => BillItem(billId: 0, description: i.descriptionController.text.trim(), quantity: i.quantity, ratePaise: i.ratePaise, amountPaise: i.amountPaise)).toList();
      final id = await widget.repository.insert(bill: bill, items: items);
      if (!mounted) return; setState(() => _isSaving = false); Navigator.pop(context, id);
    } catch (e) { if (!mounted) return; setState(() => _isSaving = false); _error('Unable to save bill: $e'); debugPrint('Bill save error: $e'); }
  }
  void _error(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  Future<void> _date() async { final d = await showDatePicker(context: context, initialDate: _billDate, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d != null) setState(() => _billDate = d); }
  void _add() => setState(() => _items.add(_BillLineController()));
  void _remove(int i) { if (_items.length == 1) return; _items.removeAt(i).dispose(); setState(() {}); }
  Widget _moneyField(TextEditingController c, String label) => TextFormField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: label, prefixText: 'Rs. ', border: const OutlineInputBorder()), validator: (v) { final x = double.tryParse(v?.trim() ?? ''); return x == null || x < 0 ? 'Enter a valid amount' : null; });
  Widget _row(String label, int value, {bool bold = false}) => Row(children: [Expanded(child: Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null)), Text(_money(value), style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null)]);

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Create Bill')), body: Form(key: _formKey, child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_customerCard(), const SizedBox(height: 20), _info(), const SizedBox(height: 20), _itemsCard(), const SizedBox(height: 20), _totals(), const SizedBox(height: 20), TextField(controller: _notesController, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder())), const SizedBox(height: 24), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _isSaving || _received != _total ? null : _saveBill, icon: const Icon(Icons.receipt_long_rounded), label: Text(_isSaving ? 'Saving...' : 'Save Bill')))])))));

  Widget _customerCard() => Card(child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [CircleAvatar(child: Text(widget.customer.name.isEmpty ? '?' : widget.customer.name.substring(0,1).toUpperCase())), const SizedBox(width: 14), Expanded(child: Text(widget.customer.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18))), const Chip(label: Text('Customer'))])));
  Widget _info() => Card(child: Padding(padding: const EdgeInsets.all(20), child: Wrap(spacing: 24, runSpacing: 16, children: [SizedBox(width:260, child: InputDecorator(decoration: const InputDecoration(labelText:'Bill Number', border:OutlineInputBorder()), child: Text(_billNumber()))), SizedBox(width:260, child: InkWell(onTap:_date, child: InputDecorator(decoration: const InputDecoration(labelText:'Bill Date', border:OutlineInputBorder()), child: Text('${_billDate.day.toString().padLeft(2,'0')}/${_billDate.month.toString().padLeft(2,'0')}/${_billDate.year}'))))])));
  Widget _itemsCard() => Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [Row(children:[const Expanded(child:Text('Items',style:TextStyle(fontSize:20,fontWeight:FontWeight.w600))), OutlinedButton.icon(onPressed:_add, icon:const Icon(Icons.add), label:const Text('Add Item'))]), const SizedBox(height:16), ...List.generate(_items.length, _itemRow)])));
  Widget _itemRow(int index) { final i=_items[index]; return Padding(padding:const EdgeInsets.only(bottom:14), child: LayoutBuilder(builder:(context,c){ final desc=TextFormField(controller:i.descriptionController, decoration:const InputDecoration(labelText:'Description',border:OutlineInputBorder()), validator:(v)=>v==null||v.trim().isEmpty?'Required':null); final qty=TextFormField(controller:i.quantityController,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Qty',border:OutlineInputBorder()),onChanged:(_)=>setState((){}),validator:(v)=>double.tryParse(v?.trim()??'')==null||double.parse(v!.trim())<=0?'Invalid':null); final rate=TextFormField(controller:i.rateController,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Rate',prefixText:'Rs. ',border:OutlineInputBorder()),onChanged:(_)=>setState((){}),validator:(v)=>double.tryParse(v?.trim()??'')==null||double.parse(v!.trim())<0?'Invalid':null); final amount=InputDecorator(decoration:const InputDecoration(labelText:'Amount',border:OutlineInputBorder()),child:Text(_money(i.amountPaise))); if(c.maxWidth<650)return Column(children:[desc,const SizedBox(height:10),Row(children:[Expanded(child:qty),const SizedBox(width:10),Expanded(child:rate)]),const SizedBox(height:10),Row(children:[Expanded(child:amount),IconButton(onPressed:_items.length==1?null:()=>_remove(index),icon:const Icon(Icons.delete_outline))])]); return Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:desc),const SizedBox(width:10),SizedBox(width:100,child:qty),const SizedBox(width:10),SizedBox(width:140,child:rate),const SizedBox(width:10),SizedBox(width:140,child:amount),IconButton(onPressed:_items.length==1?null:()=>_remove(index),icon:const Icon(Icons.delete_outline))]); })); }
  Widget _totals() => Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[_row('Subtotal',_subtotal),const SizedBox(height:10),Row(children:[const Expanded(child:Text('Discount')),SizedBox(width:180,child:_moneyField(_discountController,'Discount'))]),const SizedBox(height:10),Row(children:[const Expanded(child:Text('Tax')),SizedBox(width:180,child:_moneyField(_taxController,'Tax'))]),const Divider(height:28),_row('Total',_total,bold:true),const SizedBox(height:10),Row(children:[const Expanded(child:Text('Amount Received')),SizedBox(width:180,child:_moneyField(_amountPaidController,'Received'))]),if(_received!=_total) Align(alignment:Alignment.centerLeft,child:Text('Full payment is required before the bill can be saved.',style:TextStyle(color:Theme.of(context).colorScheme.error,fontSize:12)))]));
}
class _BillLineController { final descriptionController=TextEditingController(); final quantityController=TextEditingController(text:'1'); final rateController=TextEditingController(text:'0'); double get quantity=>double.tryParse(quantityController.text.trim())??0; int get ratePaise=>((double.tryParse(rateController.text.trim())??0)*100).round(); int get amountPaise=>(quantity*ratePaise).round(); void dispose(){descriptionController.dispose();quantityController.dispose();rateController.dispose();} }
