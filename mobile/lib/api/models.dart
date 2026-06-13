/// Dart mirrors of the Worker's JSON shapes. The Worker `serialize()`s rows so
/// `metadata` arrives as a decoded object (not a JSON string) on entities and
/// relationships; everything else is plain scalars (DESIGN.md, Data Model).
library;

const entityTypes = <String>[
  'character',
  'location',
  'faction',
  'lore',
  'story',
  'chapter',
  'event',
  'ability',
];

const statuses = <String>['stub', 'draft', 'canon', 'rejected'];

const mediaTypes = <String>['portrait', 'illustration', 'reference', 'logo'];

const relationshipTypes = <String>[
  'born_in',
  'resides_in',
  'member_of',
  'leader_of',
  'possesses',
  'friend_of',
  'rival_of',
  'parent_of',
  'sibling_of',
  'married_to',
  'related_to',
  'appears_in',
  'setting_of',
  'occurs_at',
  'involves',
  'depicts',
  'causes',
  'based_in',
];

const typeLabels = <String, String>{
  'character': 'Character',
  'location': 'Location',
  'faction': 'Faction',
  'lore': 'Lore',
  'story': 'Story',
  'chapter': 'Chapter',
  'event': 'Event',
  'ability': 'Ability',
};

const typePlurals = <String, String>{
  'character': 'Characters',
  'location': 'Locations',
  'faction': 'Factions',
  'lore': 'Lore',
  'story': 'Stories',
  'chapter': 'Chapters',
  'event': 'Events',
  'ability': 'Abilities',
};

const statusLabels = <String, String>{
  'stub': 'Stub',
  'draft': 'Draft',
  'canon': 'Canon',
  'rejected': 'Rejected',
};

/// Edge labels read from the source side ("Guli —born_in→ Bangsur").
const relationshipLabels = <String, String>{
  'born_in': 'born in',
  'resides_in': 'resides in',
  'member_of': 'member of',
  'leader_of': 'leader of',
  'possesses': 'possesses',
  'friend_of': 'friend of',
  'rival_of': 'rival of',
  'parent_of': 'parent of',
  'sibling_of': 'sibling of',
  'married_to': 'married to',
  'related_to': 'related to',
  'appears_in': 'appears in',
  'setting_of': 'setting of',
  'occurs_at': 'occurs at',
  'involves': 'involves',
  'depicts': 'depicts',
  'causes': 'causes',
  'based_in': 'based in',
};

/// Edge labels read from the target side ("Bangsur ← born_in — Guli").
const relationshipInverseLabels = <String, String>{
  'born_in': 'birthplace of',
  'resides_in': 'home of',
  'member_of': 'has member',
  'leader_of': 'led by',
  'possesses': 'wielded by',
  'friend_of': 'friend of',
  'rival_of': 'rival of',
  'parent_of': 'child of',
  'sibling_of': 'sibling of',
  'married_to': 'married to',
  'related_to': 'related to',
  'appears_in': 'features',
  'setting_of': 'set in',
  'occurs_at': 'site of',
  'involves': 'involved in',
  'depicts': 'depicted by',
  'causes': 'caused by',
  'based_in': 'base of',
};

class Entity {
  final String id;
  final String slug;
  final String type;
  final String? parentId;
  final String name;
  final String status;
  final String summary;
  final String content;
  final Map<String, dynamic> metadata;
  final String createdAt;
  final String updatedAt;

