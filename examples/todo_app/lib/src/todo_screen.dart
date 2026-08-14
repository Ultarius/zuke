import 'package:flutter/material.dart';
import 'todo_controller.dart';
import 'generated/feat_todo_001_contracts.g.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

@PresentsRequirement(['RULE-TODO-COMPLETE-ITEM'], target: 'flutter')
@ProvidesControl(
  ['CTRL-TODO-ACCESSIBLE'],
  kind: ControlProviderKind.semanticsProvider,
  layer: EnforcementLayer.presentation,
)
class TodoScreen extends StatefulWidget {
  final TodoController controller;
  final FeatTodo001FlutterBindings<FlutterBindingKey> bindings;

  const TodoScreen({
    super.key,
    required this.controller,
    required this.bindings,
  });

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        return Scaffold(
          appBar: AppBar(title: const Text('Todo List')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: widget.bindings.taskInput,
                        controller: _textController,
                        decoration: const InputDecoration(
                          hintText: 'Enter a task',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      key: widget.bindings.addTaskButton,
                      onPressed: () {
                        ctrl.addTask(_textController.text);
                        _textController.clear();
                      },
                      child: const Text('Add Task'),
                    ),
                  ],
                ),
              ),
              if (ctrl.errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    ctrl.errorMessage,
                    key: widget.bindings.errorMessage,
                    style: TextStyle(color: Colors.red.shade800),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${ctrl.activeTaskCount} ${ctrl.activeTaskCount == 1 ? 'item' : 'items'} left',
                      key: widget.bindings.taskCountDisplay,
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (ctrl.tasks.any((t) => t.isCompleted))
                      TextButton(
                        key: widget.bindings.clearCompletedButton,
                        onPressed: ctrl.clearCompleted,
                        child: const Text('Clear completed'),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ctrl.hasTasks
                    ? ListView.builder(
                        key: widget.bindings.taskList,
                        itemCount: ctrl.tasks.length,
                        itemBuilder: (context, index) {
                          final task = ctrl.tasks[index];
                          return ListTile(
                            key: ValueKey(task.id),
                            leading: Checkbox(
                              key: widget.bindings.taskItemCheckbox.instance(
                                task.id,
                              ),
                              value: task.isCompleted,
                              onChanged: (_) => ctrl.toggleTask(task.id),
                            ),
                            title: Text(
                              task.text,
                              key: widget.bindings.taskItemText.instance(
                                task.id,
                              ),
                              style: TextStyle(
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Text(
                          'No tasks yet',
                          key: widget.bindings.emptyStateMessage,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
