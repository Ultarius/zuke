import 'package:flutter/foundation.dart';
import 'package:zuke_annotations/zuke_annotations.dart';

class CartItemModel {
  final String id;
  final String name;
  final double price;
  int quantity;

  CartItemModel({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
  });
}

@ImplementsRequirement([
  'RULE-CART-ITEM-MANAGEMENT',
  'RULE-CART-PROMO-DISCOUNT',
  'RULE-CART-EMPTY-CHECKOUT',
  'RULE-CART-SUCCESSFUL-CHECKOUT',
])
@ProvidesControl(
  ['CTRL-CART-VALIDATION', 'CTRL-PROMO-VALIDATION'],
  kind: ControlProviderKind.applicationValidator,
  layer: EnforcementLayer.presentation,
)
class CartController extends ChangeNotifier {
  final List<CartItemModel> _items = [];
  String _promoCode = '';
  double _discountPercentage = 0.0;
  String _statusMessage = '';
  bool _isErrorStatus = false;

  List<CartItemModel> get items => List.unmodifiable(_items);
  int get totalItemCount => _items.fold(0, (sum, i) => sum + i.quantity);
  String get statusMessage => _statusMessage;
  bool get isErrorStatus => _isErrorStatus;
  String get errorMessage => _isErrorStatus ? _statusMessage : '';
  String get promoStatus => _discountPercentage > 0
      ? 'Discount Applied: ${(discountPercentage * 100).toInt()}%'
      : '';

  double get subtotal =>
      _items.fold(0.0, (sum, i) => sum + (i.price * i.quantity));
  double get discountPercentage => _discountPercentage;
  double get discountAmount => subtotal * _discountPercentage;
  double get grandTotal =>
      (subtotal - discountAmount).clamp(0.0, double.infinity);
  bool get isCartEmpty => _items.isEmpty;

  bool addItem(String id, String name, double price) {
    _statusMessage = '';
    _isErrorStatus = false;
    // Defensive controller guard: the catalog UI supplies only validated
    // constants, while unit tests cover malformed catalog input directly.
    if (id.trim().isEmpty ||
        name.trim().isEmpty ||
        !price.isFinite ||
        price <= 0) {
      _statusMessage = 'Catalog item details are invalid';
      _isErrorStatus = true;
      notifyListeners();
      return false;
    }
    final existingIndex = _items.indexWhere((item) => item.id == id);
    if (existingIndex >= 0) {
      _items[existingIndex].quantity += 1;
    } else {
      _items.add(CartItemModel(id: id, name: name, price: price));
    }
    notifyListeners();
    return true;
  }

  void applyPromoCode(String code) {
    _promoCode = code.trim().toUpperCase();
    _statusMessage = '';
    _isErrorStatus = false;
    if (_promoCode.isNotEmpty && isCartEmpty) {
      _discountPercentage = 0.0;
      _statusMessage = 'Add an item before applying a promo code';
      _isErrorStatus = true;
    } else if (_promoCode == 'SAVE20') {
      _discountPercentage = 0.20;
    } else if (_promoCode == 'SAVE50') {
      _discountPercentage = 0.50;
    } else if (_promoCode.isNotEmpty) {
      _discountPercentage = 0.0;
      _statusMessage = 'Invalid promo code';
      _isErrorStatus = true;
    } else {
      _discountPercentage = 0.0;
      _statusMessage = 'Please enter a promo code';
      _isErrorStatus = true;
    }
    notifyListeners();
  }

  bool attemptCheckout() {
    if (isCartEmpty) {
      _statusMessage = 'Cart is empty. Add items before checking out.';
      _isErrorStatus = true;
      notifyListeners();
      return false;
    }
    _items.clear();
    _promoCode = '';
    _discountPercentage = 0.0;
    _statusMessage = 'Order placed successfully!';
    _isErrorStatus = false;
    notifyListeners();
    return true;
  }

  void clear() {
    _items.clear();
    _promoCode = '';
    _discountPercentage = 0.0;
    _statusMessage = '';
    _isErrorStatus = false;
    notifyListeners();
  }
}
