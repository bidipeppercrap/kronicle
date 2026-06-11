CREATE TABLE `entity_revisions` (
	`id` text PRIMARY KEY NOT NULL,
	`entity_id` text NOT NULL,
	`content` text NOT NULL,
	`created_at` text NOT NULL,
	FOREIGN KEY (`entity_id`) REFERENCES `entities`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `idx_revisions_entity_created` ON `entity_revisions` (`entity_id`,`created_at`);