import 'package:flutter/material.dart';
import 'package:strazh/shared/domain/models/gift.dart';
import 'package:strazh/features/gifts/data/services/encoins_service.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/features/gifts/presentation/widgets/animated_gift_card.dart';

class GiftSelection {
  const GiftSelection({required this.gift, required this.caption});

  final Gift gift;
  final String caption;
}

class GiftPickerDialog extends StatefulWidget {
  const GiftPickerDialog({super.key, required this.recipientName});

  final String recipientName;

  @override
  State<GiftPickerDialog> createState() => _GiftPickerDialogState();
}

class _GiftPickerDialogState extends State<GiftPickerDialog> {
  final _captionController = TextEditingController();
  List<Gift> _gifts = [];
  Gift? _selectedGift;
  int _balance = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        GiftService.getCatalog(),
        EncoinsService.getBalance(),
      ]);
      if (!mounted) return;
      setState(() {
        _gifts = results[0] as List<Gift>;
        _balance = results[1] as int;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Dialog(
        backgroundColor: const Color(0xFF17131F),
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    const Icon(Icons.redeem, color: Color(0xFFFFC86B)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Подарок',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Для ${widget.recipientName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9B7AE8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '$_balance ENC',
                        style: const TextStyle(
                          color: Color(0xFFD0BFFF),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white60),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              if (_isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFC86B)),
                  ),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Не удалось загрузить подарки:\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                )
              else ...[
                Flexible(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(14),
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                            childAspectRatio: 0.95,
                        ),
                    itemCount: _gifts.length,
                    itemBuilder: (context, index) {
                      final gift = _gifts[index];
                      final selected = gift.id == _selectedGift?.id;
                      final affordable = _balance >= gift.priceEnc;
                      return GestureDetector(
                        onTap: affordable
                            ? () => setState(() => _selectedGift = gift)
                            : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF49366B)
                                : const Color(0xFF25202F),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFFFFC86B)
                                  : Colors.white.withValues(alpha: 0.07),
                              width: selected ? 1.6 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 72,
                                height: 72,
                                child: GiftAnimation(
                                  name: gift.name,
                                  giftId: gift.id,
                                  animationUrl: gift.animationUrl,
                                  size: 72,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                gift.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: affordable
                                      ? Colors.white
                                      : Colors.white38,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${gift.priceEnc} ENC',
                                style: TextStyle(
                                  color: affordable
                                      ? const Color(0xFFFFD68A)
                                      : Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Column(
                    children: [
                      TextField(
                        controller: _captionController,
                        maxLength: 120,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Подпись к подарку (необязательно)',
                          hintStyle: const TextStyle(color: Colors.white38),
                          counterStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF25202F),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _selectedGift == null
                              ? null
                              : () => Navigator.pop(
                                  context,
                                  GiftSelection(
                                    gift: _selectedGift!,
                                    caption: _captionController.text.trim(),
                                  ),
                                ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF9B7AE8),
                            disabledBackgroundColor: Colors.white12,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: Text(
                            _selectedGift == null
                                ? 'Выберите подарок'
                                : 'Подарить за ${_selectedGift!.priceEnc} ENC',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
