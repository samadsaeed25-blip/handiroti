import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'staff_api.dart';

class StaffMenuControlScreen extends StatefulWidget {
  const StaffMenuControlScreen({super.key});

  @override
  State<StaffMenuControlScreen> createState() => _StaffMenuControlScreenState();
}

class _StaffMenuControlScreenState extends State<StaffMenuControlScreen> {
  final StaffApi _api = StaffApi();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cats = await _api.getAdminMenu();
      setState(() {
        _categories = (cats is List)
            ? cats.map((e) => (e as Map).cast<String, dynamic>()).toList()
            : <Map<String, dynamic>>[];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleCategory(String categoryId, bool isActive) async {
    try {
      await _api.updateCategory(categoryId: categoryId, isActive: isActive);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _toggleItem(String itemId, bool isActive) async {
    try {
      await _api.updateItem(itemId: itemId, isActive: isActive);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _toggleVariant(String variantId, bool isActive) async {
    try {
      await _api.updateVariant(variantId: variantId, isActive: isActive);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _createCategory() async {
    final result = await showDialog<_CategoryFormResult>(
      context: context,
      builder: (_) => _CategoryFormDialog(
        title: 'Create Category',
        initialName: '',
        initialIsActive: true,
      ),
    );
    if (result == null) return;

    try {
      await _api.createCategory(
        name: result.name,
        isActive: result.isActive,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category created')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _editCategory(Map<String, dynamic> c) async {
    final categoryId = (c['id'] ?? '').toString();
    final initialName = (c['name'] ?? '').toString();
    final initialIsActive = (c['is_active'] == true);

    final result = await showDialog<_CategoryFormResult>(
      context: context,
      builder: (_) => _CategoryFormDialog(
        title: 'Edit Category',
        initialName: initialName,
        initialIsActive: initialIsActive,
      ),
    );
    if (result == null) return;

    try {
      await _api.updateCategory(
        categoryId: categoryId,
        name: result.name,
        isActive: result.isActive,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _deleteCategory(String categoryId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Category'),
        content: const Text('Are you sure? This will delete the category and its items/variants.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _api.deleteCategory(categoryId: categoryId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _createItem(String catId) async {
    final result = await showDialog<_ItemFormResult>(
      context: context,
      builder: (_) => _ItemFormDialog(
        title: 'Create Item',
        initialName: '',
        initialDescription: '',
        initialImageUrl: '',
        initialBasePrice: 0.0,
        initialIsActive: true,
      ),
    );
    if (result == null) return;

    try {
      await _api.createItem(
        categoryId: catId,
        name: result.name,
        // ✅ FIX: null-safe
        description: (result.description ?? ''),
        imageUrl: result.imageUrl,
        // ✅ FIX: null-safe
        basePriceAed: (result.basePrice ?? 0.0),
        isActive: result.isActive,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item created')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _editItem(Map<String, dynamic> item, String categoryId) async {
    final itemId = (item['id'] ?? '').toString();

    final result = await showDialog<_ItemFormResult>(
      context: context,
      builder: (_) => _ItemFormDialog(
        title: 'Edit Item',
        initialName: (item['name'] ?? '').toString(),
        initialDescription: (item['description'] ?? '').toString(),
        initialImageUrl: (item['image_url'] ?? '').toString(),
        initialBasePrice: double.tryParse((item['base_price_aed'] ?? '0').toString()) ?? 0.0,
        initialIsActive: (item['is_active'] == true),
      ),
    );
    if (result == null) return;

    try {
      await _api.updateItem(
        itemId: itemId,
        categoryId: categoryId,
        name: result.name,
        // ✅ FIX: null-safe
        description: (result.description ?? ''),
        imageUrl: result.imageUrl,
        // ✅ FIX: null-safe
        basePriceAed: (result.basePrice ?? 0.0),
        isActive: result.isActive,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _deleteItem(String itemId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Item'),
        content: const Text('Are you sure? This will delete the item and its variants.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _api.deleteItem(itemId: itemId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _createVariant(String itemId) async {
    final result = await showDialog<_VariantFormResult>(
      context: context,
      builder: (_) => _VariantFormDialog(
        title: 'Create Variant',
        initialName: '',
        initialPrice: 0.0,
        initialIsActive: true,
      ),
    );
    if (result == null) return;

    try {
      await _api.createVariant(
        itemId: itemId,
        name: result.name,
        priceAed: result.price,
        isActive: result.isActive,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Variant created')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _editVariant(Map<String, dynamic> v, String itemId) async {
    final variantId = (v['id'] ?? '').toString();

    final result = await showDialog<_VariantFormResult>(
      context: context,
      builder: (_) => _VariantFormDialog(
        title: 'Edit Variant',
        initialName: (v['name'] ?? '').toString(),
        initialPrice: double.tryParse((v['price_aed'] ?? '0').toString()) ?? 0.0,
        initialIsActive: (v['is_active'] == true),
      ),
    );
    if (result == null) return;

    try {
      await _api.updateVariant(
        variantId: variantId,
        itemId: itemId,
        name: result.name,
        priceAed: result.price,
        isActive: result.isActive,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Variant updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _deleteVariant(String variantId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Variant'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _api.deleteVariant(variantId: variantId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Variant deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _uploadImageAndFill(TextEditingController imageCtrl, TextEditingController nameCtrl) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      String mime = 'image/jpeg';
      final lower = file.name.toLowerCase();
      if (lower.endsWith('.png')) mime = 'image/png';
      if (lower.endsWith('.webp')) mime = 'image/webp';

      final url = await _api.uploadMenuImage(
        fileName: nameCtrl.text.trim().isEmpty ? 'menu' : nameCtrl.text.trim(),
        mime: mime,
        base64: b64,
      );

      if (!mounted) return;
      imageCtrl.text = url;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image uploaded')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu Control'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: _createCategory,
            icon: const Icon(Icons.add),
            tooltip: 'Add Category',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Text(_error!, style: theme.textTheme.bodyMedium))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _categories.length,
                    itemBuilder: (context, i) {
                      final c = _categories[i];
                      final catId = (c['id'] ?? '').toString();
                      final name = (c['name'] ?? '').toString();
                      final isActive = (c['is_active'] == true);
                      final items = (c['items'] is List) ? (c['items'] as List) : const [];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          title: Row(
                            children: [
                              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
                              const SizedBox(width: 10),
                              Switch(
                                value: isActive,
                                onChanged: (v) => _toggleCategory(catId, v),
                              ),
                            ],
                          ),
                          subtitle: Text('${items.length} items'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') await _editCategory(c);
                              if (v == 'delete') await _deleteCategory(catId);
                              if (v == 'add_item') await _createItem(catId);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'add_item', child: Text('Add Item')),
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                          children: [
                            for (final rawItem in items)
                              _ItemTile(
                                item: (rawItem as Map).cast<String, dynamic>(),
                                onToggleItem: _toggleItem,
                                onEditItem: (it) => _editItem(it, catId),
                                onDeleteItem: _deleteItem,
                                onToggleVariant: _toggleVariant,
                                onCreateVariant: _createVariant,
                                onEditVariant: _editVariant,
                                onDeleteVariant: _deleteVariant,
                                onUploadImage: _uploadImageAndFill,
                              ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.onToggleItem,
    required this.onEditItem,
    required this.onDeleteItem,
    required this.onToggleVariant,
    required this.onCreateVariant,
    required this.onEditVariant,
    required this.onDeleteVariant,
    required this.onUploadImage,
  });

  final Map<String, dynamic> item;

  final Future<void> Function(String itemId, bool isActive) onToggleItem;
  final Future<void> Function(Map<String, dynamic> item) onEditItem;
  final Future<void> Function(String itemId) onDeleteItem;

  final Future<void> Function(String variantId, bool isActive) onToggleVariant;
  final Future<void> Function(String itemId) onCreateVariant;
  final Future<void> Function(Map<String, dynamic> v, String itemId) onEditVariant;
  final Future<void> Function(String variantId) onDeleteVariant;

  final Future<void> Function(TextEditingController imageCtrl, TextEditingController nameCtrl) onUploadImage;

  @override
  Widget build(BuildContext context) {
    final itemId = (item['id'] ?? '').toString();
    final name = (item['name'] ?? '').toString();
    final isActive = (item['is_active'] == true);
    final imageUrl = (item['image_url'] ?? '').toString();

    final variants = (item['variants'] is List) ? (item['variants'] as List) : const [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  if (imageUrl.trim().isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        imageUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 52, height: 52),
                      ),
                    )
                  else
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
                      ),
                      child: const Icon(Icons.fastfood),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          (item['description'] ?? '').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(value: isActive, onChanged: (v) => onToggleItem(itemId, v)),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') await onEditItem(item);
                      if (v == 'delete') await onDeleteItem(itemId);
                      if (v == 'add_variant') await onCreateVariant(itemId);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'add_variant', child: Text('Add Variant')),
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              if (variants.isNotEmpty) const Divider(height: 18),
              if (variants.isNotEmpty)
                Column(
                  children: [
                    for (final rv in variants)
                      _VariantRow(
                        v: (rv as Map).cast<String, dynamic>(),
                        onToggle: onToggleVariant,
                        onEdit: (vMap) => onEditVariant(vMap, itemId),
                        onDelete: onDeleteVariant,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.v,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> v;
  final Future<void> Function(String variantId, bool isActive) onToggle;
  final Future<void> Function(Map<String, dynamic> v) onEdit;
  final Future<void> Function(String variantId) onDelete;

  @override
  Widget build(BuildContext context) {
    final variantId = (v['id'] ?? '').toString();
    final name = (v['name'] ?? '').toString();
    final price = (v['price_aed'] ?? '').toString();
    final isActive = (v['is_active'] == true);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('AED $price', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8))),
          const SizedBox(width: 10),
          Switch(value: isActive, onChanged: (val) => onToggle(variantId, val)),
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'edit') await onEdit(v);
              if (val == 'delete') await onDelete(variantId);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryFormResult {
  _CategoryFormResult({required this.name, required this.isActive});
  final String name;
  final bool isActive;
}

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({
    required this.title,
    required this.initialName,
    required this.initialIsActive,
  });

  final String title;
  final String initialName;
  final bool initialIsActive;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  late final TextEditingController _nameCtrl;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _active = widget.initialIsActive;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(child: Text('Active')),
              Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
            ],
          )
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, _CategoryFormResult(name: name, isActive: _active));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ItemFormResult {
  _ItemFormResult({
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.basePrice,
    required this.isActive,
  });

  final String name;
  final String? description;
  final String imageUrl;
  final double? basePrice;
  final bool isActive;
}

class _ItemFormDialog extends StatefulWidget {
  const _ItemFormDialog({
    required this.title,
    required this.initialName,
    required this.initialDescription,
    required this.initialImageUrl,
    required this.initialBasePrice,
    required this.initialIsActive,
  });

  final String title;
  final String initialName;
  final String initialDescription;
  final String initialImageUrl;
  final double initialBasePrice;
  final bool initialIsActive;

  @override
  State<_ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<_ItemFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _imageCtrl;
  late final TextEditingController _priceCtrl;

  late bool _active;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _descCtrl = TextEditingController(text: widget.initialDescription);
    _imageCtrl = TextEditingController(text: widget.initialImageUrl);
    _priceCtrl = TextEditingController(text: widget.initialBasePrice.toStringAsFixed(2));
    _active = widget.initialIsActive;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _imageCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _imageCtrl,
              decoration: const InputDecoration(labelText: 'Image URL'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Base Price (AED)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: Text('Active')),
                Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;

            final price = double.tryParse(_priceCtrl.text.trim());

            Navigator.pop(
              context,
              _ItemFormResult(
                name: name,
                description: _descCtrl.text.trim(),
                imageUrl: _imageCtrl.text.trim(),
                basePrice: price,
                isActive: _active,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _VariantFormResult {
  _VariantFormResult({
    required this.name,
    required this.price,
    required this.isActive,
  });

  final String name;
  final double price;
  final bool isActive;
}

class _VariantFormDialog extends StatefulWidget {
  const _VariantFormDialog({
    required this.title,
    required this.initialName,
    required this.initialPrice,
    required this.initialIsActive,
  });

  final String title;
  final String initialName;
  final double initialPrice;
  final bool initialIsActive;

  @override
  State<_VariantFormDialog> createState() => _VariantFormDialogState();
}

class _VariantFormDialogState extends State<_VariantFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _priceCtrl = TextEditingController(text: widget.initialPrice.toStringAsFixed(2));
    _active = widget.initialIsActive;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _priceCtrl,
            decoration: const InputDecoration(labelText: 'Price (AED)'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(child: Text('Active')),
              Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            final price = double.tryParse(_priceCtrl.text.trim()) ?? 0.0;
            Navigator.pop(context, _VariantFormResult(name: name, price: price, isActive: _active));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
