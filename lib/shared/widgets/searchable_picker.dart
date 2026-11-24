import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/turkish_text.dart';

/// [SearchablePicker] listesindeki bir seçenek.
class PickerItem<T> {
  const PickerItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.searchText = '',
  });

  final T value;
  final String label;
  final String? subtitle; // Seçenek altında küçük yazı
  final String searchText; // Aramada ek olarak taranan metin
}

/// Alanın hemen altında açılan, içinde arama kutusu bulunan seçim menüsü.
/// Yer yoksa yukarı doğru açılır; liste yüksekliği sınırlıdır ve kendi içinde kayar.
/// Arama büyük/küçük harf ve Türkçe karakter (ş, ı, ğ...) duyarsızdır.
class SearchablePicker<T> extends StatefulWidget {
  const SearchablePicker({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.searchHint = 'Ara...',
    this.emptyText = 'Sonuç bulunamadı',
    this.createLabel,
    this.onCreate,
  });

  final String label;
  final List<PickerItem<T>> items;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? errorText;
  final String searchHint;
  final String emptyText;

  /// Sonuç bulunamayınca "+ Yeni ..." düğmesinin yazısı (onCreate ile birlikte).
  final String? createLabel;

  /// Yeni kayıt oluşturur ve seçilecek değeri döndürür (vazgeçilirse null).
  final Future<T?> Function()? onCreate;

  @override
  State<SearchablePicker<T>> createState() => _SearchablePickerState<T>();
}

class _SearchablePickerState<T> extends State<SearchablePicker<T>> {
  final LayerLink _link = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  final TextEditingController _search = TextEditingController();
  final FocusNode _focus = FocusNode();
  OverlayEntry? _entry;
  String _query = '';

  bool get _isOpen => _entry != null;

  List<PickerItem<T>> get _filtered {
    final query = TurkishText.fold(_query.trim());
    if (query.isEmpty) return widget.items;
    return widget.items
        .where(
          (item) => TurkishText.fold(
            '${item.label} ${item.subtitle ?? ''} ${item.searchText}',
          ).contains(query),
        )
        .toList();
  }

  void _open() {
    if (_isOpen) return;
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final spaceBelow = screen.height - (origin.dy + size.height) - 16;
    final spaceAbove = origin.dy - 16;
    final openUp = spaceBelow < 230 && spaceAbove > spaceBelow;
    final maxHeight = (openUp ? spaceAbove : spaceBelow).clamp(150.0, 380.0);

    _search.clear();
    _query = '';
    _entry = OverlayEntry(
      builder: (context) => _buildOverlay(size.width, openUp, maxHeight),
    );
    Overlay.of(context).insert(_entry!);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isOpen) _focus.requestFocus();
    });
  }

  void _removeEntry() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _close() {
    if (!_isOpen) return;
    _removeEntry();
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    final onCreate = widget.onCreate;
    if (onCreate == null) return;
    _close();
    final created = await onCreate();
    if (created != null && mounted) widget.onChanged(created);
  }

  void _select(PickerItem<T> item) {
    widget.onChanged(item.value);
    _close();
  }

  Widget _buildOverlay(double width, bool openUp, double maxHeight) {
    final items = _filtered;
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: openUp ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: openUp ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(0, openUp ? -4 : 4),
          child: SizedBox(
            width: width,
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: theme.colorScheme.surface,
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                          child: TextField(
                            controller: _search,
                            focusNode: _focus,
                            decoration: InputDecoration(
                              hintText: widget.searchHint,
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 20),
                            ),
                            onChanged: (value) {
                              _query = value;
                              _entry?.markNeedsBuild();
                            },
                            onSubmitted: (_) {
                              final current = _filtered;
                              if (current.isNotEmpty) _select(current.first);
                            },
                          ),
                        ),
                        Flexible(
                          child: items.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.emptyText,
                                        style: TextStyle(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                      if (widget.onCreate != null) ...[
                                        const SizedBox(height: 10),
                                        FilledButton.tonalIcon(
                                          onPressed: _create,
                                          icon: const Icon(Icons.add),
                                          label: Text(
                                            widget.createLabel ?? 'Yeni ekle',
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.only(bottom: 6),
                                  itemCount: items.length,
                                  itemBuilder: (context, index) {
                                    final item = items[index];
                                    final selected = item.value == widget.value;
                                    return ListTile(
                                      dense: true,
                                      selected: selected,
                                      title: Text(
                                        item.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: item.subtitle == null
                                          ? null
                                          : Text(
                                              item.subtitle!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                      trailing: selected
                                          ? const Icon(Icons.check, size: 18)
                                          : null,
                                      onTap: () => _select(item),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _removeEntry();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    PickerItem<T>? selected;
    for (final item in widget.items) {
      if (item.value == widget.value) {
        selected = item;
        break;
      }
    }
    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        key: _fieldKey,
        onTap: _isOpen ? _close : _open,
        child: InputDecorator(
          isFocused: _isOpen,
          isEmpty: selected == null,
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: widget.errorText,
            isDense: false,
            // Üst boşluk biraz fazla: yazı üstten kesilmez, daha aşağıda durur.
            contentPadding: const EdgeInsets.fromLTRB(14, 22, 8, 14),
            suffixIcon: Icon(
              _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            ),
          ),
          child: Text(
            selected?.label ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}