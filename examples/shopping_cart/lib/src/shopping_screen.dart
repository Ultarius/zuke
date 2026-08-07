import 'package:flutter/material.dart';
import 'cart_controller.dart';
import 'generated/feat_cart_001_contracts.g.dart';
import 'package:zuke_annotations/zuke_annotations.dart';

@PresentsRequirement(['RULE-CART-ACCESSIBILITY'], target: 'flutter')
@ProvidesControl(
  ['CTRL-CART-ACCESSIBLE'],
  kind: ControlProviderKind.semanticsProvider,
  layer: EnforcementLayer.presentation,
  target: 'flutter',
)
class ShoppingScreen extends StatefulWidget {
  final CartController controller;
  final FeatCart001FlutterBindings<Key> bindings;

  const ShoppingScreen({
    super.key,
    required this.controller,
    required this.bindings,
  });

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  final TextEditingController _promoTextController = TextEditingController();

  @override
  void dispose() {
    _promoTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Tech Store Catalog'),
            actions: [
              Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.shopping_cart, size: 28),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.red,
                      child: Text(
                        '${ctrl.totalItemCount}',
                        key: widget.bindings.cartBadge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Catalog Item Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.headphones,
                      size: 40,
                      color: Colors.indigo,
                    ),
                    title: Text(
                      'Wireless Headphones',
                      key: widget.bindings.catalogItemName,
                    ),
                    subtitle: Text(
                      '\$100.00',
                      key: widget.bindings.catalogItemPrice,
                    ),
                    trailing: ElevatedButton(
                      key: widget.bindings.addToCartHeadphones,
                      onPressed: () {
                        ctrl.addItem(
                          'headphone-1',
                          'Wireless Headphones',
                          100.0,
                        );
                      },
                      child: const Text('Add to Cart'),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Cart & Order Summary
                const Text(
                  'Order Summary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal:'),
                    Text(
                      '\$${ctrl.subtotal.toStringAsFixed(2)}',
                      key: widget.bindings.subtotalDisplay,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (ctrl.promoStatus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    ctrl.promoStatus,
                    key: widget.bindings.discountStatusDisplay,
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                // Accessibility Semantics Wrapper for Grand Total Summary
                Semantics(
                  label: 'Order Total: \$${ctrl.grandTotal.toStringAsFixed(2)}',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '\$${ctrl.grandTotal.toStringAsFixed(2)}',
                        key: widget.bindings.totalDisplay,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Promo Code Input
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: widget.bindings.promoInput,
                        controller: _promoTextController,
                        decoration: const InputDecoration(
                          hintText: 'Enter Promo Code (e.g. SAVE20)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      key: widget.bindings.applyPromoButton,
                      onPressed: () {
                        ctrl.applyPromoCode(_promoTextController.text);
                      },
                      child: const Text('Apply Promo'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Status Message Display
                if (ctrl.statusMessage.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ctrl.isErrorStatus
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ctrl.isErrorStatus
                            ? Colors.red.shade200
                            : Colors.green.shade200,
                      ),
                    ),
                    child: Text(
                      ctrl.statusMessage,
                      key: widget.bindings.statusMessageDisplay,
                      style: TextStyle(
                        color: ctrl.isErrorStatus
                            ? Colors.red.shade800
                            : Colors.green.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Checkout Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: widget.bindings.checkoutButton,
                    onPressed: ctrl.isCartEmpty
                        ? null
                        : () {
                            ctrl.attemptCheckout();
                            _promoTextController.clear();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Proceed to Checkout',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
