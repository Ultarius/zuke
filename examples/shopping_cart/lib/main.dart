import 'package:flutter/material.dart';
import 'shopping_cart.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ShoppingScreen(
        controller: CartController(),
        bindings: ShoppingBindings(),
      ),
    ),
  );
}
