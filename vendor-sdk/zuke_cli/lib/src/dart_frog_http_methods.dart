import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

/// Recognizes a leading method guard that returns 405 for all other methods.
/// Unsupported control flow remains unknown; occurrences of HttpMethod alone
/// are not evidence of a route's method contract.
List<String> dartFrogHttpMethods(FunctionDeclaration handler) {
  final body = handler.functionExpression.body;
  final parameters = handler.functionExpression.parameters?.parameters;
  if (body is! BlockFunctionBody ||
      body.block.statements.isEmpty ||
      parameters == null ||
      parameters.isEmpty) {
    return const [];
  }
  final guard = body.block.statements.first;
  if (guard is! IfStatement || guard.elseStatement != null) return const [];
  final rejection = guard.thenStatement;
  final statement = rejection is Block && rejection.statements.length == 1
      ? rejection.statements.single
      : rejection;
  if (statement is! ReturnStatement) return const [];
  final response = statement.expression;
  if (response is! InstanceCreationExpression ||
      response.constructorName.element?.enclosingElement.name != 'Response' ||
      !_dartFrog(response.constructorName.element)) {
    return const [];
  }
  final status = response.argumentList.arguments
      .whereType<NamedExpression>()
      .where((argument) => argument.name.label.name == 'statusCode');
  if (status.length != 1 || _integer(status.single.expression) != 405) {
    return const [];
  }
  final context = parameters.first.declaredFragment?.element;
  Set<String>? allowed(Expression expression) {
    if (expression is ParenthesizedExpression) {
      return allowed(expression.expression);
    }
    if (expression is! BinaryExpression) return null;
    if (expression.operator.lexeme == '&&') {
      final left = allowed(expression.leftOperand);
      final right = allowed(expression.rightOperand);
      return left == null || right == null ? null : {...left, ...right};
    }
    if (expression.operator.lexeme != '!=') return null;
    for (final pair in [
      (expression.leftOperand, expression.rightOperand),
      (expression.rightOperand, expression.leftOperand),
    ]) {
      final method = pair.$1;
      if (method is! PropertyAccess ||
          method.propertyName.name != 'method' ||
          !_dartFrog(method.propertyName.element)) {
        continue;
      }
      final request = method.target;
      if (request is! PrefixedIdentifier ||
          request.identifier.name != 'request' ||
          !_dartFrog(request.identifier.element) ||
          context == null ||
          request.prefix.element != context) {
        continue;
      }
      final member = _element(pair.$2);
      final value = member is GetterElement ? member.variable : member;
      if (value is! FieldElement ||
          value.enclosingElement.name != 'HttpMethod' ||
          !_dartFrog(value)) {
        continue;
      }
      final name = value.name?.toUpperCase();
      if (name != null &&
          const {
            'GET',
            'POST',
            'PUT',
            'PATCH',
            'DELETE',
            'HEAD',
            'OPTIONS',
            'TRACE',
            'CONNECT',
          }.contains(name)) {
        return {name};
      }
    }
    return null;
  }

  return (allowed(guard.expression)?.toList() ?? <String>[])..sort();
}

Element? _element(Expression expression) => switch (expression) {
  PrefixedIdentifier value => value.identifier.element,
  PropertyAccess value => value.propertyName.element,
  SimpleIdentifier value => value.element,
  _ => null,
};

int? _integer(Expression expression) {
  if (expression is IntegerLiteral) return expression.value;
  final element = _element(expression);
  final variable = element is GetterElement ? element.variable : element;
  return variable is VariableElement
      ? variable.computeConstantValue()?.toIntValue()
      : null;
}

bool _dartFrog(Element? element) =>
    element?.library?.firstFragment.source.uri.toString().startsWith(
      'package:dart_frog/',
    ) ??
    false;
