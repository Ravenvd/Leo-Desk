import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../repositories/invoice_repository.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../orders/models/order.dart';
import '../../orders/repositories/order_repository.dart';

class InvoiceCreationService {
  final InvoiceRepository invoiceRepository;
  final OrderRepository orderRepository;
  final CustomerRepository customerRepository;

  InvoiceCreationService({
    InvoiceRepository? invoiceRepository,
    OrderRepository? orderRepository,
    CustomerRepository? customerRepository,
  })  : invoiceRepository = invoiceRepository ?? InvoiceRepository(),
        orderRepository = orderRepository ?? OrderRepository(),
        customerRepository = customerRepository ?? CustomerRepository();

  Future<Invoice> createForOrder(Order order) async {
    if (order.id == null) {
      throw StateError('Cannot create an invoice for an order without an ID.');
    }
    if (order.status != 'In Progress') {
      throw StateError('Invoice can only be generated when an order is In Progress.');
    }

    final existing = await invoiceRepository.getByOrderUuid(order.uuid);
    if (existing != null) return existing;

    final customer = await customerRepository.getById(order.customerId);
    if (customer == null) {
      throw StateError('Customer could not be found for the order.');
    }

    final orderItems = await orderRepository.getItems(order.id!);
    if (orderItems.isEmpty) {
      throw StateError('An invoice cannot be created for an order without items.');
    }

    final items = <InvoiceItem>[
      for (final item in orderItems)
        InvoiceItem(
          invoiceId: 0,
          description: '${item.workType} - ${item.garmentType}${item.notes?.trim().isNotEmpty == true ? ' | ${item.notes}' : ''}',
          quantity: item.quantity.toDouble(),
          ratePaise: item.unitPricePaise,
          amountPaise: item.quantity * item.unitPricePaise,
        ),
      if (order.stitchingRequired && order.stitchingPricePaise > 0)
        InvoiceItem(
          invoiceId: 0,
          description: 'Stitching',
          quantity: 1,
          ratePaise: order.stitchingPricePaise,
          amountPaise: order.stitchingPricePaise,
        ),
    ];

    final subtotal = items.fold<int>(0, (sum, item) => sum + item.amountPaise);
    final now = DateTime.now();

    return invoiceRepository.create(
      invoice: Invoice(
        orderId: order.id!,
        orderUuid: order.uuid,
        customerId: order.customerId,
        customerUuid: customer.uuid,
        invoiceNumber: 'INV-${_orderNumber(order.orderNumber)}',
        invoiceDate: now,
        subtotalPaise: subtotal,
        totalPaise: subtotal,
        notes: order.notes,
        createdAt: now,
        updatedAt: now,
      ),
      items: items,
    );
  }

  String _orderNumber(String value) =>
      value.startsWith('ORD-') ? value.substring(4) : value;
}
