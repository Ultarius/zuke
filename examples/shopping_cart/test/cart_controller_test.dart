import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_cart/shopping_cart.dart';

void main() {
  group('CartController', () {
    test('rejects blank identifiers and invalid prices', () {
      final cart = CartController();

      expect(cart.addItem('', 'Headphones', 100), isFalse);
      expect(cart.errorMessage, 'Catalog item details are invalid');
      expect(cart.addItem('headphones', '', 100), isFalse);
      expect(cart.addItem('headphones', 'Headphones', 0), isFalse);
      expect(cart.addItem('headphones', 'Headphones', double.nan), isFalse);
      expect(cart.items, isEmpty);
    });

    test('rejects promos for an empty cart and invalid promo codes', () {
      final cart = CartController();

      cart.applyPromoCode('SAVE20');
      expect(cart.discountPercentage, 0.0);
      expect(cart.errorMessage, 'Add an item before applying a promo code');

      expect(cart.addItem('headphones', 'Headphones', 100), isTrue);
      cart.applyPromoCode('NOT-A-CODE');
      expect(cart.discountPercentage, 0.0);
      expect(cart.errorMessage, 'Invalid promo code');
    });

    test('does not allow checkout with an empty cart', () {
      final cart = CartController();

      expect(cart.attemptCheckout(), isFalse);
      expect(cart.isErrorStatus, isTrue);
      expect(
        cart.statusMessage,
        'Cart is empty. Add items before checking out.',
      );
    });

    test(
      'allows checkout with items in cart, sets success status, and resets cart state',
      () {
        final cart = CartController();

        expect(cart.addItem('headphones', 'Headphones', 100), isTrue);
        cart.applyPromoCode('SAVE20');
        expect(cart.discountPercentage, 0.20);
        expect(cart.subtotal, 100.0);
        expect(cart.discountAmount, 20.0);
        expect(cart.grandTotal, 80.0);
        expect(cart.attemptCheckout(), isTrue);
        expect(cart.isErrorStatus, isFalse);
        expect(cart.statusMessage, 'Order placed successfully!');
        expect(cart.items, isEmpty);
        expect(cart.totalItemCount, 0);
        expect(cart.subtotal, 0.0);
        expect(cart.grandTotal, 0.0);
      },
    );
  });
}
