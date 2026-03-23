# Stable UUID Requirement for Discere ETL

This document explains an architectural problem we are facing in the Discere app and outlines a critical requirement for the ETL pipeline that generates `discere_reference.db`.

## Context: The Two-Database Architecture

The Discere app separates data into two distinct SQLite databases:
1. `discere_reference.db`: The read-only catalog data (e.g., Species, Taxonomies, Images). This is generated entirely by the ETL script and shipped periodically as an asset update to the app.
2. `discere_user.db`: Read-write user data (e.g., Decks, FlashCard stats). This is maintained locally on the user's device.

## How Flashcard Stats Work

In Discere, users learn species using a spaced-repetition algorithm (SM-2). When a user reviews a flashcard, their learning progress is saved in the `discere_user.db` inside a table called `flashcard_stats`. 

This table needs to link the user's progress to the specific species they are learning. It does this by storing the `species_id` (the UUID from `discere_reference.db`).

## The Problem

When a user installs an app update containing a newly generated `discere_reference.db`, **their learning progress must remain perfectly intact.**

If the ETL script generates *random* UUIDs (e.g., a standard v4 UUID) for species every time it builds the database, the `species_id` for "White Shark" in the August database will be completely different from its `species_id` in the September database. 

If UUIDs change between ETL builds, the `species_id` saved in the user's `flashcard_stats` table will suddenly point to nothing. **The user will instantly lose all their learning progress.**

To prevent this data loss, the app is currently forced to run complex, messy workarounds (looking up and saving `external_id` and `external_source` tightly alongside every single flashcard progress update) just to serve as a permanent anchor in case the UUIDs shift out from under us.

## The Solution / Requirement

We need the ETL pipeline to generate **Deterministic (Stable) UUIDs** for all entities, especially Species. 

Instead of generating a random v4 UUID, the ETL should generate a stable **v5 UUID** based on the entity's unique external identifying information. 

For example, a species UUID should be deterministically generated using its strict `external_source` and `external_id` (e.g., hashing the string `'fishbase:12345'` against a static namespace).

### Why this fixes everything:
If the ETL guarantees that an entity *always* receives the exact same UUID across every single build, the UUID itself becomes our permanent anchor. 
1. We can safely drop `external_id` and `external_source` from the user's local database entirely, keeping the schema clean.
2. Whenever you ship a new `discere_reference.db`, user learning progress in `flashcard_stats` will map perfectly to the updated reference DB without requiring complex data migrations on the user's device.