  Entity({
    required this.id,
    required this.slug,
    required this.type,
    required this.parentId,
    required this.name,
    required this.status,
    required this.summary,
    required this.content,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Entity.fromJson(Map<String, dynamic> j) => Entity(
        id: j['id'] as String,
        slug: j['slug'] as String,
        type: j['type'] as String,
        parentId: j['parent_id'] as String?,
        name: j['name'] as String,
        status: j['status'] as String,
        summary: (j['summary'] as String?) ?? '',
        content: (j['content'] as String?) ?? '',
        metadata: (j['metadata'] as Map?)?.cast<String, dynamic>() ?? {},
        createdAt: j['created_at'] as String,
        updatedAt: j['updated_at'] as String,
      );

  List<String> get tags {
    final t = metadata['tags'];
    if (t is List) return t.map((e) => e.toString()).toList();
    return const [];
  }

  String get typeLabel => typeLabels[type] ?? type;
  String get statusLabel => statusLabels[status] ?? status;
}

class Relationship {
  final String id;
  final String sourceId;
  final String targetId;
  final String type;
  final String? label;
  final Map<String, dynamic> metadata;
  final String createdAt;

  Relationship({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.type,
    required this.label,
    required this.metadata,
    required this.createdAt,
  });

  factory Relationship.fromJson(Map<String, dynamic> j) => Relationship(
        id: j['id'] as String,
        sourceId: j['source_id'] as String,
        targetId: j['target_id'] as String,
        type: j['type'] as String,
        label: j['label'] as String?,
        metadata: (j['metadata'] as Map?)?.cast<String, dynamic>() ?? {},
        createdAt: j['created_at'] as String,
      );
}

class Media {
  final String id;
  final String entityId;
  final String r2Key;
  final String mediaType;
  final String? altText;
  final String createdAt;

  Media({
    required this.id,
    required this.entityId,
    required this.r2Key,
    required this.mediaType,
    required this.altText,
    required this.createdAt,
  });

  factory Media.fromJson(Map<String, dynamic> j) => Media(
        id: j['id'] as String,
        entityId: j['entity_id'] as String,
        r2Key: j['r2_key'] as String,
        mediaType: j['media_type'] as String,
        altText: j['alt_text'] as String?,
        createdAt: j['created_at'] as String,
      );
}

/// GET /api/entities/:id — the entity plus its edges and media in one payload.
class EntityDetail extends Entity {
  final List<Relationship> relationships;
  final List<Media> media;

  EntityDetail({
    required super.id,
    required super.slug,
    required super.type,
    required super.parentId,
    required super.name,
    required super.status,
    required super.summary,
    required super.content,
    required super.metadata,
    required super.createdAt,
    required super.updatedAt,
    required this.relationships,
    required this.media,
  });

  factory EntityDetail.fromJson(Map<String, dynamic> j) {
    final base = Entity.fromJson(j);
    return EntityDetail(
      id: base.id,
      slug: base.slug,
      type: base.type,
      parentId: base.parentId,
      name: base.name,
      status: base.status,
      summary: base.summary,
      content: base.content,
      metadata: base.metadata,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      relationships: ((j['relationships'] as List?) ?? [])
          .map((e) => Relationship.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      media: ((j['media'] as List?) ?? [])
          .map((e) => Media.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// A lighter row used by backlinks (GET /api/entities/:id/backlinks).
class EntityRef {
  final String id;
  final String slug;
  final String type;
  final String name;
  final String status;
  final String summary;

  EntityRef({
    required this.id,
    required this.slug,
    required this.type,
    required this.name,
    required this.status,
    required this.summary,
  });

  factory EntityRef.fromJson(Map<String, dynamic> j) => EntityRef(
        id: j['id'] as String,
        slug: j['slug'] as String,
        type: j['type'] as String,
        name: j['name'] as String,
        status: j['status'] as String,
        summary: (j['summary'] as String?) ?? '',
      );
}

class EraRef {
  final String id;
  final String slug;
  final String name;

  EraRef({required this.id, required this.slug, required this.name});

  factory EraRef.fromJson(Map<String, dynamic> j) => EraRef(
        id: j['id'] as String,
        slug: j['slug'] as String,
        name: j['name'] as String,
      );
}

/// GET /api/timeline — events sorted chronologically plus the era bands.
class TimelineResult {
  final List<Entity> items;
  final List<EraRef> eras;
  TimelineResult({required this.items, required this.eras});
}

/// The standard list envelope: { items, total, limit, offset }.
class EntityPage {
  final List<Entity> items;
  final int total;
  final int limit;
  final int offset;
  EntityPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });
}
