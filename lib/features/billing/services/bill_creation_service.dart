import '../../customers/repositories/customer_repository.dart';
import '../../invoices/repositories/invoice_repository.dart';
import '../../orders/models/order.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../repositories/bill_repository.dart';

class BillCreationService {
  final BillRepository billRepository;
  final InvoiceRepository invoiceRepository;
  final CustomerRepository customerRepository;

  BillCreationService({
    BillRepository? billRepository,
    InvoiceRepository? invoiceRepository,
    CustomerRepository? customerRepository,
  })  : billRepository = billRepository ?? BillRepository(),
        invoiceRepository = invoiceRepository ?? InvoiceRepository(),
        customerRepository = customerRepository ?? CustomerRepository();

  Future<Bill> createForOrder(Order order) async {
    if (order.status != 'Completed') {
      throw StateError('A bill can only be generated for a completed order.');
    }
    if (order.id == null) {
      throw StateError('The completed order does not have a local ID.');
    }

    final existing = await billRepository.getByOrderUuid(order.uuid);
    if (existing != null) return existing;

    final invoice = await invoiceRepository.getByOrderUuid(order.uuid);
    if (invoice == null || invoice.id == null) {
      throw StateError(
        'No invoice exists for ${order.orderNumber}. '
        'An invoice must be generated before completion.',
      );
    }

    final customer = await customerRepository.getById(order.customerId);
    if (customer == null || customer.id == null) {
      throw StateError(
        'The customer for ${order.orderNumber} could not be found.',
      );
    }

    final invoiceItems = await invoiceRepository.getItems(invoice.id!);
    if (invoiceItems.isEmpty) {
      throw StateError('The invoice for ${order.orderNumber} has no items.');
    }

    final now = DateTime.now();
    final bill = Bill(
      customerId: customer.id!,
      customerUuid: customer.uuid,
      orderId: order.id,
      orderUuid: order.uuid,
      billNumber: _billNumber(now),
      billDate: now,
      subtotalPaise: invoice.subtotalPaise,
      discountPaise: 0,
      taxPaise: 0,
      totalPaise: invoice.totalPaise,
      amountPaidPaise: invoice.totalPaise,
      notes: invoice.notes,
      createdAt: now,
      updatedAt: now,
    );

    final items = invoiceItems
        .map(
          (item) => BillItem(
            billId: 0,
            description: item.description,
            quantity: item.quantity,
            ratePaise: item.ratePaise,
            amountPaise: item.amountPaise,
          ),
        )
        .toList();

    final id = await billRepository.insert(bill: bill, items: items);
    final created = await billRepository.getById(id);
    if (created == null) {
      throw StateError('The bill was created but could not be loaded.');
    }

    return created;
  }

  String _billNumber(DateTime value) {
    return 'BILL-${value.year}'
        '${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}-'
        '${value.hour.toString().padLeft(2, '0')}'
        '${value.minute.toString().padLeft(2, '0')}'
        '${value.second.toString().padLeft(2, '0')}'
        '${value.microsecond.toString().padLeft(6, '0')}';
  }
}
