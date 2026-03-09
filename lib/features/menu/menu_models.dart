class MenuResponse {
  final List<MenuCategory> menu;
  MenuResponse({required this.menu});

  factory MenuResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['menu'] as List? ?? [])
        .map((e) => MenuCategory.fromJson(e as Map<String, dynamic>))
        .toList();
    return MenuResponse(menu: list);
  }
}

class MenuCategory {
  final String id;
  final String name;
  final int sortOrder;
  final bool isActive;
  final List<MenuItem> items;

  MenuCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.isActive,
    required this.items,
  });

  factory MenuCategory.fromJson(Map<String, dynamic> json) {
    return MenuCategory(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      sortOrder: (json['sort_order'] ?? 0) as int,
      isActive: (json['is_active'] ?? true) as bool,
      items: (json['items'] as List? ?? [])
          .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MenuItem {
  final String id;
  final String name;
  final String? description;
  final String? imageUrl;
  final bool isActive;
  final List<MenuVariant> variants;

  MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.isActive,
    required this.variants,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      imageUrl: (json['image_url'] ?? json['imageUrl']) as String?,
      isActive: (json['is_active'] ?? true) as bool,
      variants: (json['variants'] as List? ?? [])
          .map((e) => MenuVariant.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MenuVariant {
  final String id;
  final String name;
  final String priceAed;
  final bool isActive;
  final int sortOrder;

  MenuVariant({
    required this.id,
    required this.name,
    required this.priceAed,
    required this.isActive,
    required this.sortOrder,
  });

  factory MenuVariant.fromJson(Map<String, dynamic> json) {
    return MenuVariant(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      priceAed: json['price_aed']?.toString() ?? '0.00',
      isActive: (json['is_active'] ?? true) as bool,
      sortOrder: (json['sort_order'] ?? 0) as int,
    );
  }
}
