import 'package:flutter/material.dart';
import 'todo_app.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TodoScreen(controller: TodoController(), bindings: TodoBindings()),
    ),
  );
}
