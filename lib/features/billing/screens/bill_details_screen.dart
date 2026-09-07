import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../customers/models/customer.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../repositories/bill_repository.dart';
import '../services/bill_pdf_service.dart';

class BillDetailsScreen extends StatefulWidget {
  const BillDetailsScreen({super.key, required this.bill, required this.repository, required this.customer});
  final Bill bill; final BillRepository repository; final Customer customer;
  @override State<BillDetailsScreen> createState()=>_BillDetailsScreenState();
}
class _BillDetailsScreenState extends State<BillDetailsScreen>{
  late Future<List<BillItem>> _items; bool _busy=false;
  @override void initState(){super.initState();_items=widget.repository.getItems(widget.bill.id!);}
  String money(int p)=>'Rs. ${(p/100).toStringAsFixed(2)}';
  String date(DateTime d)=>'${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
  Future<List<int>> pdf(List<BillItem> i)=>BillPdfService.generate(bill:widget.bill,items:i,customer:widget.customer);
  Future<void> preview(List<BillItem> i) async { if(widget.bill.amountPaidPaise!=widget.bill.totalPaise){_err('A bill can only be generated after full payment.');return;} setState(()=>_busy=true); try{final b=await pdf(i);await Printing.layoutPdf(onLayout:(_)=>b,name:'${widget.bill.billNumber}.pdf');}catch(e){_err('Unable to generate PDF: $e');}finally{if(mounted)setState(()=>_busy=false);}}
  Future<void> share(List<BillItem> i) async { if(widget.bill.amountPaidPaise!=widget.bill.totalPaise){_err('A bill can only be generated after full payment.');return;} setState(()=>_busy=true); try{final b=await pdf(i);await Printing.sharePdf(bytes:b,filename:'${widget.bill.billNumber}.pdf');}catch(e){_err('Unable to share PDF: $e');}finally{if(mounted)setState(()=>_busy=false);}}
  void _err(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Bill Details')),body:FutureBuilder<List<BillItem>>(future:_items,builder:(c,s){if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());if(s.hasError)return Center(child:Text('Unable to load bill items.\n${s.error}'));final items=s.data??[];return ListView(padding:const EdgeInsets.all(24),children:[Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[const Icon(Icons.receipt_long,size:32),const SizedBox(width:12),Expanded(child:Text(widget.bill.billNumber,style:Theme.of(context).textTheme.headlineSmall)),const Chip(label:Text('Paid'))]),const SizedBox(height:12),Text('Bill date: ${date(widget.bill.billDate)}'),const SizedBox(height:18),Wrap(spacing:12,runSpacing:12,children:[FilledButton.icon(onPressed:_busy?null:()=>preview(items),icon:const Icon(Icons.picture_as_pdf),label:const Text('View / Print PDF')),OutlinedButton.icon(onPressed:_busy?null:()=>share(items),icon:const Icon(Icons.share),label:const Text('Share PDF'))])])),),const SizedBox(height:18),Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Customer',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),Text(widget.customer.name,style:const TextStyle(fontWeight:FontWeight.w600)),if(widget.customer.phone!=null)Text(widget.customer.phone!),if(widget.customer.whatsapp!=null)Text('WhatsApp: ${widget.customer.whatsapp!}')]))),const SizedBox(height:18),Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[const Align(alignment:Alignment.centerLeft,child:Text('Items',style:TextStyle(fontSize:20,fontWeight:FontWeight.w600))),const SizedBox(height:12),...items.map((i)=>Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Row(children:[Expanded(child:Text(i.description)),Text('${i.quantity} × ${money(i.ratePaise)}'),const SizedBox(width:16),Text(money(i.amountPaise),style:const TextStyle(fontWeight:FontWeight.w600))])))]))),const SizedBox(height:18),Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[_r('Subtotal',widget.bill.subtotalPaise),if(widget.bill.discountPaise!=0)_r('Discount',widget.bill.discountPaise),if(widget.bill.taxPaise!=0)_r('Tax',widget.bill.taxPaise),const Divider(),_r('Total',widget.bill.totalPaise,true),_r('Amount Received',widget.bill.amountPaidPaise,true)]))),if(widget.bill.notes?.trim().isNotEmpty==true)Padding(padding:const EdgeInsets.only(top:18),child:Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Notes',style:TextStyle(fontSize:20,fontWeight:FontWeight.w600)),const SizedBox(height:8),Text(widget.bill.notes!)]))))]);});
  Widget _r(String l,int p,[bool b=false])=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[Expanded(child:Text(l,style:b?const TextStyle(fontWeight:FontWeight.w700):null)),Text(money(p),style:b?const TextStyle(fontWeight:FontWeight.w700):null)]));
}
