import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EncoinsGrant {
  const EncoinsGrant({required this.amount, required this.description});

  final int amount;
  final String description;
}

class EncoinsGrantDialog extends StatefulWidget {
  const EncoinsGrantDialog({
    required this.userName,
    this.isWithdrawal = false,
    this.currentBalance,
  });

  final String userName;
  final bool isWithdrawal;
  final int? currentBalance;

  @override
  State<EncoinsGrantDialog> createState() => _EncoinsGrantDialogState();
}

class _EncoinsGrantDialogState extends State<EncoinsGrantDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      EncoinsGrant(
        amount: int.parse(_amountController.text),
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF191522),
      title: Text(
        widget.isWithdrawal ? 'Списать Encoins' : 'Выдать Encoins',
        style: const TextStyle(color: Colors.white),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.userName,
              style: const TextStyle(color: Colors.white70),
            ),
            if (widget.isWithdrawal && widget.currentBalance != null) ...[
              const SizedBox(height: 4),
              Text(
                'Баланс: ${widget.currentBalance} ENC',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Количество ENC',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF9B7AE8)),
                ),
              ),
              validator: (value) {
                final amount = int.tryParse(value ?? '');
                if (amount == null || amount < 1 || amount > 1000000000) {
                  return 'Введите число от 1 до 1 000 000 000';
                }
                if (widget.isWithdrawal &&
                    widget.currentBalance != null &&
                    amount > widget.currentBalance!) {
                  return 'На балансе только ${widget.currentBalance} ENC';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLength: 120,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: widget.isWithdrawal
                    ? 'Причина списания'
                    : 'Причина выдачи',
                hintText: widget.isWithdrawal
                    ? 'Например, возврат ошибочного начисления'
                    : 'Например, награда за приглашение',
                labelStyle: const TextStyle(color: Colors.white60),
                hintStyle: const TextStyle(color: Colors.white38),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF9B7AE8)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
        ),
        FilledButton(
          onPressed: _submit,
          style: widget.isWithdrawal
              ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
              : null,
          child: Text(widget.isWithdrawal ? 'Списать' : 'Выдать'),
        ),
      ],
    );
  }
}
