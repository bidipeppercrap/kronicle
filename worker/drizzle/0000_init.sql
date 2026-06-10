CREATE TABLE `entities` (
	`id` text PRIMARY KEY NOT NULL,
	`slug` text NOT NULL,
	`type` text NOT NULL,
	`parent_id` text,
	`name` text NOT NULL,
	`status` text DEFAULT 'stub' NOT NULL,
	`summary` text DEFAULT '' NOT NULL,
	`content` text DEFAULT '' NOT NULL,
	`metadata` text DEFAULT '{}' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`parent_id`) REFERENCES `entities`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "entities_status_check" CHECK("entities"."status" IN ('stub', 'draft', 'canon', 'rejected'))
);
--> statement-breakpoint
CREATE UNIQUE INDEX `entities_slug_unique` ON `entities` (`slug`);--> statement-breakpoint
CREATE INDEX `idx_entities_type_status` ON `entities` (`type`,`status`);--> statement-breakpoint
CREATE INDEX `idx_entities_parent_id` ON `entities` (`parent_id`);--> statement-breakpoint
CREATE TABLE `media` (
	`id` text PRIMARY KEY NOT NULL,
	`entity_id` text NOT NULL,
	`r2_key` text NOT NULL,
	`media_type` text NOT NULL,
	`alt_text` text,
	`created_at` text NOT NULL,
	FOREIGN KEY (`entity_id`) REFERENCES `entities`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `relationships` (
	`id` text PRIMARY KEY NOT NULL,
	`source_id` text NOT NULL,
	`target_id` text NOT NULL,
	`type` text NOT NULL,
	`label` text,
	`metadata` text DEFAULT '{}' NOT NULL,
	`created_at` text NOT NULL,
	FOREIGN KEY (`source_id`) REFERENCES `entities`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`target_id`) REFERENCES `entities`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uq_relationships_edge` ON `relationships` (`source_id`,`target_id`,`type`);