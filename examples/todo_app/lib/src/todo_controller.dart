import 'package:flutter/foundation.dart';
import 'package:zuke_annotations/zuke_annotations.dart';

class TodoItemModel {
  final String id;
  final String text;
  bool isCompleted;

  TodoItemModel({
    required this.id,
    required this.text,
    this.isCompleted = false,
  });
}

@ImplementsRequirement(['RULE-TODO-ADD-ITEM', 'RULE-TODO-COMPLETE-ITEM'])
@ProvidesControl(
  ['CTRL-TODO-VALIDATION'],
  kind: ControlProviderKind.applicationValidator,
  layer: EnforcementLayer.presentation,
)
class TodoController extends ChangeNotifier {
  final List<TodoItemModel> _tasks = [];
  int _nextId = 1;
  String _errorMessage = '';

  List<TodoItemModel> get tasks => List.unmodifiable(_tasks);
  int get activeTaskCount => _tasks.where((task) => !task.isCompleted).length;
  String get errorMessage => _errorMessage;
  bool get hasTasks => _tasks.isNotEmpty;

  bool addTask(String text) {
    _errorMessage = '';
    if (text.trim().isEmpty) {
      _errorMessage = 'Task text cannot be empty';
      notifyListeners();
      return false;
    }
    _tasks.add(TodoItemModel(id: 'task-${_nextId++}', text: text.trim()));
    notifyListeners();
    return true;
  }

  void toggleTask(String id) {
    final task = _tasks.firstWhere(
      (t) => t.id == id,
      orElse: () => TodoItemModel(id: '', text: ''),
    );
    if (task.id.isEmpty) return;
    task.isCompleted = !task.isCompleted;
    notifyListeners();
  }

  void clearCompleted() {
    _tasks.removeWhere((task) => task.isCompleted);
    notifyListeners();
  }

  void clear() {
    _tasks.clear();
    _nextId = 1;
    _errorMessage = '';
    notifyListeners();
  }
}
